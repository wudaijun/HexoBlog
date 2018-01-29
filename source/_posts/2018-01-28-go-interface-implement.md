---
title: Go Interface实现
layout: post
categories: go
tags: go
---

### 1. eface

空接口通过eface结构体实现，位于runtime/runtime2.go: 

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
 
这些类型信息的第一个字段都是`_type`(类型本身的信息)，接下来是一堆类型需要的其它详细信息(如子类型信息)，这样在进行类型相关操作时，可通过一个字(`typ *_type`)即可表述所有类型，然后再通过`_type.kind`可解析出其具体类型，最后通过地址转换即可得到类型完整的"\_type树"，参考reflect.Type.Elem()函数:
 
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

   h := itabhash(inter, typ)


   var m *itab
   ...
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
...
tmp.go:18 0x1087165 e84645f8ff CALL runtime.convT2E(SB)    // var i1 interface{} = a
...
tmp.go:19 0x10871bc e8ef44f8ff CALL runtime.convT2E(SB)    // var i2 interface{} = b
...
tmp.go:20 0x10871f0 e86b45f8ff CALL runtime.convT2I(SB)    // var i3 MyInterface = c
tmp.go:20       0x10871f5       488b442410                      MOVQ 0x10(SP), AX    // 返回的iface.itab地址
tmp.go:20       0x10871fa       488b4c2418                      MOVQ 0x18(SP), CX   // 返回的iface.data地址
tmp.go:20       0x10871ff       4889842480000000                MOVQ AX, 0x80(SP)  // i3.tab = iface.itab
tmp.go:20       0x1087207       48898c2488000000                MOVQ CX, 0x88(SP)  // i3.data = iface.data
tmp.go:21       0x108720f       488b842488000000                MOVQ 0x88(SP), AX
tmp.go:21       0x1087217       488b8c2480000000                MOVQ 0x80(SP), CX
tmp.go:21       0x108721f       48898c24e0000000                MOVQ CX, 0xe0(SP) // 0xe0(SP) = i3.tab
tmp.go:21       0x1087227       48898424e8000000                MOVQ AX, 0xe8(SP) // 0xe8(SP) = i3.data
tmp.go:21       0x108722f       48894c2448                      MOVQ CX, 0x48(SP)
...
// var i4 interface{} = i3
tmp.go:21       0x108724b       488b8424e8000000                MOVQ 0xe8(SP), AX    // 加载i3的data
tmp.go:21       0x1087253       488b4c2448                      MOVQ 0x48(SP), CX    // 加载i3的tab(即interfacetype地址)
tmp.go:21       0x1087258       48894c2470                      MOVQ CX, 0x70(SP)    // i4._type = i3.interfacetype
tmp.go:21       0x108725d       4889442478                      MOVQ AX, 0x78(SP)   // i4.data = i3.data
...
// var i5 = i4.(MyInterface)﻿​
tmp.go:22       0x1087299       e87245f8ff                      CALL runtime.assertE2I(SB)
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

1. 对convT2x针对简单类型(如int32,string,slice)进行特例化优化(避免typedmemmove):

```
convT2E16, convT2I16
convT2E32, convT2I32
convT2E64, convT2I64
convT2Estring, convT2Istring
convT2Eslice, convT2Islice
convT2Enoptr, convT2Inoptr
```
据统计，在编译make.bash的时候，有93%的convT2x调用都可通过以上特例化优化。参考[这里](https://go-review.googlesource.com/c/go/+/36476)。
 
2. 优化了剩余对convT2I的调用

由于itab由编译器生成(参考上面go1.8生成的汇编代码和convT2I函数)，可以直接由编译器将itab和elem直接赋给iface的tab和data字段，避免函数调用和typedmemmove。关于此优化可参考[1](https://go-review.googlesource.com/c/go/+/20901/9)和[2](https://go-review.googlesource.com/c/go/+/20902)。

具体汇编代码不在列出，感兴趣的同学可以自己尝试。

### 4. 类型反射
 
类型反射无非就是将eface{}的_type和data字段取出进行解析，针对TypeOf的实现很简单:

```
// 代码位于relect/type.go

// reflect.Type接口的实现为: reflect.rtype
// reflect.rtype结构体定义和runtime._type一样，只是实现了reflect.Type接口，实现了一些诸如Elem()，Name()之类的方法:

func TypeOf(i interface{}) Type {
    // emptyInterface结构体定义与eface一样，都是两个word(type和data)
    eface := *(*emptyInterface)(unsafe.Pointer(&i))
    return toType(eface.typ)
}

// reflect.Type.Elem()仅对复合类型有效(Array,Ptr,Map,Chan,Slice)，取出其中的子类型
func (t *rtype) Elem() Type {
    switch t.Kind() {
    case Array:
        tt := (*arrayType)(unsafe.Pointer(t))
        return toType(tt.elem)
    case Chan:
        tt := (*chanType)(unsafe.Pointer(t))
        return toType(tt.elem)
    case Map:
        tt := (*mapType)(unsafe.Pointer(t))
        // 对mapType来说，tt.elem实际上是value的类型，可通过t.Key()来获取key类型
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
```

reflect.ValueOf则要复杂一些，因为它需要根据type来决定数据应该如何被解释，因此实际上reflect.Value也包含类型信息，并且通过一个flag字段来标识只读属性，是否为指针等。

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

// reflect.Value的Elem()方法仅对引用类型(Ptr和Interface{})有效，返回其引用的值
func (v Value) Elem() Value {
    k := v.kind()
    switch k {
    case Interface:
        var eface interface{}
        if v.typ.NumMethod() == 0 {
            eface = *(*interface{})(v.ptr)
        } else {
            eface = (interface{})(*(*interface {
                M()
            })(v.ptr))
        }
        x := unpackEface(eface)
        if x.flag != 0 {
            x.flag |= v.flag & flagRO
        }
        return x
    case Ptr:
        ptr := v.ptr
        if v.flag&flagIndir != 0 {
            ptr = *(*unsafe.Pointer)(ptr)
        }
        // The returned value's address is v's value.
        if ptr == nil {
            return Value{}
        }
        tt := (*ptrType)(unsafe.Pointer(v.typ))
        typ := tt.elem
        fl := v.flag&flagRO | flagIndir | flagAddr
        fl |= flag(typ.Kind())
        return Value{typ, ptr, fl}
    }
    panic(&ValueError{"reflect.Value.Elem", v.kind()})
}

```