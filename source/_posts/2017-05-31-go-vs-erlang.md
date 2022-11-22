---
title: Go vs Erlang
layout: post
tags:
- golang
- actor
- csp
- erlang
categories:
- golang
---

源于从Erlang转到Go的一些思维碰撞，整理下来记于此。

### Erlang Actor

Actor模型，又叫参与者模型，其"一切皆参与者(Actor)"的理念与面向对象编程的“一切皆是对象”类似，但是面向对象编程中对象的交互通常是顺序执行的(占用调用方的时间片)，而Actor模型中Actor的交互是并行执行的(不占用调用方的时间片)。

在Actor模型中，Actor的交互通过向对方Actor发送消息来完成。即Actor只关注要和谁通信，并不关注对方在哪里、如何和对方通信。模型只提供**异步消息交互**一种通信原语，甚至不保证对端一定能正确收到消息。

从Actor自身来说，它的行为模式很简单:

- 发送消息给其它的Actor
- 接收并处理消息，更新自己的数据状态
- 创建其它的Actor

每个Actor都有一个通信信箱(mailbox，FIFO消息队列)，用于保存已经收到但尚未被处理的消息。actorA要向actorB发消息，只需持有actorB ID(mailbox邮箱地址)，发送的消息将被Push到actorB的消息信箱尾部，然后返回。因此Actor的通信原语是异步的。消息QoS和请求-响应机制完全交给应用层去实现。这是Actor分布式友好的基础。

由于Actor这种"最坏预期"的设计理念，Actor模型天然有如下好处:

- 由于Actor只通过消息交互，因此避免了锁的问题
- 由于Actor并不关心对方具体位置以及通信介质，这种位置透明的特性使得它在分布式下具备很好的扩展性
- 由于Actor只提供异步消息交互，因此整个系统的下限更高(锁和同步调用是高可用系统深深的痛)

Erlang作为最早的Actor模型实践者，同时也是Actor模型的推广者和标杆。Erlang实现了完整的轻量级Actor(Erlang Process)，包括位置透明性、异步交互、基于规约的公平调度器等。使得它在并发和分布式方面有得天独厚的优势。

除此之外，Erlang OTP还在Actor模型的基础上，扩展了容错和热更两大杀手级工业特性: 容错和热更。

Erlang 热更我在[这里](https://wudaijun.com/2015/04/erlang-hotcode/)有提到，Erlang热更是非常完备成熟的，配合`gen_server State`和FP，让"永不停服"成为了可能。

至于容错，一些文章将容错作为Actor模型的核心理念之一，我个人不是很认同，如[WIKI Actor模型](https://zh.m.wikipedia.org/zh-hans/%E6%BC%94%E5%91%98%E6%A8%A1%E5%9E%8B)介绍的，Actor本身更多强调Actor本身的行为抽象和交互方式。而容错是Erlang link和supervisor机制提供的，可能由于Erlang代言Actor太成功了，以至于不少人认为: "没有容错的Actor不是纯正的Actor"。我在[这里](https://wudaijun.com/2018/07/gs-flexiblity-reliability/)提到过一些Erlang的"let it crash"理念。

因为本文主要聊Erlang Actor 和 Golang CSP，因此热更和容错不作为重点暂开。前面说了Actor的优点，凡事都有两面性，再来看看Actor(仍以Erlang为例)的缺点:

1. 由于只提供不可靠异步交互原语，因此消息QoS，请求响应语义，都需要应用层实现，并且Erlang中的同步请求效率是很低的(需要遍历mailbox)
2. Actor有隔离和边界带来的并发和分布式的优势，也有其劣势，典型地如Actor聚合管理，消息流控等，OOM也是Erlang最常见的问题(Actor数量过大、Mailbox积压消息过多等)
3. 强业务耦合Actor交互场景下，通常只能舍弃强一致性而使用最终一致性，对Actor的建模和划分粒度比较考究。

### Golang CSP

顺序通信进程(Communicating sequential processes，CSP)和Actor模型一样，都由独立的，并发的执行实体(process)构成，执行实体间通过消息进行通信。但CSP模型并不关注实体本身，而关注发送消息使用的通道(channel)，在CSP中，channel是第一类对象，process只管向channel写入或读取消息，并不知道也不关心channel的另一端是谁在处理。channel和process是解耦的，可以单独创建和读写，一个process可以读写(订阅)个channel，同样一个channel也可被多个process读写(订阅)。

对每个process来说：

- 从命名channel取出并处理消息
- 向命名channel写入消息
- 创建新的process

Golang并没有完全实现CSP理论(参见[知乎讨论](https://www.zhihu.com/question/26192499))，只提取了CSP的process和channel的概念为并发提供理论支持。目前Go已经是CSP的代表性语言。

### Golang CSP vs Erlang Actor

从Actor和CSP模型来说:

- Actor 和 CSP 有相同的宗旨："不要通过共享内存来通信，而应该通过通信来共享内存"
- Actor 和 CSP 都有独立的，并发执行的通信实体
- Actor中第一类对象为执行实体(Actor)，CSP第一类对象为通信介质(Channel)
- Actor中实体和通信介质是紧耦合的，一个Actor持有一个Mailbox，而CSP中process和channel是解耦的，没有从属关系。从这一层来说，CSP更加灵活
- Actor模型中Actor是主体，Mailbox是匿名的，CSP模型中Channel是主体，Process是匿名的。从这一层来说，由于Actor不关心通信介质，底层通信对应用层是透明的。因此在分布式和容错方面更有优势。大部分的Actor框架原生支持分布式和容错

具体到Golang和Erlang中的实现来说:

- 两者均实现了语言级的轻量级Actor，在阻塞时能自动让出调度资源，在可执行时重新接受调度。Erlang调度更注重公平性(实时性)，Golang调度更注重吞吐量(性能)
- Golang的Channel是有容量限制的，因此只能一定程度地异步(本质上仍然是同步的)，Erlang的Mailbox是无限制的(也带来了消息队列膨胀的风险)，并且Erlang并不保证消息是否能到达和被正确处理(但保证消息顺序)，是纯粹的异步语义，Actor之间做到完全解耦，奠定其在分布式和容错方面的基础。
- Erlang/OTP在Actor上扩展了对分布式(支持异质节点)、热更和容错的原生支持，Golang在这些方面还有一段路要走(受限于Channel，想要在语言级别支持分布式是比较困难的)
- Golang CSP具备更灵活地并发机制，因为Channel的两个特性: 有容量限制并独立于Goroutine存在。前者可以控制消息流量并反馈消息处理进度，后者让Goroutine本身有更高的处理灵活性。典型的应用场景是扇入扇出，生产者消费者，多路IO复用等。而在Erlang中实现这些则比较困难。另外，Erlang中的做同步请求需要遍历MailBox，而如果用Golang做同步调用，通过单独的Channel来做则更优雅高效

### CSP with Actor

在用Go写GameServer框架时，发现可以将CSP和Actor的一些特性结合起来:

- 游戏中的独立业务实体，如玩家，公会，具备强状态和功能聚合性，适合作为Actor的职责边界，即一个实体一个Goroutine
- 实体与实体之间只通过消息交互，每个实体暴露一个Logic Channel与其它实体进行逻辑交互，再做一层服务发现，即可让请求方只关注对方ID而不关注对方Channel
- 实体还有一些内部的Channel，如定时器，外部命令等。实体Goroutine对这些不同的消息来源Channel进行统一Select，形成多路IO复用的消息泵，并且可以独立控制各Channel大小
- 实体在行为和交互模型上，如Actor一样，从消息泵取出消息进行处理，并更新自己的数据，通过消息与其他Actor(本质是Channel)交互。但由于通信介质是Channel，可以封装更高级易用的交互语义，如同步、请求响应、扇入扇出、流控等
- 当然，基于Golang CSP支持有限，分布式，容错这些就只能框架自己搭建了

如此，即有Actor的封装与边界，又有一定CSP的灵活性。

在研究这个问题的过程中，发现已经有人已经用Golang实现了Actor模型: https://github.com/AsynkronIT/protoactor-go。 支持分布式，甚至supervisor，整体思想和用法和erlang非常像，真是有种他山逢知音的感觉。:)
