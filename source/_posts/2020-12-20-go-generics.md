---
title: Go 泛型特性速览
layout: post
categories: golang
tags: golang
---

>> 2022.1.22 更新: 最近一年，Go泛型已经从草案，过渡到提案，并开始实现。[Go1.18](https://tip.golang.org/doc/go1.18)实现了初版泛型，最终方案相较之前的泛型草案，将**类型列表约束(type list in constraint)**进一步丰富完善为**类型集约束(type sets of constraints)**的概念，本文内容已随最新文档更新。

之前我在[编程范式游记](https://wudaijun.com/2019/05/programing-paradigm/)中介绍了OOP中的子类化(subtype，也叫子类型多态subtype polymorphism)和泛型(generics，也叫参数多态parametric polymorphism或类型参数type parameters)，关于两者的区别和比较可以参考那篇文章，在其中我吐槽了Go目前对泛型支持的匮乏，Go泛型最初在[Go 2](https://github.com/golang/go/wiki/Go)中讨论，目前已经在Go1.18中正式实现，随着Go泛型设计和实现的细节也越来越清晰，我们从最新的[Go泛型文档](https://go.googlesource.com/proposal/+/refs/heads/master/design/43651-type-parameters.md)来了解下Go泛型设计上有哪些考量和取舍。

PS. 虽然Go官方文档仍然沿用社区惯用的"泛型(generics)"术语，由于主流语言都有自己不同的泛型支持，如Java基于**编译期类型擦除**的泛型(伪泛型)，C++的**图灵完备**的模板机制(支持模板元编程的真泛型)等，为了避免概念混淆，将Go泛型理解为**类型参数(type parameters)**更精确，它不支持C++那样灵活的模板元编程，但比Java这种运行时擦除类型信息的补丁实现更优，另外，关于运算符泛型，Go也提出了一套新的解决方案。


#### 1. 最简原型

先从最简单的泛型定义开始:

```go
// Define
func Print[T] (s []T) {
	for _, v := range s {
		fmt.Println(v)
	}
}
// Call
Print[int]([]int{1, 2, 3})
```

语法上和其它语言泛型大同小异，泛型的本质是将**类型参数化**，Go中用函数名后的`[]`定义类型参数。以上声明对C++开发者来说非常亲切的(只是换了一种语法形式)，实际上这在Go中是错误的泛型函数声明，因为它没有指明类型参数约束(constraints)。

<!--more-->

#### 2. 类型约束

与C++不同，Go在一开始就确定要引入泛型的类型参数约束(bounded generic types，subtype与generics的有机结合)，并且借机吐槽了C++的无约束泛型类型参数，因为这会带来非常难调试的编译时报错。在上例中，即使Print内部没有调用T的任何方法，也需要通过新引入的`any`关键字来表示任意类型约束(考虑下不能未显示指定约束则缺省即为`any`的原因)。因此正确的Print声明方式为:

```go
func Print[T any] (s []T) { ...
```

PS: 任意类型不代表不能执行任意操作，如声明变量，赋值，取地址(`&`)，取类型(`.(type)`)等。

那么除去`any`，如何表示一个有效的类型约束，参考其它支持bounded generic types语言的做法，如C#/Java，自然go interface是不二之选，因为go interface本质就是做subtype，而subtype本身主要就是服务于静态语言的type checker的。因此subtype也可以辅助编译器完善对类型参数的检查。使用interface做类型参数约束的函数看起来是这个样子:

```go
func Stringify[T fmt.Stringer](s []T) (ret []string) {
	for _, v := range s {
		ret = append(ret, v.String()) D
	}
	return ret
}
```

这里有一个有意思的问题，为什么Go编译器不直接用Stringify函数中对T的各种函数调用，自动推敲生成一个匿名interface呢，如此对Stringify来说，外部满足`fmt.Stringer`的类型，仍然能够使用Stringify，并且这本身也是Go隐式接口的一大便利(不依赖于subclass来实现subtype，Go没有subclass)，其它像C++/C#/Java依赖于显示接口/基类继承声明得语言，是无法做到的。关于这一点，Go官方的解释是，如果接口隐式推敲，少了显式接口这层"契约"，那么Stringify的一个很小的改动都可能导致上层调用不可用，这不利于构建大型项目。调用方只需要关心它是否满足接口约束，而不应该也不需要去阅读Stringify的代码来知道它可能调用T的哪些函数。

既然选定了用interface来做类型参数约束，那么再来看`any`，它实际上就和`interface{}`没有区别的，任意类型都满足`interface{}`接口，因此实际上Print也可以声明为 `func Print[T interface{}] (s []T)`，但是官方觉得在写任意类型的泛型的时候，每次写`interface{}`太麻烦了(符合golang的极简思维)，因此还是觉得应该保留`any`关键字，作为`interface{}`的别名，但是在除了泛型类型约束之外，常规空接口仍然用`interface{}`而不能用`any`，解释是不希望新增的泛型给以前的代码带来影响...

#### 3. 泛型类型

除了泛型函数外，基于泛型也可以构建新的类型，如:

```go
// 定义一个可保存任意类型的切片
type Vector[T any] []T
// 实现泛型类Vector方法
func (v *Vector[T]) Push(x T) { *v = append(*v, x) }
// 实例化泛型类型 Vecter[int] t
var v Vector[int]

// 与前面的Vector[int]等价，事实上编译器也会生成类似的类
type VecterInt []int
func (v *VectorInt) Push(x int) { *v = append(*v, x) }

// 定义一个可保存两个任意类型值的Pair
type Pair[T1, T2 any] struct {
	val1  T1
    val2  T2
}

// 定义Pair List
// 注意next字段引用了自身，目前这种相互直接或间接引用，要求参数类型(以及顺序)一致，后面可能会放宽此要求
type List[T1, T2 any] struct {
	next *List[T1, T2] // 如果改成 List[T2, T1] 则不行
	val  Pair[T1, T2] 
}
```

#### 4. 类型集约束

前面提到Go通过interface完成对参数类型的约束，理论上来说已经是完备的了(毕竟interface用作subtype已经证明了这点)，但是还不够方便，比如:

```go
// This function is INVALID.
func Smallest[T any](s []T) T {
	r := s[0] // panic if slice is empty
	for _, v := range s[1:] {
		if v < r { // INVALID
			r = v
		}
	}
	return r
}
```

在`Smallest`函数中，我们希望求出一个切片中的最小元素，但是这个函数声明本身是无效的，因为不是所有的类型都支持`<`运算符，事实上，在Go中，仅有限的内置类型支持`<`，其它自定义类型均不支持通过方法定义自己的`<`运算(此处开始怀念C++的运算符，但是其带来的"一切皆有可能"的代码理解负担也确实头疼...)，诚然这里可以通过定义类似的Comparable interface来进行类型约束和比较，将`v < r`替换为`v.Less(r)`，但你也需要为原生支持比较的类型(int/float/string)定义一个新的类型并实现Comparable接口，反而让Smallest使用起来更复杂。因此，这里Go有必要为基础运算符定义一套泛型类型约束，使得调用方可以直接通过`Smallest[int]([]int{3,1,4})`即可使用。

这里有两种实现方式，一种方案是预定义基础运算的约束，并且让满足条件的基础类型自动适配而无需手动实现，如`<`，`>`，`==`，`<<`，`&&`，`range`，`size`等。另一种方式是基于Go几乎所有的逻辑运算符(唯二的例外在后面会讨论)都仅支持内置基础类型，并且内置基础类型是有限的这两点事实，从另一个角度出发: 让类型约束可以直接指定其需要包含的基础类型。Go优先选择了第二种方案，提供所谓**类型集约束(type sets of contraints)**机制。

##### 类型集

Go新增了类型集(type sets)的概念，每个类型都有自己的类型集，对于非接口类型T而言，其类型集为`{T}`，即为它自身。对于接口类型而言，如下面的接口T:

```go
type T interface {
	io.Reader
	Foo()
	Bar() int
}

// 语义上等价于
type E1 interface { Foo() }
type E2 interface { Bar() int }
type T interface {
	io.Reader
	E1
	E2
}
```

接口本质是若干方法签名 + 内嵌接口的组合，而方法签名很容易转换为对应方法的interface(上例的E1和E2)，而接口T的类型集，本质是`io.Reader`的类型集和E1，E2的类型集的交集，这个定义，既能阐述接口本身概念(满足接口所定义的所有方法)，也能阐述接口作为类型约束的概念(满足T所定义的所有约束)。这个交集的概念是贯穿Go接口和Go泛型约束的。

##### 类型集约束

但是，Go接口只支持方法签名和内嵌接口，对于作为泛型类型约束来说，功能弱了一些(比如不能完成前面提到的类型枚举)，因此Go对interface进行了功能扩展，添加了三个特性，使用了这三个特性的interface，将只能作为类型约束，而不能再作为接口:

1. 类型枚举: 允许类型约束的interface中，直接枚举任意类型，如`type Integer inteface{ int }`
2. 类型近似: 类型枚举不能解决类型重定义的问题，如`type MyInt int`，也应该满足`Integer`约束，因此类型约束interface可以通过`~T`来表达T的近似类型(approximation constraint)，对于约束`type Integer2 interface {~int}`而言，任何底层类型为int的类型，均满足该约束，包括MyInt
3. 类型联合: 可以通过`A|B`来表达"A或B类型"的概念，对于约束`type PredeclaredSignedInteger interface { int | int8 | int16 | int32 | int64 }`而言，任意以上5个整数类型之一，均满足其约束条件

现在再来看前面的Smallest函数，它的完整正确约束应该为:

```go
// Ordered is a type constraint that matches any ordered type.
// An ordered type is one that supports the <, <=, >, and >= operators.
type Ordered interface {
	~int | ~int8 | ~int16 | ~int32 | ~int64 |
		~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 | ~uintptr |
		~float32 | ~float64 |
		~string
}
```

考虑到`Ordered`这类约束可能会在很多地方用到，因此可能需要将其归到官方库中提供，该package为`contraints`，如此`Smallest`即可定义为`func Smallest[T constraints.Ordered](s []T) T`。

这里再提一下Go泛型的显示声明原则，有了类型列表约束之后，函数可以直接使用类型列表中所有类型都支持的运算，但**不能直接使用类型列表都支持的方法，即使这些类型都提供了该方法**:

```go
type MyInt int
func (i MyInt) String() string {
	return strconv.Itoa(int(i))
}

type MyFloat float64
func (f MyFloat) String() string {
	return strconv.FormatFloat(float64(f), 'g', -1, 64)
}

type MyIntOrFloat interface {
	MyInt | MyFloat
}

func ToString[T MyIntOrFloat](v T) string {
    return v.String() // Error: 泛型函数只能使用类型约束显式声明的方法
}
```

这样是为了避免当类型和接口嵌套较深时，调用方很难搞清楚函数到底依赖了约束的哪些方法(因为没了类型约束这层契约)，因此在`MyIntOrFloat`中显式添加`String() string`接口是一个更明智的选择。

综上，Go泛型约束基于接口，但其功能是接口的父集，在扩展了interface功能后，完整的作为类型约束的interface语法如下:

```go
// InterfaceTypeName 即为内嵌接口，MethodSpec 为方法签名，均为Go接口本身的概念
InterfaceType  = "interface" "{" {(MethodSpec | InterfaceTypeName | ConstraintElem) ";" } "}" .
ConstraintElem = ConstraintTerm { "|" ConstraintTerm } .
ConstraintTerm = ["~"] Type .
```

#### 5. 预定义约束

**几乎所有的运算符都仅支持内置类型**，这其中有两个例外的运算符，等于(==)和不等于(!=)，比如我们知道，在Go中，struct，array是可以直接比较的，Go需要特殊处理这两个运算符，因此还是提出了`comparable`这个特殊的预定义类型约束:

```go
func Index[T comparable](s []T, x T) int {
	for i, v := range s {
		if v == x {
			return i
		}
	}
	return -1
}
```

由于Go同时支持了预定义类型约束和类型集约束，因此开发者可能定义出一个永远无法满足的类型约束:

```go
type ImpossibleConstraint interface {
	comparable
	[]int
}
```

由于`[]int`无法被比较，因此没有任何类型能满足`ImpossibleConstraint`约束，定义这个约束本身不会报错，但是在尝试调用使用该约束的任意泛型函数和泛型类时，会得到编译错误。

有了预定义类型约束和类型集约束之后，Go关于运算符的泛型补丁算是打完了，这里再简单梳理下作为interface接口和interface约束的区别:

1. Go预定义了两个类型约束: `any`(等价于interface{}) 和 `comparable`
2. 约束在接口的基础上，扩展了类型集的支持，包括类型枚举(`type T interface {int}`)，或类型(`int8|int16`)，近似类型(`~int`)三种特性
3. 接口的本质是一种类型，可定义值，可为nil(表示没有值，但有类型信息)，类型约束本身描述类型的元信息(类型的类型)，它用来定义值通常没有意义，并且不能为nil
4. 约束本身可以泛型化，这个在之后会提到

#### 6. 复合类型的类型集约束

如果类型集约束中可以存在复合类型，再结合索引`[]`，求大小`len`，遍历`range`，字段访问`.`等针对复合类型的操作符时，有意思的问题就来了。由于不同复合类型的操作符的参数和返回值类型可能是不同的，比如如果类型集约束中包含`[]int`和`[]int64`，它们的索引操作`[]`会分别返回`int`和`int64`，那么此时编译器有两种做法:

1. 支持`[]`操作，但是需要有一个类型联合(`type union`)的新类型，来保存`[]`的返回值。比如在这里，编译器会生成`int`和`int64`的联合来保存`[]`的返回值
2. 仅当`[]`对类型列表中所有的类型的参数和返回值都一致时，才允许使用`[]`，否则不允许使用`[]`并报编译错误

Go目前选择第二种，因为直观上它更容易理解，具体以例子来说:

```go
type structField interface {
		struct { a int; x int } |
		struct { b int; x float64 } |
		struct { c int; x uint64 }
}
func IncrementX[T structField](p *T) {
	v := p.x // Error: 对structField type list来说，操作p.x的返回值类型不一样
	v++
	p.x = v
}

type sliceOrMap interface {
	[]int | map[int]int
}
func Entry[T sliceOrMap](c T, i int) int {
	c[i] // OK. []int和map[int]int的索引操作的参数和返回值均为int
}

type sliceOrFloatMap interface {
	[]int | map[float64]int
}

func FloatEntry[T sliceOrFloatMap](c T) int {
	return c[1.0] // Error: 对[]int和map[float64]int来说，[]操作的参数类型不一致
}
```

目前来说，这应该能够应付绝大部分复合类型type list的应用场景。

#### 7. 类型参数的相互引用

Go支持同一个类型参数列表间的相互引用，如下面的泛型图类型:

```go
package graph

// 创建了一个泛型接口约束来表示图的节点，该约束限制类型必须提供一个返回任意类型切片的Edges()函数
type NodeConstraint[Edge any] interface {
	Edges() []Edge
}

// 创建了一个泛型接口约束来表示图的边，该约束限制类型必须提供一个返回两个相同的任意类型值的Nodes()函数
type EdgeConstraint[Node any] interface {
	Nodes() (from, to Node)
}

// 重点在这里，对泛型图类的类型约束列表中，存在相互引用
// 即限制了NodeConstraint的泛型类型(Edges返回的切片边类型)必须满足另一个EdgeConstraint约束
// EdgeConstraint 的泛型类型(Nodes返回的节点类型)必须满足NodeConstraint
// 即将两个接口约束相互关联了起来
type Graph[Node NodeConstraint[Edge], Edge EdgeConstraint[Node]] struct { ... }

// 创建图，由于约束本身也是泛型，所以看起来复杂一些
func New[Node NodeConstraint[Edge], Edge EdgeConstraint[Node]] (nodes []Node) *Graph[Node, Edge] {
	...
}

// 求图最短路径的方法，由于New的时候，编译器已经检查过了。因此方法中不再需要复填Node/EdgeConstraint，直接使用类型参数即可。
func (g *Graph[Node, Edge]) ShortestPath(from, to Node) []Edge { ... }
```

我们可以用以下Vertex和FromTo类来实例化Graph泛型类:

```go
type Vertex struct { ... }
func (v *Vertex) Edges() []*FromTo { ... }

type FromTo struct { ... }
func (ft *FromTo) Nodes() (*Vertex, *Vertex) { ... }

var g = graph.New[*Vertex, *FromTo]([]*Vertex{ ... })
```

除了相互引用以外，类型约束还可以引用自身，比如定义类型自己的`Equal`函数:

```go
// 查找并返回e的下标，官方给出的写法
func Index[T interface { Equal(T) bool }](s []T, e T) int {
    ...
}

// 以下是等价写法
type Equaler[T any] interface { 
	Equal(T) bool
}

// 查找并返回e的下标
func Index[T Equaler[T]](s []T, e T) int {
    ...
}
```

Go编译器会推导类型参数相互引用的合理性，这进一步提升了泛型的灵活性。

#### 8. 函数参数类型推导

回到前面的Print，该泛型函数的调用方式形如: `Print[int]([]int{3,1,2})`，但前面的类型参数相互引用中提到，编译器需要支持一定的类型推导(type inference)能力，因此实际上大部分时候，我们都不需要显式指定类型参数，直接通过`Print([]int{3,1,2})`调用即可，编译器会通过实参`[]int{3,1,2}`匹配`[]T`，推导出T为int。

这种根据泛型函数调用时传入的实参类型，推敲得到泛型函数类型参数的类型的能力就是函数参数类型推导。

Go类型推导基于底层的类型一致(type unification)机制，本质上来说是一套类型匹配机制，对了类型A和类型B:

1. 如果A，B均不包含类型参数，那么A和B一致当且仅当A和B相同
2. 仅一方包含类型参数: 如A为`[]map[int]bool`，B为`[]T`，那么称A和B是类型一致的，并且此时T为`map[int]bool`
3. 双方都包含类型参数: 如A为`[]map[T1]bool`，B为`[]map[int]T2`，那么A B也是类型一致的，并且T1为`int`，T2为`bool`

Go对泛型函数的类型参数推导是在函数调用而不是实例化的时候发生的，并且函数类型参数推导本身不包含类型约束检查和形实参赋值检查(像普通函数调用的检查一样)，这些是在类型推导完成之后才开始的。类型推导分为两个阶段:

1. 第一阶段，忽略所有的无类型(untype)实参(如字面常量`5`)，先依次推导参数列表中其它的包含类型参数的形参，如果一个类型参数在形参中出现了多次，那么它每次匹配的类型必须是相同的。注: 对于函数的类型参数推导，编译器**只能对出现在函数参数列表中的类型参数进行推导**，而对于那些只用于函数体或函数返回值的类型参数，编译器是无法推导的。
2. 第二阶段，再开始处理无类型实参的匹配，因为其对应形参中的类型参数，可能在第一遍的时候被推敲出来了，如果对应形参还没被推导出来，给无类型实参赋予默认类型(如`5`对应`int`)，再开始推导对应形参。

分为两个阶段是为了延迟无类型实参的类型推导，使泛型对于无类型实参更友好易用。举个例子:

```go
func NewPair[F any](f1, f2 F) *Pair[F] { ... }

// OK, 第一阶段完成后(F类型仍然未知)，开始给无类型实参赋予默认类型int，两次匹配均得到F为int，前后一致，推导完成，F为int
NewPair(1, 2)

// OK, 第一阶段完成后，根据int64(2)推导得到F为int64，第二阶段时，所有无类型实参的类型都已经确定，推导完成，F为int64
// 如果不是两阶段推导，那么这种情况就无法被支持
NewPair(1, int64(2))

// Failed，第一阶段完成后(F未知)，开始分别给无类型参数赋予默认值int和float64，F前后匹配两次的类型不一致，推导失败，编译器报错
NewPair(1, 2.5)
```

#### 9. 约束类型推导

约束类型推导，提供了基于一个类型参数，推导出另一个类型参数的能力，通常应用在多个类型参数之间有关联时。如前面定义Graph泛型类时，用到了泛型接口约束:

```go
type NodeConstraint[Edge any] interface {
	Edges() []Edge
}
```

泛型接口约束允许定义泛型类型参数之间的关系，但是由于约束本身也是泛型的，因此对接口约束中的类型参数也需要推导，这个步骤发生在函数类型参数推导之后，具体的推导规则仍然是根据已知的具象的实参推导未知的类型参数。具体推导规则描述起来比较抽象，仍然以官方例子来说:

```go
// 将数字切片中所有元素翻倍并返回
func Double[E constraints.Number](s []E) []E {
	r := make([]E, len(s))
	for i, v := range s {
		r[i] = v + v
	}
	return r
}

type MySlice []int

// 返回值是[]int，而不是MySlice
var V1 = Double(MySlice{1})
```

为了`Double`函数更易用，我们需要为`Double`的参数即切片本身定义一个类型参数(这样才能定义相同类型的返回值)，但是我们同时需要约束这个切片的元素类型，因此这里需要定义泛型接口约束:

```go
type SC[E any] interface {
	[]E
}

// 定义泛型约束 SC[E]，并且约束E的类型为数字
func DoubleDefined[S SC[E], E constraints.Number](s S) S {
	// Note that here we pass S to make, where above we passed []E.
	r := make(S, len(s))
	for i, v := range s {
		r[i] = v + v
	}
	return r
}

type MySlice []int

// V3的类型是MySlice
var V3 = DoubleDefined(MySlice{1})
```

上例再一次说明了泛型接口约束存在的必要性，按照我的理解，泛型接口约束允许**对一个类型分层次的约束，以及完成约束与约束之间的关联**。回到对约束的类型推导上来，在`DoubleDefined`中，函数的类型参数推导没有办法推导`E`的类型(因为它没有出现在函数参数列表中)，它只能推导得到`S -> MySlice`，这个时候就需要约束类型参数推导来完成剩下的工作了，`MySlice`是已知的具象的类型，从它对应的`SC[E]`约束开始推导，`SC[E]`类型列表中只有一个类型`[]E`，因此`MySlice`只能`[]E`类型一致，推出`E -> int`。

约束的类型推导的时机在函数参数类型推导之后，但是仍然在约束检查之前。


#### 10. 小结

以上主要是简单归纳了Go泛型文档中，偏应用层面的一些特性，简单小结一下:

1. 和其它语言的泛型类似，本质是将类型参数化，支持函数泛型和类型泛型，但目前[暂不支持方法泛型](https://go.googlesource.com/proposal/+/refs/heads/master/design/43651-type-parameters.md#no-parameterized-methods)
2. 通过基于接口的类型约束来描述和限制类型参数(bounded generic types)
3. 类型约束对接口扩展了类型枚举、类型近似、类型联合等元素，用以支持运算符的泛型操作
4. 类型约束对外描述类型参数所需实现的方法或允许的类型集
5. 类型约束对内定义了类型参数所允许调用的方法和支持的操作
6. 类型约束本身也可以泛型化，用以类型参数的相互引用或自引用
7. 类型推导使得大部分时候调用方无需显式指定类型参数
8. 本质上是编译期泛型，泛型类型的反射包括完整的编译时类型信息
9. 不支持元编程、偏特化、变参等高级特性

在大部分的设计取舍上，Go官方会优先考虑构建大型项目所必需的实用性(可读+易用)，类型约束不只是type checker，更是一层设计上不可缺少的契约层，尽可能地将大部分信息都明确地内聚到这层契约上。有时候为了实用性，Go会选择牺牲一定的灵活性，类型集约束就是一个例子。

这里顺便再提下类型集约束，它是把双刃剑，一方面很大程度解决了Go没有运算符重载的问题(这里并不是说有运算符重载就一定香，它带来的代码理解负担也需要慎重考虑)，但另一方面，类型集约束也带来了如下问题:

1. 打破了接口类型约束的封装，甚至允许将泛型约束"降级"为具体类型(只有一个类型的类型列表约束)
2. 接口约束和类型列表约束两者组合可能定义出永远不能被实例化的约束
3. 类型列表约束没有根治没有运算符重载的问题，还加了个预定义约束`comparable`补丁

因此个人觉得，类型列表约束需要慎用，特别是对于自定义类型。

总的来说，这次的Go泛型可以说是众望所归，整体上还是比较实用易用。我已经有点跃跃欲试了，准备在实践中重写部分代码，增强复用性、扩展性以及运行性能。

