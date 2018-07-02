---
title: Erlang 内存问题诊断
layout: post
tags: erlang
categories: erlang
---

通过`erlang:memory()`查看节点内存占用总览，需要通过静态和动态两个维度对内存进行考核：

- 静态: 各类内存占用比例，是否有某种类的内存占用了节点总内存的绝大部分
- 动态: 各类内存增长特性，如增长速度，或是否长期增长而不回收(atom除外)

找出有疑似内存泄露的种类后，再进行下一步分析

### atom

atom不会被GC，这意味着我们应该对atom内存增长更加重视而不是忽略。在编写代码时，尽量避免动态生成atom，因为一旦你的输入源不可靠或受到攻击(特别针对网络消息)，atom内存增长可能导致节点crash。可以考虑将atom生成函数替换为更安全的版本：

<!--more-->

	list_to_atom/1 -> list_to_existing_atom/1
	binary_to_atom/2 -> binary_to_existing_atom/2
	binary_to_term(Bin) -> binary_to_term(Bin,[safe])
	
### ets

ets内存占用通常是由于表过大，通过`ets:i().`查看ets表条目数，大小，占用内存等。

### process

进程内存占用过高可能有两方面原因，进程数量过大和进程占用内存过高。针对于前者，首先找出那些没有被链接或监控的"孤儿进程"：

	[P || P<-processes(),
		[{_,Ls},{_,Ms}] <- [process_info(P,[links,monitors])],
		[]==Ls,[]==Ms].

或通过`supervisor:count_children/1`查看sup下进程数量和状态。

而如果是进程所占内存过高，则可将内存占用最高的几个进程找出来进行检查:

	recon:proc_count(memory, 10). % 打印占用内存最高的10个进程
	recon:proc_count(message_queue_len, 10). % 打印消息队列最长的10个进程
	
### binary

erlang binary大致上分为两种，heap binary(<=64字节)和refc binary(>64字节)，分别位于进程堆和全局堆上，进程通过ProBin持有refc binary的引用，当refc binary引用计数为0时，被GC。关于binary的详细实现，参考[Erlang常用数据结构实现][]。

recon提供的关于binary问题检测的函数有：

	% 打印出引用的refc binary内存最高的N个进程
	recon:proc_count(binary_memory, N)
	% 对所有进程执行GC 打印出GC前后ProcBin个数减少数量最多的N个进程
	recon:bin_leak(N)
	
以上两个函数，通常可以找出有问题的进程，然后针对进程的业务逻辑和上下文进行优化。通常来说，针对于refc binary，有如下思路：

- 每过一段时间手动GC(高效，不优雅)
- 如果只持有大binary中的一小段，用`binary:copy/1-2`(减少refc binary引用)
- 将涉及大binary的工作移到临时一次性进程中，做完工作就死亡(变相的手动GC)
- 对非活动进程使用hibernate调用(该调用将进程挂起，执行GC并清空调用栈，在收到消息时再唤醒)

一种典型地binary泄露情形发生在当一个生命周期很长的中间件当作控制和传递大型refc binary消息的请求控制器或消息路由器时，因为ProcBin仅仅只是个引用，因此它们成本很低而且在中间件进程中需要花很长的时间去触发GC，所以即使除了中间件其他所有进程都已经GC了某个refc binary对应的ProcBin，该refc binary也需要保留在共享堆里。因此中间件进程成为了主要的泄漏源。

针对这种情况，有如下解决方案：

- 避免中间件接触到refc binary，由中间件进程返回目标进程的Pid，由原始调用者来进行binary转发
- 调整中间件进程的GC频率(fullsweep_after)

### driver/nif

另一部分非Erlang虚拟机管制的内存通常来自于第三方Driver或NIF，要确认是否是这部分内存出了问题，可通过`recon_alloc:memory(allocated).`和OS所报告的内存占用进行对比，可以大概得到C Driver或NIF分配的内存，再根据该部分内存的增长情况和占用比例来判断是否出现问题。

如果是纯C，那么内存使用应该是相对稳定并且可预估的，如果还挂接了Lua这类动态语言，调试起来要麻烦一些，在我们的服务器中，Lua部分是无状态的，可以直接重新加载Lua虚拟机。其它的调试手段，则要透过Lua层面的GC机制去解决问题了。

[Erlang常用数据结构实现]: http://wudaijun.com/2015/12/erlang-datastructures/
