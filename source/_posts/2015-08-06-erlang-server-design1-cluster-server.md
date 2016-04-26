---
title: 开发笔记(1) cluster server
layout: post
tags: erlang
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

在Erlang中，我们的服务本身通常是一个进程，即Pid，我们可以用分布式数据库mnesia实现一个简易的cluster_server，它处理的一件事是：根据不同Key值(Erlang Eterm)取出对应服务的Pid。cluster_server本身是节点唯一的进程，用于和mnesia交互，实现服务注册/服务查找。除了基础的服务发现，cluster_server还可以做：

- 负载均衡：在mnesia中记录所有节点的负载信息，在创建服务时，将服务分发到当前负载较轻的节点
- 灾难恢复：如果节点挂掉了，节点上的所有服务将被注销(主动注销/失联注销)，通过master监控或者其它机制可以重新创建这个服务，此时服务会被分发到其它可用的节点进行创建，并且重新注册。
- 配置共享：可以向集群中写入一些配置信息，如当前服务的状态(启动中，运行中)，当前节点的状态(负载量)等

为了完成服务创建的动态分发，我们还需要知道哪些节点是可用的，因此需要还维护节点状态表。

	-record(cluster_node, {type, node, share}). % 用于服务创建
	-record(cluster_(type)_process, {id, node, pid, share}). % 用于服务查找
	
其中cluster_node为所有node共享，`cluster_(type)_process` 一般为指定type的node共享。cluster_server提供如下接口：

```
% Type: 进程类型(如player, pvp, agent)
% Id:	进程ID，用于检索进程(如playerid)
% Callback: 创建进程的回调MFA，可用于执行具体创建工作 如 player_sup:start_child(PlayerId)
% Selector: 自定义的node筛选规则，用于选择创建该进程的node
% 该函数通过事务确保MFA执行完成
create_process(Type, Id, Callback, Selector) -> {ok, Record} | {error, Reason}

% 根据进程类型和进程ID，获取进程
get_process(Type, Id) -> {ok, Record} | {error, not_find}

% 添加进程到cluster_(Type)_process表中 Node即为当前node() 一般在进程init()和初始化完成之后调用
set_process(Type, Id, Pid) -> ok | {error, Reason}

% 删除进程 一般在进程terminate时调用
del_process(Type, Id) -> ok
```

[etcd]: https://github.com/coreos/etcd
[zookeeper]: https://zookeeper.apache.org/
[microservice]: http://martinfowler.com/articles/microservices.html#MicroservicesAndSoa
[etcd_introduction]: http://www.infoq.com/cn/articles/etcd-interpretation-application-scenario-implement-principle