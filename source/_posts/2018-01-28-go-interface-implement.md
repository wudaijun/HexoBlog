---
title: Go Interface 实现
layout: post
categories: go
tags: go
---

本文从源码的角度学习下Go接口的底层实现，以及接口赋值，反射，断言的实现原理。作为对比，用到了go1.8.6和go1.9.1两个版本。

### 1. eface

空接口通过eface结构体实现，位于runtime/runtime2.go: 

<!-- more -->

```go
// src/runtime/runtime2.go
// 空接口
type eface struct {
    _type *_type
    data  unsafe.Pointer
}
```

空接口(eface)有两个域，所指向对象的类型信息(\_type)和数据指针(data)。先看看`_type`字段：

```
// 所有类型信息结构体的公共部分
// src/rumtime/runtime2.go
type _type struct {
    size       uintptr         // 类型的大小
    ptrdata    uintptr      // size of memory prefix holding all pointers
    hash       uint32          // 类型的Hash值
    tflag      tflag              // 类型的Tags 
    align      uint8       // 结构体内对齐
    fieldalign uint8       // 结构体作为field时的对齐
    kind       uint8       // 类型编号 定义于runtime/typekind.go
    alg        *typeAlg    // 类型元方法 存储hash和equal两个操作。map key便使用key的_type.alg.hash(k)获取hash值
    gcdata    *byte            // GC相关信息
    str       nameOff   // 类型名字的偏移    
    ptrToThis typeOff    
}
```

\_type是go所有类型的公共描述，里面包含GC，反射等需要的细节，它决定data应该如何解释和操作，这也是它和C void*不同之处。
各个类型所需要的类型描述是不一样的，比如chan，除了chan本身外，还需要描述其元素类型，而map则需要key类型信息和value类型信息等:

```go
// src/runtime/type.go
// ptrType represents a pointer type.
type ptrType struct {
   typ     _type   // 指针类型 
   elem  *_type // 指针所指向的元素类型
}
type chantype struct {
    typ  _type        // channel类型
    elem *_type     // channel元素类型
    dir  uintptr
}
type maptype struct {
    typ           _type
    key           *_type
    elem          *_type
    bucket        *_type // internal type representing a hash bucket
    hmap          *_type // internal type representing a hmap
    keysize       uint8  // size of key slot
    indirectkey   bool   // store ptr to key instead of key itself
    valuesize     uint8  // size of value slot
    indirectvalue bool   // store ptr to value instead of value itself
    bucketsize    uint16 // size of bucket
    reflexivekey  bool   // true if k==k for all keys
    needkeyupdate bool   // true if we need to update key on an overwrite
}
```

这些类型信息的第一个字段都是`_type`(类型本身的信息)，接下来是一堆类型需要的其它详细信息(如子类型信息)，这样在进行类型相关操作时，可通过一个字(`typ *_type`)即可表述所有类型，然后再通过`_type.kind`可解析出其具体类型，最后通过地址转换即可得到类型完整的"\_type树"，参考`reflect.Type.Elem()`函数:

{% codeblock lang:go %}
// reflect/type.go
// reflect.rtype结构体定义和runtime._type一致  type.kind定义也一致(为了分包而重复定义)
// Elem()获取rtype中的元素类型，只针对复合类型(Array, Chan, Map, Ptr, Slice)有效
func (t *rtype) Elem() Type {
   switch t.Kind() {
   case Array:
      tt := (*arrayType)(unsafe.Pointer(t))
      return toType(tt.elem)
   case Chan:
      tt := (*chanType)(unsafe.Pointer(t))
      return toType(tt.elem)
   case Map:
      // 对Map来讲，Elem()得到的是其Value类型
      // 可通过rtype.Key()得到Key类型
      tt := (*mapType)(unsafe.Pointer(t))
      return toType(tt.elem)
   case Ptr:
      tt := (*ptrType)(unsafe.Pointer(t))
      return toType(tt.elem)
   case Slice:
      tt := (*sliceType)(unsafe.Pointer(t))
      return toType(tt.elem)
   }
   panic("reflect: Elem of invalid type")
}
{% endcodeblock %}

### 2. iface

iface结构体表示非空接口:

```go
// runtime/runtime2.go
// 非空接口
type iface struct {
    tab  *itab
    data unsafe.Pointer
}

// 非空接口的类型信息
type itab struct {
    inter  *interfacetype    // 接口定义的类型信息
    _type  *_type                // 接口实际指向值的类型信息
    link   *itab  
    bad    int32
    inhash int32
    fun    [1]uintptr             // 接口方法实现列表，即函数地址列表，按字典序排序
}

// runtime/type.go
// 非空接口类型，接口定义，包路径等。
type interfacetype struct {
   typ     _type
   pkgpath name
   mhdr    []imethod      // 接口方法声明列表，按字典序排序
}

// 接口的方法声明 
type imethod struct {
   name nameOff          // 方法名
   ityp typeOff                // 描述方法参数返回值等细节
}
```

非空接口(iface)本身除了可以容纳满足其接口的对象之外，还需要保存其接口的方法，因此除了data字段，iface通过tab字段描述非空接口的细节，包括接口方法定义，接口方法实现地址，接口所指类型等。iface是非空接口的实现，而不是类型定义，iface的真正类型为interfacetype，其第一个字段仍然为描述其自身类型的\_type字段。

为了提高查找效率，runtime中实现(interface_type, concrete_type) -> itab(包含具体方法实现地址等信息)的hash表:

```go
// runtime/iface.go
const (
   hashSize = 1009
)

var (
   ifaceLock mutex // lock for accessing hash
   hash      [hashSize]*itab
)
// 简单的Hash算法
func itabhash(inter *interfacetype, typ *_type) uint32 {
   h := inter.typ.hash
   h += 17 * typ.hash
   return h % hashSize
}

// 根据interface_type和concrete_type获取或生成itab信息
func getitab(inter *interfacetype, typ *_type, canfail bool) *itab {
   ...
    // 算出hash key
   h := itabhash(inter, typ)


   var m *itab
   ...
           // 遍历hash slot链表
      for m = (*itab)(atomic.Loadp(unsafe.Pointer(&hash[h]))); m != nil; m = m.link {
         // 如果在hash表中找到则返回
         if m.inter == inter && m._type == typ {
            if m.bad {
               if !canfail {
                  additab(m, locked != 0, false)
               }
               m = nil
            }
            ...
            return m
         }
      }
   }
    // 如果没有找到，则尝试生成itab(会检查是否满足接口)
   m = (*itab)(persistentalloc(unsafe.Sizeof(itab{})+uintptr(len(inter.mhdr)-1)*sys.PtrSize, 0, &memstats.other_sys))
   m.inter = inter
   m._type = typ
   additab(m, true, canfail)
   if m.bad {
      return nil
   }
   return m
}

// 检查concrete_type是否符合interface_type 并且创建对应的itab结构体 将其放到hash表中
func additab(m *itab, locked, canfail bool) {
   inter := m.inter
   typ := m._type
   x := typ.uncommon()

   ni := len(inter.mhdr)
   nt := int(x.mcount)
   xmhdr := (*[1 << 16]method)(add(unsafe.Pointer(x), uintptr(x.moff)))[:nt:nt]
   j := 0
   for k := 0; k < ni; k++ {
      i := &inter.mhdr[k]
      itype := inter.typ.typeOff(i.ityp)
      name := inter.typ.nameOff(i.name)
      iname := name.name()
      ipkg := name.pkgPath()
      if ipkg == "" {
         ipkg = inter.pkgpath.name()
      }
      for ; j < nt; j++ {
         t := &xmhdr[j]
         tname := typ.nameOff(t.name)
         // 检查方法名字是否一致
         if typ.typeOff(t.mtyp) == itype && tname.name() == iname {
            pkgPath := tname.pkgPath()
            if pkgPath == "" {
               pkgPath = typ.nameOff(x.pkgpath).name()
            }
            // 是否导出或在同一个包
            if tname.isExported() || pkgPath == ipkg {
               if m != nil {
                    // 获取函数地址，并加入到itab.fun数组中
                  ifn := typ.textOff(t.ifn)
                  *(*unsafe.Pointer)(add(unsafe.Pointer(&m.fun[0]), uintptr(k)*sys.PtrSize)) = ifn
               }
               goto nextimethod
            }
         }
      }
      // didn't find method
      if !canfail {
         if locked {
            unlock(&ifaceLock)
         }
         panic(&TypeAssertionError{"", typ.string(), inter.typ.string(), iname})
      }
      m.bad = true
      break
   nextimethod:
   }
   if !locked {
      throw("invalid itab locking")
   }
   // 加到Hash Slot链表中
   h := itabhash(inter, typ)
   m.link = hash[h]
   m.inhash = true
   atomicstorep(unsafe.Pointer(&hash[h]), unsafe.Pointer(m))
}
```

可以看到，并不是每次接口赋值都要去检查一次对象是否符合接口要求，而是只在第一次生成itab信息，之后通过hash表即可找到itab信息。

### 3. 接口赋值

```go
type MyInterface interface {
   Print()
}

type MyStruct struct{}
func (ms MyStruct) Print() {}

func main() {
   a := 1
   b := "str"
   c := MyStruct{}
   var i1 interface{} = a
   var i2 interface{} = b
   var i3 MyInterface = c
   var i4 interface{} = i3
   var i5 = i4.(MyInterface)
   fmt.Println(i1, i2, i3, i4, i5)
}
```
用go1.8编译并反汇编:

    $GO1.8PATH/bin/go build -gcflags '-N -l' -o tmp tmp.go
    $GO1.8PATH/bin/go tool objdump -s "main\.main" tmp


```
// var i1 interface{} = a
test.go:16      0x1087146       488b442430                      MOVQ 0x30(SP), AX
test.go:16      0x108714b       4889442438                      MOVQ AX, 0x38(SP)
test.go:16      0x1087150       488d05a9e10000                  LEAQ 0xe1a9(IP), AX // 加载a的类型信息(int)
test.go:16      0x1087157       48890424                        MOVQ AX, 0(SP)
test.go:16      0x108715b       488d442438                      LEAQ 0x38(SP), AX // 加载a的地址
test.go:16      0x1087160       4889442408                      MOVQ AX, 0x8(SP)
test.go:16      0x1087165       e84645f8ff                      CALL runtime.convT2E(SB)
test.go:16      0x108716a       488b442410                      MOVQ 0x10(SP), AX // 填充i1的type和data
test.go:16      0x108716f       488b4c2418                      MOVQ 0x18(SP), CX 
test.go:16      0x1087174       48898424a0000000                MOVQ AX, 0xa0(SP)
test.go:16      0x108717c       48898c24a8000000                MOVQ CX, 0xa8(SP)
// var i2 interface{} = b
// 与i1类似 加载类型信息 调用convT2E
...
test.go:17      0x10871bc       e8ef44f8ff                      CALL runtime.convT2E(SB)
test.go:17      0x10871c1       488b442410                      MOVQ 0x10(SP), AX
test.go:17      0x10871c6       488b4c2418                      MOVQ 0x18(SP), CX
test.go:17      0x10871cb       4889842490000000                MOVQ AX, 0x90(SP)
test.go:17      0x10871d3       48898c2498000000                MOVQ CX, 0x98(SP)
// var i3 MyInterface = c
test.go:18      0x10871db       488d051e000800                  LEAQ 0x8001e(IP), AX // 加载c的类型信息(MyStruct)
test.go:18      0x10871e2       48890424                        MOVQ AX, 0(SP)
test.go:18      0x10871e6       488d442430                      LEAQ 0x30(SP), AX
test.go:18      0x10871eb       4889442408                      MOVQ AX, 0x8(SP)
test.go:18      0x10871f0       e86b45f8ff                      CALL runtime.convT2I(SB)
test.go:18      0x10871f5       488b442410                      MOVQ 0x10(SP), AX
test.go:18      0x10871fa       488b4c2418                      MOVQ 0x18(SP), CX
test.go:18      0x10871ff       4889842480000000                MOVQ AX, 0x80(SP)
test.go:18      0x1087207       48898c2488000000                MOVQ CX, 0x88(SP)
// var i4 interface{} = i3
test.go:19      0x108720f       488b842488000000                MOVQ 0x88(SP), AX
test.go:19      0x1087217       488b8c2480000000                MOVQ 0x80(SP), CX // CX = i3.itab
test.go:19      0x108721f       48898c24e0000000                MOVQ CX, 0xe0(SP) 
test.go:19      0x1087227       48898424e8000000                MOVQ AX, 0xe8(SP) // 0xe8(SP) = i3.data
test.go:19      0x108722f       48894c2448                      MOVQ CX, 0x48(SP) 
test.go:19      0x1087234       4885c9                          TESTQ CX, CX
test.go:19      0x1087237       7505                            JNE 0x108723e
test.go:19      0x1087239       e915020000                      JMP 0x1087453
test.go:19      0x108723e       8401                            TESTB AL, 0(CX)
test.go:19      0x1087240       488b4108                        MOVQ 0x8(CX), AX // (i3.itab+8) 得到 &i3.itab.typ，因此AX=i3.itab.typ 即iface指向对象的具体类型信息，这里是MyStruct
test.go:19      0x1087244       4889442448                      MOVQ AX, 0x48(SP) // 0x48(SP) = i3.itab.typ
test.go:19      0x1087249       eb00                            JMP 0x108724b
test.go:19      0x108724b       488b8424e8000000                MOVQ 0xe8(SP), AX // AX = i3.data
test.go:19      0x1087253       488b4c2448                      MOVQ 0x48(SP), CX // CX = i3.itab.typ
test.go:19      0x1087258       48894c2470                      MOVQ CX, 0x70(SP) // i4.typ = i3.itab.typ
test.go:19      0x108725d       4889442478                      MOVQ AX, 0x78(SP) // i4.data = i3.data
// var i5 = i4.(MyInterface)
test.go:20      0x1087262       48c78424f000000000000000        MOVQ $0x0, 0xf0(SP)
test.go:20      0x108726e       48c78424f800000000000000        MOVQ $0x0, 0xf8(SP)
test.go:20      0x108727a       488b442478                      MOVQ 0x78(SP), AX
test.go:20      0x108727f       488b4c2470                      MOVQ 0x70(SP), CX
test.go:21      0x1087284       488d1535530100                  LEAQ 0x15335(IP), DX
test.go:20      0x108728b       48891424                        MOVQ DX, 0(SP) // 压入 MyInterface 的 interfacetype
test.go:20      0x108728f       48894c2408                      MOVQ CX, 0x8(SP) // 压入 i4.type
test.go:20      0x1087294       4889442410                      MOVQ AX, 0x10(SP) // 压入 i4.data
test.go:20      0x1087299       e87245f8ff                      CALL runtime.assertE2I(SB) // func assertE2I(inter *interfacetype, e eface) (r iface)
...
```

可以看到编译器通过convT2E和convT2I将编译器已知的类型赋给接口(其中E代表eface，I代表iface，T代表编译器已知类型，即静态类型)，编译器知晓itab的布局，会在编译期检查接口是否适配，并且生成itab信息，因此编译器生成的convT2X调用是必然成功的。

对于接口间的赋值，将iface赋给eface比较简单，直接提取eface的interfacetype和data赋给iface即可。而反过来，则需要使用接口断言，接口断言通过assertE2I, assertI2I等函数来完成，这类assert函数根据使用方调用方式有两个版本:

```go
i5 := i4.(MyInterface)         // call conv.assertE2I
i5, ok := i4.(MyInterface)  //  call conv.AssertE2I2
```

下面看一下几个常用的conv和assert函数实现:

```go
// go1.8/src/runtime/iface.go
func convT2E(t *_type, elem unsafe.Pointer) (e eface) {
    if raceenabled {
        raceReadObjectPC(t, elem, getcallerpc(unsafe.Pointer(&t)), funcPC(convT2E))
    }
    if msanenabled {
        msanread(elem, t.size)
    }
    if isDirectIface(t) {
        // This case is implemented directly by the compiler.
        throw("direct convT2E")
    }
    x := newobject(t)
    // TODO: We allocate a zeroed object only to overwrite it with
    // actual data. Figure out how to avoid zeroing. Also below in convT2I.
    typedmemmove(t, x, elem)
    e._type = t
    e.data = x
    return
}

func convT2I(tab *itab, elem unsafe.Pointer) (i iface) {
    t := tab._type
    if raceenabled {
        raceReadObjectPC(t, elem, getcallerpc(unsafe.Pointer(&tab)), funcPC(convT2I))
    }
    if msanenabled {
        msanread(elem, t.size)
    }
    if isDirectIface(t) {
        // This case is implemented directly by the compiler.
        throw("direct convT2I")
    }
    x := newobject(t)
    typedmemmove(t, x, elem)
    i.tab = tab
    i.data = x
    return
}

func assertE2I(inter *interfacetype, e eface) (r iface) {
    t := e._type
    if t == nil {
        // explicit conversions require non-nil interface value.
        panic(&TypeAssertionError{"", "", inter.typ.string(), ""})
    }
    r.tab = getitab(inter, t, false)
    r.data = e.data
    return
}
```

在assertE2I中，我们看到了getitab函数，即`i5=i4.(MyInterface)`中，会去判断i4的concretetype(MyStruct)是否满足MyInterface的interfacetype，由于前面我们执行过`var i3 MyInterface = c`，因此hash[itabhash(MyInterface, MyStruct)]已经存在itab，所以无需再次检查接口是否满足，从hash表中取出itab即可(里面针对接口的各个方法实现地址都已经初始化完成)。

而在go1.9中，有一些优化:

1.对convT2x针对简单类型(如int32,string,slice)进行特例化优化(避免typedmemmove):

```
convT2E16, convT2I16
convT2E32, convT2I32
convT2E64, convT2I64
convT2Estring, convT2Istring
convT2Eslice, convT2Islice
convT2Enoptr, convT2Inoptr
```
据统计，在编译make.bash的时候，有93%的convT2x调用都可通过以上特例化优化。参考[这里](https://go-review.googlesource.com/c/go/+/36476)。

2.优化了剩余对convT2I的调用

由于itab由编译器生成(参考上面go1.8生成的汇编代码和convT2I函数)，可以直接由编译器将itab和elem直接赋给iface的tab和data字段，避免函数调用和typedmemmove。关于此优化可参考[1](https://go-review.googlesource.com/c/go/+/20901/9)和[2](https://go-review.googlesource.com/c/go/+/20902)。

具体汇编代码不再列出，感兴趣的同学可以自己尝试。
 
对接口的构造和转换本质上是对object的type和data两个字段的操作，对空接口eface来说，只需将type和data提取并填入即可，而对于非空接口iface构造和断言，需要判断object或eface是否满足接口定义，并生成对应的itab(包含接口类型，object类型，object接口实现方法地址等信息)，每个已初始化的iface都有itab字段，该字段的生成是通过hash表优化的，以及对于每个interfacetype <-> concrettype对，只需要生成一次itab，之后从hash表中取就可以了。由于编译器知晓itab的内存布局，因此在将iface赋给eface的时候可以避免函数调用，直接将iface.itab.typ赋给eface.typ。

### 4. 类型反射
 
#### 4.1 类型&值解析

类型和值解析无非就是将eface{}的\_type和data字段取出进行解析，针对TypeOf的实现很简单:

```
// 代码位于relect/type.go

// reflect.Type接口的实现为: reflect.rtype
// reflect.rtype结构体定义和runtime._type一样，只是实现了reflect.Type接口，实现了一些诸如Elem()，Name()之类的方法:

func TypeOf(i interface{}) Type {
    // emptyInterface结构体定义与eface一样，都是两个word(type和data)
    eface := *(*emptyInterface)(unsafe.Pointer(&i))
    return toType(eface.typ) // 将eface.typ赋给reflect.Type接口，供外部使用
}

 
```
要知道，对于复合类型，如Ptr, Slice, Chan, Map等，它们的type信息中包含其子类型的信息，如Slice元素类型，而其元素类型也可能是复合类型，因此type实际上是一颗"类型树"，可通过`reflect.Elem()`和`reflect.Key()`等API来获取这些子类型信息，但如果如果type不匹配(比如`reflect.TypeOf([]int{1,2}).Key()`)，会panic。
 
`reflect.ValueOf()`则要复杂一些，因为它需要根据type来决定数据应该如何被解释:

```
type Value struct {
    // 值的类型
    typ *rtype
    // 立即数或指向数据的指针
    ptr unsafe.Pointer
    // type flag uintptr
    // 指明值的类型，是否只读，ptr字段是否是指针等
    flag
}

func ValueOf(i interface{}) Value {
    if i == nil {
        return Value{}
    }

    escapes(i)

    return unpackEface(i)
}

// 将数据从interface{}解包为reflec.Value
func unpackEface(i interface{}) Value {
    e := (*emptyInterface)(unsafe.Pointer(&i))
    // NOTE: don't read e.word until we know whether it is really a pointer or not.
    t := e.typ
    if t == nil {
        return Value{}
    }
    f := flag(t.Kind())
    if ifaceIndir(t) {
        f |= flagIndir
    }
    return Value{t, e.word, f}
}
 
// 将数据由reflect.Value打包为interface{}
func packEface(v Value) interface{} {
    t := v.typ
    var i interface{}
    e := (*emptyInterface)(unsafe.Pointer(&i))
    // First, fill in the data portion of the interface.
    switch {
    case ifaceIndir(t):
        if v.flag&flagIndir == 0 {
            panic("bad indir")
        }
        ptr := v.ptr
        if v.flag&flagAddr != 0 {
            c := unsafe_New(t)
            typedmemmove(t, c, ptr)
            ptr = c
        }
        e.word = ptr
    case v.flag&flagIndir != 0:
        e.word = *(*unsafe.Pointer)(v.ptr)
    default:
        e.word = v.ptr
    }

    e.typ = t
    return i
}
 
// 将reflect.Value转换为interface{}，相当于reflect.ValueOf的逆操作
// 等价于: var i interface{} = (v's underlying value)
func (v Value) Interface() (i interface{}) {
   return valueInterface(v, true)
}

func valueInterface(v Value, safe bool) interface{} {
   if v.flag == 0 {
      panic(&ValueError{"reflect.Value.Interface", 0})
   }
   if safe && v.flag&flagRO != 0 {
      panic("reflect.Value.Interface: cannot return value obtained from unexported field or method")
   }
   if v.flag&flagMethod != 0 {
      v = makeMethodValue("Interface", v)
   }
   // 当interface{}作为子类型时，会产生类型为Interface的Value
   // 如 reflect.TypeOf(m).Elem().Kind() == Interface
   if v.kind() == Interface {
      if v.NumMethod() == 0 {
         return *(*interface{})(v.ptr)
      }
      return *(*interface {
         M()
      })(v.ptr)
   }
   return packEface(v)
}
 
```

和`reflect.Type.Elem()`一样，`reflect.Value`也提供一系列的方法进行值解析，如`Elem()`可以得到Interface或Ptr指向的值，`Index()`可以得到Array, Slice或String对应下标的元素等。但在使用这些API前要先通过`reflect.Type.Kind()`确认类型匹配，否则会panic。
 
#### 4.2 类型反射
 
 
类型&值解析实际上对将interface{}的type和data提出来，以`reflect.Type`和`reflect.Value`接口暴露给用户使用，而类型反射是指提供一个reflect.Type，我们可以创建一个对应类型的对象，这可以通过`reflect.New()`来完成：
 
```go
// reflect/value.go
// New returns a Value representing a pointer to a new zero value
// for the specified type. That is, the returned Value's Type is PtrTo(typ).
func New(typ Type) Value {
   if typ == nil {
      panic("reflect: New(nil)")
   }
   ptr := unsafe_New(typ.(*rtype))
   fl := flag(Ptr)
   return Value{typ.common().ptrTo(), ptr, fl}
}
 
 
// runtime/malloc.go
func newobject(typ *_type) unsafe.Pointer {
   return mallocgc(typ.size, typ, true)
}

//go:linkname reflect_unsafe_New reflect.unsafe_New
func reflect_unsafe_New(typ *_type) unsafe.Pointer {
   return newobject(typ)
}
```
 
PS: Go的包管理看来还是不够好用，为了达成reflect包和runtime包的"解耦"，先后使用和copy struct define和link method "黑科技"。
 
`reflect.New()`创建对应Type的对象并返回其指针，以下是一个简单的示例:
 
```
type User struct {
   UserId     int
   Name   string
}

func main() {
   x := User{UserId: 111}
   typ := reflect.TypeOf(x)
   // reflect.New返回的是*User 而不是User
   y := reflect.New(typ).Elem()
   for i:=0; i<typ.NumField(); i++ {
      // 根据每个struct field的type 设置其值
      fieldT := typ.Field(i) 
      fieldV := y.Field(i)
      kind := fieldT.Type.Kind()
      if kind == reflect.Int{
         fieldV.SetInt(123)
      } else if kind == reflect.String{
         fieldV.SetString("wudaijun")
      }
   }
   fmt.Println(y.Interface())
}
```
 
以上代码稍改一下，即可实现简单CSV解析：根据提供的struct原型，分析其字段，并一一映射到csv每一列，将csv读出的string转换为对应的struct field type，对于简单类型使用strconv即可完成，对于复合数据结构如Map, Slice，可使用json库来定义和解析。
 
 
`reflect.New()`和`reflect.Zero()`可用于创建Type对应的对象，除此之外，reflect包还提供了`reflect.MapOf()`, `reflect.SliceOf()`等方法用于基于现有类型创建复合类型。具体源码不再列出，参考reflect/type.go和reflect/value.go。
 
 
reflect提供的反射能力不可谓不强大，但在实际使用中仍然不够好用，一个因为Go本质上是静态类型语言，要提供"动态类型"的部分语义是比较复杂和不易用的，这有点像C++提供泛型编程，虽然强大，但也是把双刃剑。
 
参考:

1. [Golang汇编快速指南](https://studygolang.com/articles/2917)
2. [Go Interface源码剖析](http://legendtkl.com/2017/07/01/golang-interface-implement/)