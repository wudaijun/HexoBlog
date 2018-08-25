---
title: Go 的一些"坑"
layout: post
categories: go
tags: go
---

#### 访问控制

1. package 内没有任何访问控制
2. package 间的访问控制只由大小写区分

问题1我们可以通过合理拆分 package，来避免代码维护变得越来越困难，为了避免循环依赖，这里有[一些实践](http://wudaijun.com/2018/07/go-package-goroutine-practice/)。

问题2则更难处理一些，因此 Go语言的reflect这类基础设施也受此影响，有时候你为了对象能够序列化或者 DeepCopy，就必须将其字段大写，也就对所有的package都暴露了实现。也就是说，Go 语言的基础设施(如reflect)也受此访问控制的限制(reflect本质上也是个package)。

<!--more-->

比如游戏服务器中 Model，为了序列化，没有办法将其结构实现对外隐藏起来，只暴露API，这也就导致没有一种安全的方法来做脏标记这种状态封装(Go也没有类似Lua metatable这种Hook机制)。

#### 可变语义

Go语言鼓励你用指针，还帮你做了指针的自动解引用，但是 Go 的大部分数据结构都是引用语义并且goroutine不安全的，如 slice，map等，Go不提供任何不可变语义，比如 const，copy-on-write等，这很符合 Go 的哲学: 简单(实现起来简单)。要想共享数据，要么通过 channel 或 mutex 来实现串行访问，要么就拷贝一份(深拷贝,DeepCopy)。初学者要没搞明白Go的数据结构实现之前，很容易写出并发不安全的代码。

#### 没有泛型

泛型本质上就是基于现有类型创造新的类型，达成代码复用。比如`map[KeyType]ValueType`，Go的reflect可以完成这个任务，你可以反射得到对象的type和value，然后可以通过这个type来创建新的对象或者构建更复杂的类型，比如`[]type`，`chan type`，`map[int]type`，甚至 struct，但是这一切都是运行时的，没有类型安全保证。是的，一门静态语言提供给开发者的泛型机制(reflect)并不提供类型安全保证。开发者只能通过interface来做一些丑陋的代码复用，典型的如sync.Map。

#### deepcopy

前面说了，go不支持不可变语义，如果你要共享，要么加锁，要么拷贝。是的，Go 当然有 deepcopy 函数，但不是 Go 本身提供的，而是[第三方基于reflect的](https://github.com/mohae/deepcopy/blob/master/deepcopy.go)。首先，基于 reflect 的 deepcopy 比自己写一个 deepcopy 要慢一个数量级，和直接序列化为 bson/json差不多。其次，前面也提到了，reflect 不能访问小写开头字段，因此基于reflect的deepcopy是不完整的，这可能导致一些问题，比如该对象的某个API访问了小写字段，或者大写字段和小写字段有相互关联。

解决DeepCopy的方案有两个，一是自己实现一个基于代码生成([text/template](https://golang.org/pkg/text/template/))的deepcopy，这也是我们最近在尝试的。而是等着哪一天Go 想通了，做了个语言层面的deepcopy :)

#### 构造函数

Go没有构造函数，Go"尽量"让零值(var t T)易于使用，比如int默认为0，string默认为""，sync 包的大部分数据结构都可以拿来即用(`sync.Mutex`,`sync.WaitGroup`等)。但也有例外，比如map:

```go
var m1 = map[string]string{} // empty map
var m0 map[string]string     // zero map (nil)

println(len(m1))   // outputs '0'
println(len(m0))   // outputs '0'
println(m1["foo"]) // outputs ''
println(m0["foo"]) // outputs ''
m1["foo"] = "bar"  // ok
m0["foo"] = "bar"  // panics!
```

对零值map的读取是ok的，但写入会panic!，我想大家都经历过`panic: assignment to entry in nil map`这类错误。特别在使用别人的结构体时，如果其内包含指针或map，而你没有显示调用其初始化函数(通常是NewXXX, OpenXXX, InitXXX)，后果通常是panic，毕竟库作者不一定会在每个 API上都检查初始状态，这通常需要使用者去谨慎检查并承担责任。

#### 切片和动态数组

Go 的切片用于引用数组的一部分，如`s := a[1:3]`，切换本身可以访问或修改数组的部分元素，但不会拷贝数组或者对数组大小造成影响。动态数组则是可以不断追加(append)元素的数组，这两个东西本来是两个概念，但是不巧的是，在 Go 中，它们都叫 slice，在一个切片语义的 slice上执行append一个元素将可能导致:

1. len<cap时，切片修改了原本不属其引用范围的数组元素
2. len==cap 时，切片重新分配，并拷贝原本所指向数组元素，从而丢失切片的引用语义

因此我们在使用 slice 的一个实践就是一个slice只表达一种语义(要么切片，要么动态数组)，不要混用，关于slice 的更多细节参考[这里](http://wudaijun.com/2016/09/go-notes-1-datastructures/)。

#### nil interface

我在[这篇博客](http://wudaijun.com/2018/01/go-interface-implement/)里谈了下interface的实现，简单来说，interface{}本身就是一个结构体，包含 type/itab, data 两个字段，现在我们来看个有趣的示例:

```go
type ITester interface {
	A()
	B()
}

type Test struct {}
func (*Test) A() {}
func (Test) B() {}

func main() {
	var t *Test = nil
	var it ITester = t
	println(t, it) // '0x0 (0x1071e60,0x0)'
	if it != nil {
		println("Not nil!") // 程序会走到这里
		it.A()     // ok
		it.B()     // panic: value method main.Test.B called using nil *Test pointer
	} else {
		println("nil!")     // 对interface{}不了解的同学可能会认为应该走到这里
	}
}
```

现在我们来大概看看发生了什么，it本身是个itab+data的结构体，其中itab包含了t的类型以及ITester方法定义等，data则指向t，因此it打印出来第二个字段为0x0，但指向nil值的it本身并不为nil，也就是说`var it1 ITester = nil`和`var it2 Itester = (*Test)(nil)`，两条语句的性质是完全不一样的。it可以正常调用A()，因为A()的receiver是指针，而调用B()则会panic，因为需要解nil指针。这个示例能够说明interface{}实现的一些非直观性，以及自动解引用和nil receiver结合时引发的一些问题。另外，如果你真的需要判断一个interface{}指向的值是否为nil，还得用到"万能的"反射: `if it != nil && !reflect.ValueOf(it).IsNil() `。


#### And More...

前面只是列举了部分我在使用中对Go语言设计的反思，还有一些被广为诟病的如GOPATH，依赖管理等，它们有些可能是 Feature(嗯，万能的词汇)，有些则可能有设计上的考量(你我皆凡人)，Go语言目前给我的整体感觉就是"差那么一步"，比如map没有clear接口，没有提供deepcopy函数，没有构造函数等，这一步或难(比如添加 const语义)或不难(比如map clear)，但设计者终究没有为开发者提供这样的选项，这种差一步的好处便是简单(这里当然说的是语言实现简单)，这可能是Go语言最重要的设计哲学之一，也是对"互联网C语言"Slogan的践行。另一个角度来说，开发者对语言的期望是很高的，灵活性/安全性，开发效率/运行效率，命令式/面向对象/函数式/泛型等统统都要。:) 有意思的是，网上有人将对 Go 语言的吐槽收集起来，做成了[go is not good](https://github.com/ksimka/go-is-not-good)系列，然后赚了3000多个Star。。。真的是Go社区火了，带动了一堆"副产业"。。。








