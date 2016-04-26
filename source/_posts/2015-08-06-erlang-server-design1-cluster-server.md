---
title: 开发笔记(1) cluster server
layout: post
tags: erlang
categories: erlang
---

## 需求提出

基于我们的服务器需求，整个集群有很多node，node可根据其职责来划分，如player_node，master_node，pvp_node，每种node可有多个。其中master_node负责监控/管理所有业务逻辑node，新加入的node只需和master_node连接，即加入了整个集群。基于Erlang本身的分布式特性，当我在查找某个服务时，如某个PlayerId对应的player_server，我无需知道这个player_server位于哪个player_node上，甚至无需知道是否在本台物理机上，我只需获取到这个player_server的Pid，即可与其通信。显然地，为了将服务的使用者和服务本身解耦，我们需要维护这样一个 {PlayerId -> player_server Pid}的映射表，并且这个表是集群

## 服务发现

服务发现本身可以看做是一个业务独立的"特殊服务"，它用于逻辑服务的注册/查找/配置信息共享。关于服务发现领域，已经有一些比较成熟的组件，如[etcd][etcd]。

<!--more-->

后端集群集中处理的一件事是：根据{type, id}二元组创建/取出对应进程Pid，比如type为player，id则为playerid，根据这两个值取出玩家进程Pid，而不管该进程实际运行于哪个player_node上，进程位置对于应用来说是透明的。理想情况下，每个node部署在一台物理机上，当一个物理机挂掉之后，之后负载将分发到其它同类型的node，而挂掉的node已有的进程将重新创建在其它node上。对玩家进程来说，就是一次重新登录。包括master_node在内，所有类型的node至少配置两个以上，这样，整个系统是没有单点的。

如果由其它语言来实现这样一个集群，可能颇为麻烦，因为要实时同步所有node信息和node上的process信息。但通过[Erlang mnesia][mnesia]来做这件事，却只需几百代码。得益于mnesia天生分布式的特性，可以将node信息和process信息存入mnesia表中：

	-record(cluster_node, {type, node}).		       % 用于进程创建
	-record(cluster_(type)_process, {id, node, pid}). % 用于进程获取

其中cluster_node为所有node共享，`cluster_(type)_process` 一般为指定type的node共享。cluster_server提供如下接口：

```
% Type: 进程类型(如player, pvp, agent)
% Id:	进程ID，用于检索进程(如playerid)
% Callback: 创建进程的回调MFA，可用于执行具体创建工作 如 player_sup:start_child(PlayerId)
% Selector: 自定义的node筛选规则，用于选择创建该进程的node
create_process(Type, Id, Callback, Selector) -> {ok, Pid()} | {error, Reason}

% 根据进程类型和进程ID，获取进程
get_process(Type, Id) -> {ok, Pid()} | {error, not_find}

% 添加进程到cluster_(Type)_process表中 Node即为当前node() 一般在进程init中调用
set_process(Type, Id, Pid) -> ok | {error, Reason}

% 删除进程 一般在进程terminate时调用
del_process(Type, Id) -> ok
```

[etcd]: https://github.com/coreos/etcd