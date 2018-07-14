---
title: Go package和goroutine的一些理解和实践
layout: post
categories: go
tags: go
---

Go的package和goroutine，前者组织Go程序的静态结构，后者形成Go程序的动态结构，这里谈谈对这两者的一些理解和实践。

### 一. package 管理

#### 1. package 布局

分包的目的是划分系统，将系统划分为一个个更小的模块，更易于理解，测试和维护。如何组织Go项目的包结构，是大多数Go程序员都遇到过的问题，各个开源项目的实践可能也并不相同。以下是几种常见分包方案。

##### 单一Package

适用于小型应用程序，无需考虑循环依赖等问题。但在Go中，同一个Package下的类和变量是没有隐私可言的，C++/Java可以在同一个文件中通过Class实现访问控制，但是Go不可以。因此随着项目代码规模增长(超过10K [SLOC](https://en.wikipedia.org/wiki/Source_lines_of_code)，代码维护和隔离将变得非常困难。

<!--more-->

##### 按功能模块纵向划分

按照功能模块纵向划分可能是最容易想到的一种方案，比如玩家/地图/公会，这种划分方案主要的问题之一在于循环依赖，比如玩家包和公会包之间可能相互引用，这个时候通常的做法要么是通过控制反转(依赖注入/查找)，或者观察者模式等设计模式解耦，要么就为其中一个包抽出一个接口包，将A->B->A的关系变为IA->B->A。随着包增多，交互的复杂，包依赖关系的维护也会变成负担。


##### MVC横向划分

Rails风格布局，至今仍然在很多HTTP框架中流行，它之所以适用于HTTP，是因为HTTP框架交互流程相对单一且明确(Request-Response)，而对于GS来说，交互流程则要复杂得多，客户端，Timer，RPC调用等等。因此最终往往做成了Fat Controller/Thin Model，导致绝大部分逻辑都堆在Controller层。循环引用的问题仍然可能存在。

##### 按照依赖划分

这是Go标准库最常用的方案，比如`io.Reader/Writer/Closer`接口，字符串读取(bytes.Reader/strings.Reader)，文件读取(os.File)，网络读取(net.Conn)等都实现了io.Reader接口，我们在使用读取相关功能的时候，只需要导入io接口包和对应的Reader实现包(如os.File)即可。这种模型的主要思维按照依赖进行划分:

- root包: 声明原型和接口，不包含实现。root包本身不依赖任何包。比如这里的io包。
- implement包: 对root包中的接口使用和实现。比如这里的os，net，strings等。
- main包: 导入root包和implement包，以root包接口为原型，实现对implement的桥接和依赖注入。

这种布局有几个好处:

1. 按照依赖划分，更容易适应重构和需求变更
2. 将依赖独立出去，代码变得很容易测试，比如很容易实现一个模拟DB操作的dep包，而业务逻辑无需任何变更
3. 以接口为契约的包划分，要比直接包划分有更清晰的交互边界，前面提到的两种包划分，做得不好很容易最终只是将代码分了几个目录存放，实际交互仍然混乱(比如直接修改其它包数据)

这种布局其实有点像前面提到的以接口包的形式将A->B->A的关系变为IA->B->A，后者针对局部关系，而依赖划分强调从整体上思考这个功能模块的原型，然后围绕这些原型(接口)去扩展实现，最后在main包中将这些实现组装起来。关于这种包布局在[这篇文章](https://medium.com/@benbjohnson/standard-package-layout-7cdbc8391fc1)有很好的阐述。

以上几种分包的方式都有其适用情形，就我们项目而言，目前这几种布局方案都在用，按依赖划分相比其它方案而言，对开发人员的业务理解能力更高，我们将其应用到战斗，DB，网络等通用模块，而对于普通业务逻辑，按照功能划分即可，毕竟业务逻辑的抽象是变化很快并且极不稳定的。另外，分包最好主要从模块关系出发，不要以代码量为主要考量，否则包关系只会剪不断，理还乱。

#### 2. 不要用package init()

init函数依赖于包的导入顺序，并且一个包还可能有多个init函数，通过它来做一些初始化会让整个调用流程不可控，并且让包的导入具有副作用(比如[net/http/pprof](https://golang.org/pkg/net/http/pprof/)的[init()](https://github.com/golang/go/blob/dev.boringcrypto.go1.9/src/net/http/pprof/pprof.go#L71)便会影响http.DefaultClient的Handler，个人并不认同这种做法)。所有包的初始化应该显式指定，包的导入应该没有副作用。

#### 3. 适当应用internal包

对于一些比较复杂的包，将那些外部不可见的逻辑，变量声明等放到[internal包](https://golang.org/doc/go1.4#internalpackages)中，这样internal包下的导出内容和子包只能被其父目录引用，起到一定程度的访问控制，包的使用者也更容易理解，这可能也是Go觉得包的访问控制实在是太弱了才加上的，但目前好像很少有项目用这个特性，即使它看起来是无害的。关于包的访问限制，这里有篇[如何访问package私有函数](http://colobu.com/2017/05/12/call-private-functions-in-other-packages/)比较有意思，可以了解一下。

### 二. 再谈 goroutine

我在[谈谈架构灵活性和可靠性](http://wudaijun.com/2018/07/gs-flexiblity-reliability/)里已经提到过goroutine的一些实践，这里再啰嗦几句，为什么我对goroutine的规范使用如此重视。

goroutine本身只是执行体，并不包含其消息上下文，错误处理以及生命周期管理，Go语言给了开发者最大的灵活度去实现自己的并发模型和流控，这也是CSP模型的长处(参考[CSP vs Actor](http://wudaijun.com/2017/05/go-vs-erlang/))，但对开发者而言，日常会用到的并发模型其实就那么几种: Actor，生产者-消费者，线程池，扇入-扇出等，比如逻辑开发大多数时候需求可能都只是并发执行一个Task，Task完成后在调用方的上下文中执行回调函数: `go(task func(), cb func())`，而具体这个Task goroutine它的错误处理和生命周期开发者并不关心，交给开发者自己去实现也很容易出错，比如创建出一个没有错误处理和终止条件的goroutine，最终导致轻则导致goroutine泄露，重则因为不知道那个小功能上创建出的goroutine panic没有被defer，然后整个节点就挂了。

Go反复给开发者强调"goroutine is cheap"，让开发者觉得使用goroutine非常简单，无非就是普通函数前面加个`go`，而实际上goroutine创建是很便宜，但是没有管理好goroutine的代价可不一定便宜。这也是为什么现在的高级语言都有自己的轻量级线程和协程，而不直接使用OS线程的原因，因为原生的OS线程做错误处理和生命周期管理比较困难。而Go的`go`原语，还是一个非常底层的并发原语，它加上channel能够实现任何并发模型，这就像是指针，goto和手动GC一样，足够强大，但也太锋利，用不好会割手。在Erlang OTP里面，Process包含了消息上下文(mailbox)，错误处理，它在灵活性上可能不如CSP，但大部分用起来却更省心。

谈到`go`并发原语，前几天读到[一篇文章](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)，非常有意思，作者将现代并发原语(如`go`, `CreateThread`等)比作当今时代的goto，核心依据如下:

1. go和goto一样，容易破坏函数的黑盒封装
2. 没了黑盒，也就没有了易读性，可维护性
3. 没了黑盒，也就丢失了很多语言级高级特性(比如`RAII`，python的`with...as`)
4. 没了黑盒，也做不好错误处理和错误传递

作者认为`goto`是从汇编到高级语言的过渡产物，而`go`则是如今并发编程时代的过渡产物，参考`goto`的解决方案，作者认为应该提供一些更高级的并发原语替换`go`，亦如当初用if,for等控制语句替换`goto`，最后作者安利了一下自己的并发库[Trio](https://trio.readthedocs.io/en/latest/)，大概应该是将线程的生命周期管理做到了框架中，以尽可能地保留函数的黑盒理念及其带来的好处。原文比较冗长，作者的眼界确实很广，且不论Trio这个东东到底怎么样，文中的大部分观点我都比较认同，并且得到了很多启发，技术发展的趋势是越来越易于使用，越来越按照人而不是计算机的方式来思考和解决问题。

收回对未来的展望，回到我们的goroutine，在使用过程中，框架应该尽可能对goroutine封装，比如Actor，异步任务，让外部逻辑易于使用，在手动创建goroutine时，将消息上下文，错误处理，生命周期等一并考虑进来，作为一个整体来设计和考量。
