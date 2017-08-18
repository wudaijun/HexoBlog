---
title: 用context库规范化Go的异步调用
layout: post
categories: go
tags: go
---

### 常见并发模型

之前对比过[Go和Erlang的并发模型](http://wudaijun.com/2017/05/go-vs-erlang/)，提到了Go的优势在于流控，下面列举几种常见的流控:

#### Ping-Pong

这通常针对于两个goroutine之间进行简单的数据交互和协作，我们常用的RPC也属于此类，通过channel的类型可以灵活实现交互方式:

- 同步单工: 单个双向非缓冲channel
- 同步双工: 多个单向非缓冲channel
- 异步双工: 多个单向缓冲channel

#### 流水线

流水线如其词语，goroutine是"流水线工人"，channel则为"流水线"，衔接不同的goroutine的输入输出，每个goroutine有一个输入(inbound)channel和输出(outbound)channel:

	// 以下定义一个流水线工人 用于将inbound channel中数字求平方并放入outbound channel
	func sq(in <-chan int) <-chan int {
	    out := make(chan int)
	    go func() {
	        for n := range in {
	            out <- n * n
	        }
	        close(out)
	    }()
	    return out
	}

流水线goroutine有一些特质：它负责创建并关闭channel(在完成自己的工作后)，这样外部调用无需关心channel的创建和关闭，当channel被关闭，它的下游goroutine会读出零值的数据。我们还可以用链式调用来组装流水线：
	
	sq(sq(sq(ch)))
	
在实际应用中，如DB读写，网络读写等外部阻塞操作通常都放到单独的流水线去做，下游主goroutine可以灵活处理IO结果(如通过select完成IO复用)。

#### 扇入扇出

流水线工作通常是一对一的"工作对接"，通过select可以达成IO复用，比如GS同时处理网络消息，RPC调用，Timer消息等，这其实就是简单的扇入模型，扇出模型也比较常见，比如在对一些无状态的任务做分发时，可以让多个goroutine处理一个channel任务队列上的数据，最大程度地提升处理效率。
	
	
上面三个模式是应用最常用到的，因此不再举例具体说明，[Go并发可视化](http://strucoder.com/2016/03/15/gozhong-de-bing-fa-ke-shi-hua/)这篇文章很好地归纳和总结了这些模型，推荐一读。

### 交互规范

上面只所以提出这三种模型主要是为了导出接下来的问题，当用到多个goroutine时，如何协调它们的工作：

#### 如何正确关闭其它goroutine

这类问题的通常情形是：当某个goroutine遇到异常或错误，需要退出时，如何通知其它goroutine，或者当服务器需要停止时，如何正常终止整个并发结构，为了简化处理问题模型，以流水线模型为例，在正常情况下，它们会按照正常的流程结束并关闭channel(上游关闭channel，下游range停止迭代，如此反复)，但当某个下游的goroutine遇到错误需要退出，上游是不知道的，它会将channel写满阻塞，channel内存和函数栈内存将导致内存泄露，在常规处理方案中，我们会使用一个done channel来灵活地通知和协调其它goroutine，通过向done channel写入数据(需要知道要关闭多少个goroutine)或关闭channel(所有的读取者都会收到零值，range会停止迭代)。

#### 如何处理请求超时

至于超时和请求放弃，通常我们可以通过select来实现单次请求的超时，比如 A -> B -> C 的Ping-Pong异步调用链，我们可以在A中select设置超时，然后在B调用C时也设置超时，这种机制存在如下问题:

1. 每次请求链中的单次调用都要启一个timer goroutine
2. 调用链中的某个环节，并不知道上层设置的超时还有多少，比如B调用C时，如果发现A设置的超时剩余时间不足1ms，可以放弃调用C，直接返回
3. A->B的超时可能先于B->C的超时发生，从而导致其它问题

#### 如何安全放弃异步请求

这个问题可以理解为如何提前结束某次异步调用，接上面提到的A->B->C调用链，如果A此时遇到了其它问题，需要提前结束整个调用链(如)，B是不知道的，A和B之间数据交互channel和done channel，没有针对某个请求的取消channel，尽管大部分时候不会遇到这种需求，但针对某个请求的协同机制是缺失的，还需要另行设计。

#### 如何保存异步调用上下文

异步调用通常会有上下文，这个上下文不只指调用参数，还包括回调处理参数(非处理结果)，请求相关上下文(如当前时间)等，这类数据从设计上可以通过包含在请求中，或者extern local value，或者每次请求的session mgr来解决，但并不通用，需要开发者自行维护。


### 使用context

以上几个问题并不限于Go，而是异步交互会遇到的普遍问题，只是在Go应用和各类库会大量用到goroutine，所以这类问题比较突出。针对这些问题，Go的内部库(尤其是net,grpc等内部有流水线操作的库)作者开发了context(golang.org/x/net/context)包，用于简化单个请求在多个goroutie的请求域(request-scoped)数据，它提供了:

1. 请求的超时机制
2. 请求的取消机制
3. 请求的上下文存取接口
4. goroutine并发访问安全性

context以组件的方式提供超时(WithTimeout/WithDeadline)，取消(WithCancel)和K-V(WithValue)存取功能，每次调用WithXXX都将基于当前的context(Background为根Context)继承一个Context,一旦父Context被取消，其子Context都会被取消，应用可通过<-context.Done()和
context.Err()来判断当前context是否结束和结束的原因(超时/取消)。

比如针对我们前面的"sq流水线工人"，我们可以通过context让它知道当前流水线的状态，并及时终止:

```go
func sq(ctx context.Context, in <-chan int) out <-chan int{
	out := make(chan int)
	go func() {
	    for n := range in {
	        select{
	        case <-ctx.Done():	// 当前流水线被终止
	        		close(out)
	        		return ctx.Err() // 终止原因: DeadlineExceeded or Canceled
	        case out <- n * n:
	    }
	    close(out)
	}()
	return out
}
```

我们可以将context在goroutine之间传递，并且针对当前调用通过WithXXX创建子context，设置新的超时，请求上下文等，一旦请求链被取消或超时，context的done channel会被关闭，当前context的所有`<-ctx.Done()`操作都会返回，并且所有当前context的子context会以相同原因终止。

比如在A->B->C中，B基于A的context通过WithTimeout或WithValue创建子context，子Context的超时和上下文都可以独立于父context(但如果子context设置超时大于父context剩余时间，将不会创建timer)，通过context库内部的继承体系来完成对应用层调用链的记录，并执行链式的超时和取消。

关于context的进一步了解可参考[Go语言并发模型：使用 context](https://segmentfault.com/a/1190000006744213)，也可直接阅读源码，实现也比较简单，单文件不到300行代码，但本身的意义却是重大的，go的很多异步库(如net,grpc,etcd等)都用到了这个模块，context正在逐渐成为异步库的API规范，我们也可以从context这个库中得到一些启发，适当地用在自己的项目中。