---
title: 开发笔记(2) 服务器Lua战斗
layout: post
tags: erlang
categories: erlang

---

服务器战斗系统是自动战斗的，没有玩家实际操作，因此实际上是一份客户端的Lua战斗代码，这里讨论如何在Erlang中植入Lua代码。

<!--more-->

### 1. Port Driver

最开始，出于简单考虑，我使用Port Driver的方式来挂接战斗模块，使用[erlualib](https://github.com/Motiejus/erlualib)库，通过`luam:one_call`执行调用，进行了简单的时间统计，其中new_state<1ms，dostring: 600ms，call: 20-300ms。

由于是3D+NvN的战斗，整个Lua代码跑起来还是很耗时的，跑一场战斗需要接近1s的时间。由于Port Driver中的Lua代码是在虚拟机调度线程上下文中执行的，而Erlang虚拟机无法对原生代码进行公平调度，这会使在Lua代码执行期间，该调度器上其它任务都被挂起，得不到正常调度。

### 2. 异步nif

为了避免阻塞调度，Port driver是行不通的，我们还剩两种方案：

1. 用Ports，将战斗独立为一个操作系统进程
2. 异步nif

考虑到尽量利用Erlang Node以及以后手动PVP的可能性，我选择了方案二，而刚好同事写了一个[异步nif库](https://github.com/zhuoyikang/elua)，也就拿来测试了。所谓异步nif，就是在nif内部提供一个C原生线程池，来做nif实际的工作，而Erlang虚拟机内只需要receive阻塞等待结果即可，Erlang层面的阻塞是可被调度的，也就是不会影响到节点上其它进程的公平调度。

简单介绍一下elua，elua内部提供一个线程池，每个线程都有自己的任务队列，同一个lua state上的操作将会被推送到同一个线程的任务队列中(通过简单hash)，以保证lua state不被并发。elua使用和定制都非常灵活，可以很轻松地添加nif接口和自定义数据类型的序列化。

### 3. 序列化数据

在erlualib中，数据序列化是在erlang层完成的，erlang层通过`lua:push_xxx`来将基本数据(bool,integer,atom)一个个压入Lua栈，每一次push操作，都是一次port_command，而战斗入口的数据是比较繁杂的，英雄成长，技能，装备属性等等，涉及很多key-value，一来是序列化效率低，二来是这种数据结构不能兼容于客户端。同一套战斗入口数据，最好能同时用于服务器和客户端的战斗模块。

因此在elua中，我选择使用protobuf，通过二进制传输战斗入口数据，这个二进制流也可以传输给客户端，用于支持重放。

### 4. 进程池

由于每场战斗是独立的，原则上对lua state是没有依赖的，事先分配一个lua state池，将耗时的dostring操作提前完成，每场战斗取出一个可用的lua state，然后spawn一个battle_worker进程来跑战斗，跑完之后将战斗结果cast回逻辑进程，进行后续逻辑处理。这样receive阻塞放在battle_worker中，实际Lua代码执行由elua线程池完成，对逻辑进程来说，是完全异步的。

受限于elua内部的C线程(称为worker)和CPU核心数的多少，并不是erlang process越多，战斗就跑得越快，当战斗请求过多时，请求被阻塞在elua内部各个worker的任务队列中。并且spawn的process不够健壮，也没有重启机制。显然我们应该让worker process常驻，并且通过gen_server+sup实现，worker process的个数可以刚好等于elua worker的个数，这样process和worker可以直接保持一对一的关系，修改elua任务分配hash算法，让process[i]的战斗请求将分发到worker[i]的任务队列。这样我们只需把process的分配调度做好，elua即可高效地利用起来。每个process持有一个lua state，保证lua state不被并发。当战斗请求过多时，消息将阻塞在process的消息队列中，而不是elua worker的任务队列中。

另外，如果战斗模块负荷较重，可以将elua线程池的大小设为Erlang虚拟机可用的CPU个数-1，这样即使elua所有线程忙碌，也不会占用全部的CPU，进一步保证节点其它进程得到调度。

### 5. 无状态服务

到这里，我们讨论的都是如何将Lua代码嵌入在逻辑服务器中，如pvp_server，这样做实际上还有两点隐患：

1. 多个pvp_server不能有效地利用同一个pvp_node资源，因为它们具有各自的worker proces pool
2. 我们都假设elua和Lua战斗代码是足够健壮的，虽然Lua代码本身的异常可以通过`lua_pcall`捕获，但是Lua虚拟机本身的状态异常，如内存增长，仍然是不稳定的因素，可能会影响到整个pvp_node的逻辑处理

因此，将所有Lua战斗相关的东西，抽象到一个battle\_node上，才是最好的方案，battle\_node本身没有状态，可以为来自不同ServerId，不同模块的战斗请求提供服务，battle\_node上有唯一的battle_server，动态管理该节点上的battle\_worker process，并且分发任务，battle\_server本身不属于任何一个ServerId。battle_worker由sup监控，并且在启动和挂掉时，都向battle\_server注册/注销自己。

battle\_server仍然需要向cluster\_server注册自己，只不过不是以逻辑Server：{NodeType,ServerId,Node,Pid}的方式，而是以服务的方式：{ServiceName,_,Node,ServicePid}注册自己，cluster_server需要为Service提供一套筛选机制，在某个服务的所有注册节点中，选出一个可用节点:`cluster_server:get_service(ServiceName)`。

再来看看整个异常处理流程：

- lua代码错误: lua_pcall捕获 -> Erlang逻辑层的battle_error
- battle_worker crash: 向battle_server注销自己 -> battle_worker_sup重启 -> 重建lua state -> 向battle_server重新注册自己
- battle_server crash: 终止所有battle_worker -> 向cluster_server注销自己 -> battle_server_sup重启 -> 重新创建所有battle_worker -> 向cluster_server重新注册
- elua crash: battle_node crash -> 该节点不可用 -> 外部请求仍然可能路由到该节点 -> 战斗超时 -> cluster_server检测到(节点心跳机制)该节点不可响应 -> 在集群中删除该节点 -> 外部请求路由到其它可用节点

并且整个战斗系统的伸缩性很强，可以通过简单添加机器来缓解服务器战斗压力。

### 6. Lua代码热更

这个是Lua的强项，直接通过elua再次dofile Lua入口文件即可，但是要保证该Lua入口不具备副作用，如对一些全局符号进行了改写，否则下一次直接dofile，将叠加这种副作用从而导致代码异常。如果有一些全局初始化操作，应该单独抽离出来，放在另一个Lua文件中，只在创建Lua虚拟机时执行。

另一种热更方案是，每次都重新创建一个Lua虚拟机，这样可以保证每次热更后的Lua虚拟机状态都得以重置恢复。

最重要的是，这一切，所有外部请求来说，都是透明的。
