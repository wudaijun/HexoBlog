---
title: Go vs Erlang
layout: post
tags: [go,erlang]
categories:
- go
---

源于从Erlang到Go的一些思维碰撞，就像当初从C++到Erlang一样，整理下来记于此。

### Actor

Actor模型，又叫参与者模型，其"一切皆参与者(actor)"的理念与面向对象编程的“一切皆是对象”类似，但是面向对象编程中对象的交互通常是顺序执行的(占用的是调用方的时间片，是否并发由调用方决定)，而Actor模型中actor的交互是并行执行的(不占用调用方的时间片，是否并发由自己决定)。

在Actor模型中，actor执行体是第一类对象，每个actor都有自己的ID(类比人的身份证)，可以被传递。actor的交互通过发送消息来完成，每个actor都有一个通信信箱(mailbox，本质上是FIFO消息队列)，用于保存已经收到但尚未被处理的消息。actorA要向actorB发消息，只需持有actorB ID，发送的消息将被立即Push到actorB的消息信箱尾部，然后返回。因此Actor的通信原语是异步的。

从actor自身来说，它的行为模式可简化为:

- 发送消息给其它的actor
- 接收并处理消息，更新自己的状态
- 创建其它的actor

一个好的Actor模型实现的设计目标:

- 调度器: 实现actor的公平调度
- 容错性: 具备良好的容错性和完善错误处理机制
- 扩展性: 屏蔽actor通信细节，统一本地actor和远程actor的通信方式，进而提供分布式支持
- 热更新? (还没弄清楚热更新和Actor模型，函数式范式的关联性)

在Actor模型上，Erlang已经耕耘三十余载，以上提到的各个方面都有非常出色的表现，其OTP整合了在Actor模型上的最佳实践，是Actor模型的标杆。

### CSP

顺序通信进程(Communicating sequential processes，CSP)和Actor模型一样，都由独立的，并发的执行实体(process)构成，执行实体间通过消息进行通信。但CSP模型并不关注实体本身，而关注发送消息使用的通道(channel)，在CSP中，channel是第一类对象，process只管向channel写入或读取消息，并不知道也不关心channel的另一端是谁在处理。channel和process是解耦的，可以单独创建和读写，一个process可以读写(订阅)个channel，同样一个channel也可被多个process读写(订阅)。

对每个process来说：

- 从命名channel取出并处理消息
- 向命名channel写入消息
- 创建新的process

Go语言并没有完全实现CSP理论(参见[知乎讨论](https://www.zhihu.com/question/26192499))，只提取了CSP的process和channel的概念为并发提供理论支持。目前Go已经是CSP的代表性语言。

### CSP vs Actor

- 相同的宗旨："不要通过共享内存来通信，而应该通过通信来共享内存"
- 两者都有独立的，并发执行的通信实体
- Actor第一类对象为执行实体(actor)，CSP第一类对象为通信介质(channel)
- Actor中实体和通信介质是紧耦合的，一个Actor持有一个Mailbox，而CSP中process和channel是解耦的，没有从属关系。从这一层来说，CSP更加灵活
- Actor模型中actor是主体，mailbox是匿名的，CSP模型中channel是主体，process是匿名的。从这一层来说，由于Actor不关心通信介质，底层通信对应用层是透明的。因此在分布式和容错方面更有优势

### Go vs Erlang

- 以上 CSP vs Actor
- 均实现了语言级的coroutine，在阻塞时能自动让出调度资源，在可执行时重新接受调度
- go的channel是有容量限制的，因此只能一定程度地异步(本质上仍然是同步的)，erlang的mailbox是无限制的(也带来了消息队列膨胀的风险)，并且erlang并不保证消息是否能到达和被正确处理(但保证消息顺序)，是纯粹的异步语义，actor之间做到完全解耦，奠定其在分布式和容错方面的基础
- erlang/otp在actor上扩展了分布式(支持异质节点)，热更和高容错，go在这些方面还有一段路要走(受限于channel，想要在语言级别支持分布式是比较困难的)
- go在消息流控上要做得更好，因为channel的两个特性: 有容量限制并独立于goroutine存在。前者可以控制消息流量并反馈消息处理进度，后者让goroutine本身有更高的处理灵活性。典型的应用场景是扇入扇出，Boss-Worker等。相比go，erlang进程总是被动低处理消息，如果要做流控，需要自己做消息进度反馈和队列控制，灵活性要差很多。另外一个例子就是erlang的receive操作需要遍历消息队列([参考](http://www.jianshu.com/p/41f2e943c795))，而如果用go做同步调用，通过单独的channel来做则更优雅高效

### Actor in Go 

在用Go写GS框架时，不自觉地会将goroutine封装为actor来使用:

- GS的执行实体(如玩家，公会)的逻辑具备强状态和功能聚合性，不易拆分，因此通常是一个实体一个goroutine
- 实体接收的逻辑消息具备弱优先级，高顺序性的特点，因此通常实体只会暴露一个Channel与其它实体交互(结合go的interface{}很容易统一channel类型)，这个channel称为RPC channel，它就像这个goroutine的ID，几乎所有逻辑goroutine之间通过它进行交互
- 除此之外，实体还有一些特殊的channel，如定时器，外部命令等。实体goroutine对这些channel执行select操作，读出消息进行处理
- 加上goroutine的状态数据之后，此时的goroutine的行为与actor相似：接收消息(多个消息源)，处理消息，更新状态数据，向其它goroutine发送消息(通过RPC channel)

到目前为止，goroutine和channel解耦的优势并未体现出来，我认为主要的原因仍然是GS执行实体的强状态性和对异步交互流程的顺序性导致的。

在研究这个问题的过程中，发现已经有人已经用go实现了Actor模型: https://github.com/AsynkronIT/protoactor-go。 支持分布式，甚至supervisor，整体思想和用法和erlang非常像，真是有种他山逢知音的感觉。:)

参考：

1. http://jolestar.com/parallel-programming-model-thread-goroutine-actor/
2. https://www.zhihu.com/question/26192499

