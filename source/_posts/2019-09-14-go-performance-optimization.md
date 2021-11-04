---
title: 聊聊Go内存优化和相关底层机制
layout: post
tags: go
categories: go
---

最近做的优化比较多，整理下和Go内存相关的一些东西。

## 一. 不要过早优化

虽是老生常谈，但确实需要在做性能优化的时候铭记在心，个人的体会:

1. first make it work, then measure, then optimize
2. 二八原则
3. 需求变更快
4. 对性能的主观直觉不靠谱

<!--more-->

## 二. 内存优化

Golang运行时的内存分配算法主要源自 Google 为 C 语言开发的TCMalloc算法，全称Thread-Caching Malloc。核心思路是层级管理，以降低锁竞争开销。Golang内存管理大概分为三层，每个线程(GPM中的P)都会自行维护一个独立的内存池(mcache)，进行内存分配时优先从mcache中分配(无锁)，当mcache内存不足时才会向全局内存池(mcentral)申请(有锁)，当mcentral内存不足时再向全局堆空间管理(mheap)中申请(有锁+按照固定大小切割)，最后mheap如果不足，则向OS申请(SysCall)。mcache -> mcentral -> mheap -> OS 代价逐层递增，Golang运行时的很多地方都有这种层级管理的思路，比如GPM调度模型中对G的分配，这种层级在并发运行时下，通常有比较好的性能表现。

以下讨论下内存优化(主要是优化分配和GC开销，而非内存占用大小)常用的手段。

### 1. 内存复用

关于内存复用最常见的手段就是内存池了，它缓存已分配但不再使用的对象，在下次分配时进行复用，以避免频繁的对象分配。

#### 1.1 sync.Pool

Go的`sync.Pool`包是Go官方提供的内存池，在使用sync.Pool时，需要注意:

1. sync.Pool是goroutine safe的，并发控制会带来少部分开销(经过多级缓存已经无锁优化，这部分开销大部分时候都不用过多关注)
2. sync.Pool无法设置大小，所以理论上只受限于GC临界值大小
3. sync.Pool中的对象不支持自定义过期时间及策略，go1.13前sync.Pool中的对象会在GC开始前全部清除，在go1.13中有优化，会留一部分Object，相当于延缓了收缩扩张的速度

sync.Pool适用于跨goroutine且需要动态伸缩的场景，典型的如网络层或日志层，每个连接(goroutine)都需要Pool，并且连接数是不稳定的。

#### 1.2 leakybuf

有时为了达成更轻量，更可控的复用，我们可能会根据应用场景自己造轮子，比如实现一个固定大小，不会被GC的内存池。比如shadowsocks-go的[LeakyBuf](https://github.com/shadowsocks/shadowsocks-go/blob/master/shadowsocks/leakybuf.go)就用channel巧妙实现了个[]byte Pool。

leakybuf这类Pool相较于sync.Pool的主要优势是不会被GC，但缺点是少了收缩性，设置大了浪费内存，设置小了复用作用不明显。因此它适用于能够提前预估池子大小的场景，在实践中，我们将其用在DB序列化层，其Worker数量固定，单个[]byte较大，也相对稳定。

#### 1.3 逻辑对象复用

复用的粒度不仅限于简单struct或slice，也可以是逻辑实体。比如我们游戏中每次生成地图NPC时，会根据配置初始化大量的属性和BUFF，涉及到很多小对象的分配，这里我们选择将整个NPC作为复用粒度，在NPC倒计时结束或被击败消失时，将NPC整理缓存在池子中，并重置其战斗状态和刷新时间。这种逻辑实体的复用不通用但往往有用，必要的时候可以派上用场。

#### 1.4. 原地复用

除了内存池这种"有借有还"的复用外，另一种常用的内存复用思路是就地复用，它主要用于切片这类容易重置的数据结构，比如下面是一个过滤切片中所有奇数的操作:

```go
s := []int{1,2,3,4,5}
ret := s[:0]
for i:=0; i<len(s); i++ {
    if s[i] & 1 == 1{
        ret = append(ret, s[i])
    }
}
```

另一个"黑科技"操作是[]byte to string:

```go
bs := make([]byte, 1000)
// 175 ns/op 底层会拷贝bs，保证string的字符常量语义
ss2 = string(bs)
// 2.48 ns/op 直接地址转换，慎用，破坏了string的字符常量语义，更改bs将影响到ss1 ！
ss1 = *(*string)(unsafe.Pointer(&bs))
```

切片的这类技巧经常用在网络层和算法层，有时候也能起到不错的效果。

### 2. 预分配

预分配主要针对map, slice这类数据结构，当你知道它要分配多大内存时，就提前分配，一是为了避免多次内存分配，二是为了减少space grow带来的数据迁移(map evacuate or slice copy)开销。

```go
n := 10
src := make([]int, n)

// 无预分配: 162 ns/op
var dst []int
for i:=0; i<n; i++ {
	dst = append(dst, src[i])
}

// 预分配，32.3 ns/op，提升了5倍
dst2 := make([]int, 0, n)
for i:=0; i<n; i++ {
	dst2 = append(dst2, src[i])
}

// 预分配+append...: 30.1 ns/op
dst2 = append(dst2, src...)

// 预分配+copy: 26.0 ns/op
copy(dst2, src)

```

可以看到，slice预分配对性能的提升是非常大的，这里为了简单起见，以纯粹的拷贝切片为例，而对于切片拷贝，应该使用go专门为优化slice拷贝提供的内置函数copy，如果抛开分配dst2的开销，`copy(dst2, src)`的运算速度达到0.311ns，是`append(dst, src...)`的20倍左右！

平时编码中养成预分配的习惯是有利而无害的，Go的一些代码分析工具如[prealloc](https://github.com/alexkohler/prealloc)可以帮助你检查可做的预分配优化。

有时候预分配的大小不一定是精确的，也可能模糊的，比如要将一个数组中所有的偶数选出来，那么可以预分配1/2的容量，在不是特别好估算大小的情况下，尽可能保守分配。

预分配的另一个思路就是对于一些频繁生成的大对象，比如我们逻辑中打包地图实体，这是个很大的pb协议，pb默认生成的内嵌消息字段全是指针，给指针赋值的过程中为了保证深拷贝语义需要频繁地分配这些各级字段的内存，为了优化分配内存次数，我们使用[gogoproto](https://github.com/gogo/protobuf)的nullable生成器选项来对这类消息生成嵌套的值字段而非指针字段，这样可以减少内存分配次数(但分配的数量是一样的)。

### 3. 避免不必要的分配

Go的逃逸分析+GC会让Gopher对指针很青睐，receiver，struct field, arguments, return value等，却容易忽略背后的开销(当然，大部分时候开发者确实不需要操心)。

#### 3.1 减少返回值逃逸

为了避免引用必要的时候也可以化切片为数组:

```go
// 创建并返回了一个切片，切片是引用语义，导致ret逃逸
func GetNineGrid1() []int {
	ret := make([]int, 9)
	return ret
}

// 创建了一个数组但返回了它的切片(相当于它的引用)，导致数组逃逸
func GetNineGrid2() []int {
	var ret [9]int
	return ret[:]
}

// 创建并返回数组，数组是值语义，因此不会逃逸
func GetNineGrid3() [9]int {
	return [9]int{}
}
```

这还不够，有时候还需要对计算流程进行优化:

```go
type Coord struct{
	X   int32
	Z   int32
}
func f1(c *Coord) *Coord {
	ret := Coord{
		X: 	c.X/2,
		Z: 	c.Z/2,
	}
	return &ret
}
func f2() int32 {
	c := &Coord{
		X: 2,
		Z: 4,
	}
	c2 := f1(c)
	return c2.X
}

// 优化后
func new_f1(c *Coord, ret *Coord) {
	ret.X = c.X/2,
	ret.Z = c.Z/2,
}
func new_f2() int32 {
    c := &Coord{
        X:  2,
        Z:  4,
    }
    ret := &Coord{}
    new_f1(c, ret)
    return ret.X
}
```

在上面的代码中，Go编译器会分析到f1的变量ret地址会返回，因此它不能分配在栈在(调用完成后，栈就回收了)，必须分配在堆上，这就是逃逸分析(escape analyze)。而对于f2中的变量c来说，虽然函数中用了c的地址，但都是用于其调用的子函数(此时f1的栈还有效)，并未返回或传到函数栈有效域外，因此f2中的c会分配到栈上。

在默认编译参数下，f1的ret并不会逃逸，这是因为f1会被内联的，f1的调用并不会有新的函数栈的扩展和收缩，都会在f2的函数栈上进行，由于f2中的变量都没有逃逸到f2之外，因此对f2的调用也不会有任何内存分配，可以通过`-gcflags -N -l`编译选项来禁用内联，并通过`-gcflags -m`打印逃逸分析信息。但内联也是有条件的(函数足够简单，不涉及Interface)，我们将在后面再聊到内联。

#### 3.2 化指针为值

可以将使用频繁并且简单的结构体比如前面的地图坐标Coord，使用值而不是指针，这样可以减少不必要的变量逃逸带来的GC开销。

#### 3.3 字符串操作优化

以下是一个简单的测试，并注有其benchmark性能数据:

```go
// 1834 ns/op	     880 B/op	      29 allocs/op
func stringSprintf() string {
	var s string
	v := "benmark"
	for i := 0; i < 10; i++ {
		s = fmt.Sprintf("%s[%s]", s, v)
	}
	return s
}

// 616 ns/op	     576 B/op	      10 allocs/op
func stringPlus() string {
	var s string
	v := "benmark"
	for i := 0; i < 10; i++ {
		s = s + "[" + v + "]"
	}
	return s
}

// 395 ns/op	     304 B/op	       3 allocs/op
func stringBuffer() string {
	var buffer bytes.Buffer
	v := "benmark"
	for i := 0; i < 10; i++ {
		buffer.WriteString("[")
		buffer.WriteString(v)
		buffer.WriteString("]")
	}
	return buffer.String()
}

// 218 ns/op	     248 B/op	       5 allocs/op
func stringBuilder() string {
	var builder strings.Builder
	v := "benmark"
	for i := 0; i < 10; i++ {
		builder.WriteString("[")
		builder.WriteString(v)
		builder.WriteString("]")
	}
	return builder.String()
}
```


导致内存分配差异如此大的主要原因是string是常量语义，每次在构造新的string时，都会将之前string的底层[]byte拷贝一次，在执行多次string拼接时，`strings.Builder`和`bytes.Buffer`会缓存中间生成的[]byte，直到真正需要string结果时再调用它们的`String()`返回，避免了生成不必要的string中间结果，因此在多次拼接字符串的场景，`strings.Builder`和`bytes.Buffer`是更好的选择。

简单总结下:

- `fmt.Sprintf`: 适用于将其它类型格式化为字符串，灵活性高，但由于逃逸会导致大量的内存分配(后面讲逃逸会再次提到)
- `+`: 适用于少量的的常量字符串拼接，易读性高
- `bytes.Buffer`: 有比slice默认更激进的cap分配，它的`String()`方法需要拷贝。适用于大量的字符串的二进制拼接，如网络层。
- `strings.Builder`: 底层使用slice默认cap分配，主要的优点是调用`String()`不需要拷贝(直接地址转换)，适用于要求输出结果是string的地方


## 三 逃逸和内联

### 1. 逃逸分析

前面简单提了下逃逸分析，这里我们再深入讨论下，逃逸分析虽然好用，却并不免费，只有理解其内部机制，才能将收益最大化(开发效率vs运行效率)。逃逸分析的本质是当编译器发现函数变量将脱离函数栈有效域或被函数栈有效域外的变量所引用时时，将变量分配在堆上而不是栈在。也可以用两个不变性约束来描述:

1. 指向栈对象的指针不能存放在堆中
2. 指向栈对象的指针的生命周期不能超过该栈对象

典型导致逃逸的情形有:

1. 函数返回变量地址，或返回包含变量地址的struct，刚才已经讨论过
2. 将变量地址写入channel或sync.Pool，编译器无法获悉其它goroutine如何使用这个变量，也就无法在编译时决议变量的生命周期
3. 闭包也可能导致闭包上下文逃逸
4. 将变量地址赋给可扩容容器(如map,slice)时，slice/map超过cap重新分配时，将在堆上进行，栈的大小毕竟是固定和有限的
5. 涉及到Interface的很多逃逸优化都比较保守，如`reflect.ValueOf(x)`会显式调用`escapes(x)`导致x逃逸

第4点和第5点单独说下，以slice和空接口为例:

```go
func example() {
	s1 := make([]int, 10)
	s2 := make([]*int, 10)
	s3 := make([]interface{}, 10)
	a, b, c, d := 456, 456, 456, 456
	e := 123
	f := struct{X int; Z int}{}
	// 值语义slice, a将分配在栈上
	s1[1] = a

	// 引用语义slice, 引用b的地址，b将分配在堆上
	s2[2] = &b

	// 引用语义slice, 引用c的值，c将分配在栈上，但s3[3]对应interface{}中的data会分配一个int的空间，然后将c值赋给该堆内存
	s3[3] = c

	// 引用语义slice，引用d的地址，d将分配在堆上，s3[4]对应interface{}的data值即为d的地址
	s3[4] = &d

	// 引用语义slice，引用e的值，e同样将分配在栈上，但s3[5]本身也不再分配int堆内存(go1.15专门为0~255的小整数转interface作了[staticuint64s预分配优化](https://github.com/golang/go/blob/dev.boringcrypto.go1.15/src/runtime/iface.go#L532))
	s3[5] = e

	// 引用语义slice，引用f的值，f将分配在栈上，s3[6]对应interface{}的data会分配一个新的16B的空间，并拷贝f的值
	s3[6] = f

	// 通过println打印不会导致逃逸
	println(&a, &b, &c, &d, &e, &f, s3[3], s3[4])
}
```

由于栈空间是在编译期确定的，slice重分配只能发生在堆上。目前golang逃逸分析还不能完全分析slice的生命周期和扩容可能性，它会保守地保证slice元素只能指向堆内存(否则重分配后，浅拷贝会导致堆内存引用了栈内存)，因此可能会发生逃逸。

当slice元素为interface时，情况和s2类似，interface{}本质为引用语义，即为typ + pointer，这个pointer指向实际的data，参考我之前写的[go interface实现](https://wudaijun.com/2018/01/go-interface-implement/)。interface的pointer总是指针(不会类似Erlang Term一样对立即数进行优化，就地存储)，因此执行`s3[3] = c`时，本质会新分配一个对应空间，然后拷贝值，最后让pointer指向它。不让这个int值直接逃逸的原因是，执行该赋值后，本质上c和s3[3]是相互独立的，s3[3]为一个只读的int，而c的值是可以随时变化的，不应该相互影响，因此不能直接引用c的地址。虽然没有立即数优化，但是Go1.15之后，对小整数转interface{}进行了优化，也算聊胜于无。

Go官方一直在做interface逃逸相关的优化:

Go1.10开始提出的[devirtualization](https://github.com/golang/go/issues/19361)，编译器在能够知晓Interface具体对象的情况下(如`var i Iface = &myStruct{}`)，可以直接生成对象相关代码调用(通过插入类型断言)，而无需走Interface方法查找，同时助力逃逸分析。devirtualization还在不断完善(最初会导致receiver和参数逃逸，[这里](https://github.com/golang/go/issues/33160#issuecomment-512653356)有讨论，该问题2020年底已经在Go1.16中[Fix](https://go-review.googlesource.com/c/go/+/264837/5))。

Go1.15的[staticuint64s预分配优化](https://github.com/golang/go/blob/dev.boringcrypto.go1.15/src/runtime/iface.go#L532)避免了小整数转换为interface{}的内存分配。目前Go的逃逸分析策略还相对保守，比如前面代码的s2，既slice变量本身没有逃逸，也没有发生扩容，那么让slice以及其元素都在栈上应该是安全的。当然，好的逃逸分析需要在编译期更深入地理解程序，这本身也是在保证安全的前提下循序渐进的。

整体来说，目前的逃逸分析还在逐渐完善，还远没到真正成熟的地步，比如strings.Builder的源码:

```
// noescape hides a pointer from escape analysis.  noescape is
// the identity function but escape analysis doesn't think the
// output depends on the input. noescape is inlined and currently
// compiles down to zero instructions.
// USE CAREFULLY!
// This was copied from the runtime; see issues 23382 and 7921.
//go:nosplit
//go:nocheckptr
func noescape(p unsafe.Pointer) unsafe.Pointer {
	x := uintptr(p)
	return unsafe.Pointer(x ^ 0)
}

func (b *Builder) copyCheck() {
	if b.addr == nil {
		// This hack works around a failing of Go's escape analysis
		// that was causing b to escape and be heap allocated.
		// See issue 23382.
		// TODO: once issue 7921 is fixed, this should be reverted to
		// just "b.addr = b".
		b.addr = (*Builder)(noescape(unsafe.Pointer(b)))
	} else if b.addr != b {
		panic("strings: illegal use of non-zero Builder copied by value")
	}
}
```

noescape通过一个无用的位运算，切断了逃逸分析对指针的追踪(解除了参数与返回值的关联)，noescape被大量应用到Go Runtime源码中。

另一个饱受诟病的就是fmt.Printf系列(包括logrus.Debugf等所有带`...interface{}`参数的函数)，它也很容易导致逃逸，原理前面已经提过，`...interface{}`是`[]interface{}`的语法糖，逃逸分析不能确定`args []interface{}`切片是否会在函数中扩容，因此它要保证切片中的内容拷贝到堆上是安全的，那么就要保证切片元素不能引用栈内存，因此interface{}中的pointer只能指向堆内存。

虽然noescape能解决部分问题，但不建议轻易使用，除非是明确性能瓶颈的场景。

### 2. 内联

前面说过，逃逸分析+GC好用但不免费，但如果没有内联这个最佳辅助的话，前两者的代价怕是昂贵得用不起，所有函数返回的地方，都会树立起一道"墙"，任何想要从墙内逃逸到墙外的变量都会被分配在堆上，如:

```go
func NewCoord() *Coord {
	return &Coord{
		X: 	1,
		Z: 2,
	}
}
func foo() {
	c := NewCoord()
	return c.x
}
```

`NewCoord`这类简单的构造函数都会导致返回值分配在堆上，抽离函数的代价也更大。因此Go的内联，逃逸分析，GC是名副其实的三剑客，它们共同将其它语言避之不及的指针变得"物美价廉"。

Go1.9开始对内联做了比较大的运行时优化，开始支持[mid-stack inline](https://go.googlesource.com/proposal/+/master/design/19348-midstack-inlining.md)，talk链接在[这里](https://docs.google.com/presentation/d/1Wcblp3jpfeKwA0Y4FOmj63PW52M_qmNqlQkNaLj0P5o/edit#slide=id.g1d00ad65a7_2_17)。并且支持通过`-l`编译参数指定内联等级(参数定义参考[cmd/compile/internal/gc/inl.go](https://github.com/golang/go/blob/71a6a44428feb844b9dd3c4c8e16be8dee2fd8fa/src/cmd/compile/internal/gc/inl.go#L10-L17))。并且只在`-l=4`中提供了mid-stack inline，据Go官方统计，这大概可以提升9%的性能，也增加了11%左右的二进制大小。Go1.12开始默认支持了mid-stack inline。

我们目前还没有调整过内联参数，因为这是有利有弊的，过于激进的内联会导致生成的二进制文件更大，CPU instruction cache miss也可能会增加。默认等级的内联大部分时候都工作得很好并且稳定。

到Go1.17为止，虽然对Interface方法的调用还不能被内联(即使编译器知晓具体类型)，但是由于devirtualization优化的存在，已经和直接调用方法性能差距不大:

```go
type I interface {
	F() int
}
type A struct{
	x int
	y int
}
func (a *A) F() int {
	z := a.x + a.y
	return z
}
func BenchmarkX(b *testing.B) {
	b.ReportAllocs()
	for i:=0; i<b.N; i++ {
		// F() 会被内联 0.36 ns/op
		// var a = &A{}
		// a.F()
		
		// before go1.16 接口方法的receiver &A{}会逃逸 18.4 ns/op
		// go1.16+ &A{}不再逃逸 2.51 ns/op
		var iface I = &A{}
		iface.F()
	}
}
```

针对目前Go Interface 内联做得不够好的情况，一个实践是，在性能敏感场景，让你的公用API返回具体类型而非Interface，如`etcdclient.New`，`grpc.NewServer`等都是如此实践的，它们通过私有字段加公开方法让外部用起来像Interface一样，但数据逻辑层可能实践起来会有一些难度，因为Go的访问控制太弱了...

总的来说，golang 的 GC，内联，逃逸仍然在不断优化和完善，关注和升级最新golang版本，可能是最廉价的性能提升方式。
