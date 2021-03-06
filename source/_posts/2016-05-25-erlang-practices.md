---
title:  Erlang 实践经验
layout: post
tags: erlang
categories: erlang

---

### 使用binary而不是lists

所有能用binary的地方都用binary，配置，协议，DB，网络接口，等等，如果驱动或第三方库不能很好地支持binary，就换一个或者重写接口，如果项目一开始就这么做，会在后期省掉很多麻烦。

### 不要动态生成 atom

atom不被Erlang GC，在代码中要时刻警惕诸如`list(binary)_to_atom/2`和`binary_to_term/1`等动态生成atom的API，特别是这些API的输入源来自于网络或客户端等不可信源，可用`list(binary)_to_existing_atom/2`和`binary_to_term/2`替换之，前者只能转换为已经存在的原子，否则会报错，后者功能类似，确保不会生成新的atom，函数引用，Pid等(这些资源都是不会被GC回收的)。

可通过`erlang:memory/0`来观察atom内存使用状况。

<!--more-->

### 保证OTP进程的init/1是安全稳定的

supervisor的start_link会**同步启动**整个supervisor树，如果某个孩子进程启动失败，supervisor会立即尝试重启，如果重启成功，继续启动下一个孩子进程，否则重试次数到达设定上限后，supervisor启动失败。

在实践中，不要将耗时，依赖外部不稳定服务的操作，放在init/1中，这会导致整个supervisor树启动的不稳定性。特别是对于一些网络连接，数据库读取等操作，应该尽量通过诸如`gen_server:cast(self(), reconnect)`的形式，将实际初始化延后，并维护好状态(是否已经初始化完成)。在`handle_cast(reconnect, State)`中处理具体的细节，不管是初始化，还是运行时的网络异常，都可以通过该函数处理。如果一个错误会经常性地出现在日常的操作中，那么是现在出现，还是以后出现是没有区别的，尽量以同样的方法处理它。

通常情况下，我们需要保证OTP进程的init/1是快速，稳定的，如果连启动过程都不是稳定的，那么supervisor的启动也就没有多大意义了(不能将整个系统恢复到已知稳定状态)，并且可能一个进程本身的非关键初始化错误，导致了整个supervisor启动失败。

> initialization与supervision方法的不同之处：在initialization过程中，client的使用者来决定他们能容忍什么程序的错误，而不是client自己本身决定的。在设计容错系统中，这两者区别尤其重要。   -- [Erlang In Anger](https://zhongwencool.gitbooks.io/erlang_in_anger/chapter_2_building_open_source_erlang_software/side_effects.html)

### 消息队列膨胀

Erlang系统最常见的问题是节点内存耗尽，而内存耗尽的主凶之一就是消息队列过长(Erlang消息队列的大小是无限制的)。要查看消息队列膨胀的进程不难，但是难的是找到消息队列膨胀的原因和解决方案。

常见的消息膨胀原因：

1. 日志进程：特别是错误日志，重试，重启，链接都是产生大量错误日志消息的原因，解决方案：使用lager
2. 锁和阻塞操作：如网络操作或阻塞等待消息等，解决方案：添加更多进程，化阻塞为异步等
3. 非期望的消息：特别针对于非OTP进程，解决方案：非OTP进程定期flush消息队列，当然，尽量使用OTP进程
4. 系统处理能力不足：解决方案：横向扩展，限制输入，丢弃请求等。








