---
title: 开发笔记(2) pvp server
layout: post
tags: erlang
categories: erlang

---

### PVP简介

接[这里](http://wudaijun.com/2015/08/erlang-server-design1/)，由于是大服机制，每个player_server可以跑在任何player_node上，那么逻辑上的小服并不以一个node实际存在，而仅仅是player上的一个字段，对应的每个逻辑小服需要有个pvp_server进程用于维护pvp，也就是竞技场，由于pvp_server要维护排行榜逻辑，因此每个逻辑小服是只能对应一个pvp_server的。

<!--more-->

在设计pvp_server的时候，需要在Erlang虚拟机上跑客户端的战斗代码，也就是一段Lua代码，整个战斗过程是自动进行的，没有玩家手动操作，Lua战斗代码通过跑桢来运算。但对服务器来说，就相当于一次函数调用。
/Users/wudaijun/Github/wudaijun.github.io/_posts/2015-08-06-erlang-server-design1-cluster-server.md
###1. 最简单的实现

最开始，出于简单考虑，我们使用Port Driver的方式来挂接战斗模块，使用[erlualib](https://github.com/Motiejus/erlualib)库，通过`luam:one_call`执行调用，进行了简单的时间统计：

	new_state: < 1ms
	dostring:  600ms
	call:	   20-300ms
	
客户端的战斗是比较复杂的(3d + 6v6)，跑一场战斗需要接近1s的时间，由于我们逻辑服只有一个pvp_server，同时还肩负维护pvp逻辑和排行榜的职责。因此单是阻塞调度就够头疼的了，设想一下，部署于四核机器上的pvp_node，刚好四个核心(对应四个pvp_server)都阻塞于lua代码中，这段时间整个pvp_node都不能做任何事情。

###2. 避免阻塞调度

Port driver是行不通的，我们还剩下几种方案：

1. 用Ports，将战斗独立为一个操作系统进程
2. 抽象一个pvp_battle的node，只用于跑战斗(但是仍然会照成节点假死的情况)
3. 异步nif

考虑到尽量利用Erlang Node以及以后手动PVP的可能性，我们选择了方案三，而刚好同事写了一个[异步nif库](https://github.com/zhuoyikang/elua)，也就拿来测试了。所谓异步nif，就是在nif内部提供一个C原生线程池，来做nif实际的工作，而Erlang虚拟机内只需要receive阻塞等待结果即可，虚拟机上的阻塞是可被调度的，也就是不会影响到pvp_node上的其它pvp进程的调度。

简单介绍一下elua，elua内部提供一个线程池，每个线程都有自己的任务队列，同一个lua_state上的操作将会被推送到同一个线程的任务队列中(通过简单hash)，以保证lua_state不被并发。elua使用和定制都非常灵活，可以很轻松地添加nif接口和自定义数据类型的序列化。

###3. 序列化数据

在erlualib中，数据序列化是在erlang层完成的，erlang层通过`lua:push_xxx`来将基本数据(bool,integer,atom)一个个压入Lua栈，每一次push操作，都是一次port_command，而战斗入口的数据是比较繁杂的，英雄成长，技能，装备属性等等，涉及很多key-value，一来是序列化效率低，二来是这种数据结构不能兼容于客户端。同一套战斗入口数据，最好能同时用于服务器和客户端的战斗模块。

因此在elua中，我们使用protobuf，通过二进制传输战斗入口数据，这个二进制流也可以传输给客户端，用于支持重放。

###4. 复用luastate

由于每场战斗对lua虚拟机状态依赖很小，因此我们可以事先分配一个lua虚拟机池，将耗时的dostring操作提前完成，之后的战斗直接用该lua虚拟机调用战斗函数即可。

###5. 并发战斗

由于每场战斗是相互独立的，因此战斗可以实现并发，每场战斗之前检查一下玩家状态(如是否当前正在被其它玩家攻打)，取出一个可用的lua_state，然后spawn一个进程来跑战斗，跑完之后将战斗结果cast回pvp进程，进行排行榜变动等后续逻辑处理。

###6. 复用process

为每场战斗spawn一个process主要有两点不妥：效率低以及process数量不可控(当然可以通过luastate池限制)。受限于elua内部的C线程(称为worker)和CPU核心数的多少，并不是erlang process越多，战斗就跑得越快，当战斗请求过多时，请求被阻塞在elua内部各个worker的任务队列中。同时我们还需要改进elua内部的hash算法保证每个请求被均匀地分发到各个worker的任务队列。整个模块的可控性变得很差。

和lua虚拟机池一样，我们可以避免每次战斗都新开process，而是将这些process事先创建好，而创建的个数可以刚好等于elua worker的个数，这样process和worker可以直接保持一对一的关系，process[i]的战斗请求将分发到worker[i]的任务队列。这样我们只需把process的分配调度做好，elua即可高效地利用起来。每个process持有一个luastate，保证luastate不被并发。当战斗请求过多时，消息将阻塞在process的消息队列中，而不是elua worker的任务队列中。

###7. 后续优化

到目前，我们的pvp_server，在并发50场战斗的测试中，响应依次在100ms - 800ms。还远远不够好，剩下的优化从以下几个方面入手：

1. pvp_server的优化，减轻pvp_server的负载，可让pvp_server和pvp_node呈一对一的关系
2. 客户端lua代码的优化
3. 如果仍然不能满足性能要求，将战斗单独做成battle_node
