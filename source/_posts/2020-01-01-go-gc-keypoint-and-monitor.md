---
title: Golang GC核心要点和度量方法
layout: post
categories: golang
tags:
- golang
- gc
---

### 一. Go GC 要点

先来回顾一下GC的几个重要的阶段:

#### Mark Prepare - STW

做标记阶段的准备工作，需要停止所有正在运行的goroutine(即STW)，标记根对象，启用内存屏障，内存屏障有点像内存读写钩子，它用于在后续并发标记的过程中，维护三色标记的完备性(三色不变性)，这个过程通常很快，大概在10-30微秒。

#### Marking - Concurrent

标记阶段会将大概25%(gcBackgroundUtilization)的P用于标记对象，逐个扫描所有G的堆栈，执行三色标记，在这个过程中，所有新分配的对象都是黑色，被扫描的G会被暂停，扫描完成后恢复，这部分工作叫后台标记([gcBgMarkWorker](https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mgc.go#L1817))。这会降低系统大概25%的吞吐量，比如`MAXPROCS=6`，那么GC P期望使用率为`6*0.25=1.5`，这150%P会通过专职(Dedicated)/兼职(Fractional)/懒散(Idle)三种工作模式的Worker共同来完成。

<!--more-->

这还没完，为了保证在Marking过程中，其它G分配堆内存太快，导致Mark跟不上Allocate的速度，还需要其它G配合做一部分标记的工作，这部分工作叫辅助标记(mutator assists)。在Marking期间，每次G分配内存都会更新它的"负债指数"(gcAssistBytes)，分配得越快，gcAssistBytes越大，这个指数乘以全局的"负载汇率"(assistWorkPerByte)，就得到这个G需要帮忙Marking的内存大小(这个计算过程叫[revise](https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mgc.go#L484))，也就是它在本次分配的mutator assists工作量([gcAssistAlloc](https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mgcmark.go#L363))。

#### Mark Termination - STW

标记阶段的最后工作是Mark Termination，关闭内存屏障，停止后台标记以及辅助标记，做一些清理工作，整个过程也需要STW，大概需要60-90微秒。在此之后，所有的P都能继续为应用程序G服务了。

#### Sweeping - Concurrent

在标记工作完成之后，剩下的就是清理过程了，清理过程的本质是将没有被使用的内存块整理回收给上一个内存管理层级(mcache -> mcentral -> mheap -> OS)，清理回收的开销被平摊到应用程序的每次内存分配操作中，直到所有内存都Sweeping完成。当然每个层级不会全部将待清理内存都归还给上一级，避免下次分配再申请的开销，比如Go1.12对mheap归还OS内存做了[优化](https://ms2008.github.io/2019/06/30/golang-madvfree/)，使用[NADV_FREE](https://go-review.googlesource.com/c/go/+/135395/)延迟归还内存。

#### STW

在[Go调度模型](https://wudaijun.com/2018/01/go-scheduler/)中我们已经提到，Go没有真正的实时抢占机制，而是一套协作式抢占(cooperative preemption)，即给G(groutine)打个标记，等待G在调用函数时检查这个标记，以此作为一个安全的抢占点(GC safe-point)。但如果其它P上的G都停了，某个G还在执行如下代码:

```go
func add(numbers []int) int {
     var v int
     for _, n := range numbers {
         v += n
     }
     return v
}
```

add函数的运行时间取决于切片的长度，并且在函数内部是没有调用其它函数的，也就是没有抢占点。就会导致整个运行时都在等待这个G调用函数(以实现抢占，开始处理GC)，其它P也被挂起。这就是Go GC最大的诟病: GC STW时间会受到G调用函数的时机的影响并被延长，甚至如果某个G在执行无法抢占的死循环(即循环内部没有发生函数调用的死循环)，那么整个Go的runtime都会挂起，CPU 100%，节点无法响应任何消息，连正常停服都做不到。pprof这类调试工具也用不了，只能通过gdb，delve等外部调试工具来找到死循环的goroutine正在执行的堆栈。如此后果比没有被defer的panic更严重，因为那个时候的节点内部状态是无法预期的。

因此有Gopher开始倡议Go使用非协作式抢占(non-cooperative preemption)，通过堆栈和寄存器来保存抢占上下文，避免对抢占不友好的函数导致GC STW延长(毕竟第三方库代码的质量也是参差不齐的)。相关的Issue在[这里](https://github.com/golang/go/issues/24543)。好消息是，**[Go1.14](https://tip.golang.org/doc/go1.14)(目前还是Beta1版本，还未正式发布)已经支持异步抢占**，也就是说:

```go
// 简单起见，没用channel协同
func main() {
  go func() {
    for {
    }
  }()

  time.Sleep(time.Millisecond)
  runtime.GC()
  println("OK")
}
```

这段代码在Go1.14中终于能输出`OK`了。这个提了近五年的Issue: [runtime: tight loops should be preemptible #10958](https://github.com/golang/go/issues/10958)前几天终于关闭了。不得不说，这是Go Runtime的一大进步，它不止避免了单个goroutine死循环导致整个runtime卡死的问题，更重要的是，它为STW提供了最坏预期，避免了GC STW造成了性能抖动隐患。

### 二. Go GC 度量

#### 1. go tool prof

Go 基础性能分析工具，pprof的用法和启动方式参考[go pprof性能分析](https://wudaijun.com/2018/04/go-pprof/)，其中的heap即为内存分配分析，go tool默认是查看正在使用的内存(`inuse_heap`)，如果要看其它数据，使用`go tool pprof --alloc_space|inuse_objects|alloc_objects`。

需要注意的是，go pprof本质是数据采样分析，其中的值并不是精确值，适用于性能热点优化，而非真实数据统计。

#### 2. go tool trace

go tool trace可以将GC统计信息以可视化的方式展现出来。要使用go tool trace，可以通过以下方式生成采样数据:

1. API: `trace.Start`
2. go test: `go test -trace=trace.out pkg`
3. net/http/pprof: `curl http://127.0.0.1:6060/debug/pprof/trace?seconds=20`

得到采样数据后，之后即可以通过 `go tool trace trace.out` 启动一个HTTP Server，在浏览器中查看可视化trace数据:

![](/assets/image/202001/trace-index.jpg)

里面提供了各种trace和prof的可视化入口，点击第一个View trace可以看到追踪总览:

![](/assets/image/202001/trace-view.jpg)

包含的信息量比较广，横轴为时间线，各行为各种维度的度量，通过A/D左右移动，W/S放大放小。以下是各行的意义:

- Goroutines: 包含GCWaiting，Runnable，Running三种状态的Goroutine数量统计
- Heap: 包含当前堆使用量(Allocated)和下次GC阈值(NextGC)统计
- Threads: 包含正在运行和正在执行系统调用的Threads数量
- GC: 哪个时间段在执行GC
- ProcN: 各个P上面的goroutine调度情况

除了**View trace**之外，trace目录的第二个**Goroutine analysis**也比较有用，它能够直观统计Goroutine的数量和执行状态:

![](/assets/image/202001/trace-goroutines.jpg)

![](/assets/image/202001/trace-goroutines2.jpg)

通过它可以对各个goroutine进行健康诊断，各种network,syscall的采样数据下载下来之后可以直接通过`go tool pprof`分析，因此，实际上pprof和trace两套工具是相辅相成的。

#### 3. GC Trace

GC Trace是Golang提供的非侵入式查看GC信息的方案，用法很简单，设置`GCDEBUG=gctrace=1`环境变量即可:

```
GODEBUG=gctrace=1 bin/game
gc 1 @0.039s 3%: 0.027+4.5+0.015 ms clock, 0.11+2.3/4.0/5.5+0.063 ms cpu, 4->4->2 MB, 5 MB goal, 4 P
gc 2 @0.147s 1%: 0.007+1.2+0.008 ms clock, 0.029+0.15/1.1/2.0+0.035 ms cpu, 5->5->3 MB, 6 MB goal, 4 P
gc 3 @0.295s 0%: 0.010+2.3+0.013 ms clock, 0.040+0.14/2.1/4.3+0.053 ms cpu, 7->7->4 MB, 8 MB goal, 4 P
```

下面是各项指标的解释:

```
gc 1 @0.039s 3%: 0.027+4.5+0.015 ms clock, 0.11+2.3/4.0/5.5+0.063 ms cpu, 4->4->2 MB, 5 MB goal, 4 P

// 通用参数
gc 2: 程序运行后的第2次GC
@0.147s: 到目前为止程序运行的时间
3%: 到目前为止程序花在GC上的CPU%

// Wall-Clock 流逝的系统时钟
0.027ms+4.5ms+0.015 ms   : 分别是 STW Mark Prepare，Concurrent Marking，STW Mark Termination 的时钟时间

// CPU Time 消耗的CPU时间
0.11+2.3/4.0/5.5+0.063 ms : 以+分隔的阶段同上，不过将Concurrent Marking细分为Mutator Assists Time, Background GC Time(包括Dedicated和Fractional Worker), Idle GC Time三种。其中0.11=0.027*4，0.063=0.015*4。

// 内存相关统计
4->4->2 MB: 分别是开始标记时，标记结束后的堆占用大小，以及标记结束后真正存活的(有效的)堆内存大小
5 MB goal: 下次GC Mark Termination后的目标堆占用大小，该值受GC Percentage影响，并且会影响mutator assist工作量(每次堆大小变更时都动态评估，如果快超出goal了，就需要其它goroutine帮忙干活了, https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mgc.go#L484)

// Processors
4 P : P的数量，也就是GOMAXPROCS大小，可通过runtime.GoMaxProcs设置

// 其它
GC forced: 如果两分钟内没有执行GC，则会强制执行一次GC，此时会换行打印 GC forced
```

#### 4. MemStats

[runtime.MemStats](https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mstats.go#L147)记录了内存分配的一些统计信息，通过`runtime.ReadMemStats(&ms)`获取，它是[runtime.mstats](https://github.com/golang/go/blob/dev.boringcrypto.go1.13/src/runtime/mstats.go#L24)的对外版(再次可见Go单一访问控制的弊端)，MemStats字段比较多，其中比较重要的有:

```go
// HeapSys 

// 以下内存大小字段如无特殊说明单位均为bytes
type MemStats struct {
    // 从开始运行到现在累计分配的堆内存数
    TotalAlloc uint64
    
    // 从OS申请的总内存数(包含堆、栈、内部数据结构等)
    Sys uint64
    
    // 累计分配的堆对象数量 (当前存活的堆对象数量=Mallocs-Frees)
    Mallocs uint64
    
    // 累计释放的堆对象数量
    Frees   uint64
    
    // 正在使用的堆内存数，包含可访问对象和暂未被GC回收的不可访问对象
    HeapAlloc uint64
    
    // 虚拟内存空间为堆保留的大小，包含还没被使用的(还没有映射物理内存，但这部分通常很小)
    // 以及已经将物理内存归还给OS的部分(即HeapReleased)
    // HeapSys = HeapInuse + HeapIdle
    HeapSys uint64
    
    // 至少包含一个对象的span字节数
    // Go GC是不会整理内存的
    // HeapInuse - HeapAlloc 是为特殊大小保留的内存，但是它们还没有被使用
    HeapInuse uint64
    
    // 未被使用的span中的字节数
    // 未被使用的span指没有包含任何对象的span，它们可以归还OS，也可以被重用，或者被用于栈内存
    // HeapIdle - HeadReleased 即为可以归还OS但还被保留的内存，这主要用于避免频繁向OS申请内存
    HeapIdle uint64
    
    // HeapIdle中已经归还给OS的内存量
    HeapReleased uint64
 
    // ....
}
```

程序可以通过定期调用`runtime.ReadMemStats`API来获取内存分配信息发往时序数据库进行监控。另外，该API是会STW的，但是很短，Google内部也在用，用他们的话说:"STW不可怕，长时间STW才可怕"，该API通常一分钟调用一次即可。

#### 5. ReadGCStats

`debug.ReadGCStats`用于获取最近的GC统计信息，主要是GC造成的延迟信息:

```go
// GCStats collect information about recent garbage collections.
type GCStats struct {
	LastGC         time.Time       // 最近一次GC耗费时间
	NumGC          int64           // 执行GC的次数
	PauseTotal     time.Duration   // 所有GC暂停时间总和
	Pause          []time.Duration // 每次GC的暂停时间，最近的排在前面
	...
}
```

和ReadMemStats一样，ReadGCStats也可以定时收集，发送给时序数据库做监控统计。

### 三. Go GC 调优

Go GC相关的参数少得可怜，一如既往地精简:

#### 1. debug.SetGCPercent

一个百分比数值，决定即本次GC后，下次触发GC的阈值，比如本次GC Sweeping完成后的内存占用为200M，GC Percentage为100(默认值)，那么下次触发GC的内存阈值就是400M。这个值通常不建议修改，因为优化GC开销的方法通常是避免不必要的分配或者内存复用，而非通过调整GC Percent延迟GC触发时机(Go GC本身也会根据当前分配速率来决定是否需要提前开启新一轮GC)。另外，debug.SetGCPercent传入<0的值将关闭GC。

#### 2. runtime.GC

强制执行一次GC，如果当前正在执行GC，则帮助当前GC执行完成后，再执行一轮完整的GC。该函数阻塞直到GC完成。

#### 3. debug.FreeOSMemory

强制执行一次GC，并且尽可能多地将不再使用的内存归还给OS。

严格意义上说，以上几个API预期说调优，不如说是补救，它们都只是把Go GC本身就会做的事情提前或者延后了，通常是治标不治本的方法。真正的GC调优主要还是在应用层面。我在[这篇文章](https://wudaijun.com/2019/09/go-performance-optimization/)聊了一些Go应用层面的内存优化。

以上主要从偏应用的角度介绍了Golang GC的几个重要阶段，STW，GC度量/调试，以及相关API等。这些理论和方法能在在必要的时候派上用场，帮助更深入地了解应用程序并定位问题。

推荐文献:

1. [Garbage Collection In Go](https://www.ardanlabs.com/blog/2018/12/garbage-collection-in-go-part1-semantics.html)
2. [GC 20 问](https://github.com/qcrao/Go-Questions/blob/master/GC/GC.md)
3. [A visual guide to Go Memory Allocator from scratch](https://blog.learngoprogramming.com/a-visual-guide-to-golang-memory-allocator-from-ground-up-e132258453ed)