---
title: 开发笔记(1) cluster server
layout: post
tags:
- erlang
- distribution
categories: erlang

---

### 服务发现

在游戏服务器中，通常有一些功能本身非常内聚，甚至是无状态的，在这种时候，我们应该将其单独地做成一个服务，而不是嵌入到GameServer中，这种思想就是所谓的服务([microservice][])思想。

服务发现本身可以看做是一个业务独立的"特殊服务"，它用于逻辑服务的注册/查找/配置信息共享。通常由如下三部分组成：

- 一个强一致，高可用的服务存储
- 提供服务注册和服务健康状态监控的能力
- 提供查找服务，连接服务的能力

在分布式领域中，服务发现是一个非常实用和通用的组件，并且已经有一些比较成熟的组件，如[zookeeper][zookeeper]，[etcd][etcd]等。服务发现组件的好处有很多：微服理念，为负载均衡，灾难恢复提供基础。更多应用场景，可参见etcd的[这篇文章][etcd_introduction]。

<!--more-->

### cluster_server

先来谈谈我们的集群划分，基于我们的服务器设计，整个集群由N个node组成，node可根据其职责来划分，如player_node，master_node，pvp_node，每个node上跑对应类型的进程，每种node可有多个。其中master_node负责监控/管理所有业务逻辑node，新加入的node只需和master_node连接，这种粒度的划分本身是有利弊的，我们在之后的开发中对它进行了[改进](http://wudaijun.com/2016/01/erlang-server-design5-server-node/)，就我们本身cluster_server的设计初衷而言，本质职责是没变的。

在GS中，我们在查找某个服务时，如某个PlayerId对应的player_server，我无需知道这个player_server位于哪个player_node上，甚至无需知道是否在本台物理机上，我只需获取到这个player_server的Pid，即可与其通信。显然地，为了将服务的使用者和服务本身解耦，我们需要维护这样一个 PlayerId -> player_server Pid 的映射表，并且这个表是集群共同访问的，这也就是服务发现的基本需求。

#### 服务注册/查找，状态共享

在Erlang中，我们的服务本身通常是一个进程，即Pid，我们可以用分布式数据库mnesia实现一个简易的cluster_server，它处理的一件事是：根据不同Key值(Erlang Term)取出对应服务的Pid。cluster_server本身是节点唯一的进程，用于和mnesia交互，实现服务注册/服务查找。为了方便使用，我将Key定义为一个type加一个id，表的初步定义如下：

	-record(cluster_(TYPE)_process, {id, node, pid, share}).  % TYPE: pvp player 等  share: 用于状态共享

基于这张mnesia表，可以实现如下功能：

1.  服务注册：通过事务保证写入的原子性，将不同类型的服务写入对应的表中
2. 服务查找：根据不同的类型访问不同的表，用mnesia的ram_copies来优化读取，使读取像本地ets一样快
3. 服务注销：在服务不可用或被终止时，通过事务删除对应表条目
4. 状态共享：通过share字段可以获知服务的当前状态或配置

#### 服务创建，负载均衡

上面实现了最简单的服务注册/查找机制，服务本身的创建和维护由服务提供者管理，在GS集群中，通常我们是希望所有的服务被统一监控和管理，比如某个服务节点挂了，那么上面的所有服务将被注销(主动注销/失联注销)，这个时候应该允许使用者或master重启该服务，将该服务分配到其它可用节点上。

因此我们还需要维护可用节点表，用于服务创建：

	-record(cluster_(type)_process, {id, node, pid, share}).

通过share字段，可以获取到节点当前的状态信息，比如当前负载，这样做负载均衡就比较容易了，将服务创建的任务分发到当前负载较轻的节点即可。

#### 服务监控，灾难恢复

对于关键的服务或者是无状态的服务，可以通过master来监控其状态，在其不可用时，对其进行选择性恢复。比如当某服务所在物理机断电或断网，此时上面的服务都来不及注销自己，通过`monitor_node/2`，master会在数次心跳检测失败后，收到`nodedown`消息，此时master节点可以代为注销失联结节点上所有服务，并且决定这些服务是否需要重建在其它节点上。

### 注意事项

#### 一致性问题

- 如果不使用事务，服务A可能覆写/误删服务B
- 服务注册信息同步到其它节点的时间差，可能导致的不同步(服务的写入者无论是服务的发起方还是服务本身，都会存在这个问题)。

解决方案：

1. 使用事务

	这是最"简单"的方案，主要是性能问题，特别是游戏的波峰时段，这种延迟会扩散

2. 串行化服务管理

	将服务的查找或者是注册/注销，交由一个Proxy来做(经由某种分组规则ServerId)，则可使用脏读写，避免一致性问题。但是会有单点，并且弱化了分布式的特性。
	
3. 服务查询

	将表不添加本地拷贝，直接使用remote类型表进行访问(事务)，在本节点对Pid进行保存，采用某种机制来确保缓存Pid的正确性(如monitor)

4. 退化ETS

	将一些频繁访问和使用的服务退化为ETS(特别是player和agent)，主要目的是减轻mnesia压力(28原则)，使mnesia可以安全的使用事务。但这部分服务也失去了使用mnesia的优势，个人觉得不如方案3。
	
#### 全联通问题

mnesia必须建立在全联通网络上，在节点数量超过10个时，就需要关注这个问题了。

解决方案：

可为节点分组(如5个一组)，设定代理节点，由代理节点组成mnesia集群。

[etcd]: https://github.com/coreos/etcd
[zookeeper]: https://zookeeper.apache.org/
[microservice]: http://martinfowler.com/articles/microservices.html#MicroservicesAndSoa
[etcd_introduction]: http://www.infoq.com/cn/articles/etcd-interpretation-application-scenario-implement-principle