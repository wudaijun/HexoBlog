---
title: 开发笔记(1) cluster server
layout: post
tags: erlang
categories: erlang
---

## 设计原则

无单点，高可用性，强大的热更支持。

## 集群

整个服务器可能有很多node，node可根据其职责来划分，如player_node，master_node，pvp_node，每种node可有多个。其中master_node负责连接和管理所有node，新加入的node只需和master_node连接，即加入了整个集群。

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


##PlayerServer：

数据库： [mongodb][]

网络层： [ranch][]

协议层： [protobuf][]

为了更好地支持热更时的数据结构兼容性，我们将整个玩家数据PlayerData组织为dict，放在gen_server的State中。尽管对于交互性弱的游戏来说，将玩家数据模块化放在进程字典中更快更方便，但是在代码可读性和数据管理上，会更麻烦。而且将PlayerData置于gen_server state中的另一个好处是：所有消息处理都具备事务性。逻辑处理上遇到错误可通过抛异常的方式结束处理，消息分发器捕获异常，响应错误消息。整个消息处理中，PlayerData要么被正确处理，要么不变。

将PlayerData组织为dict而不是record的原因有两个：一是为了更好地支持热更机制，二是[dict与mongodb的转换][dict_mongodb]比较方便。

至于其它的Agent进程与Player进程关联，登录重登机制，都大同小异。现在在考虑的一件事是落地优化，目前实行的落地是直接覆写，没有进行字段跟踪或模块标记来优化。

[mnesia]: http://wudaijun.com/2015/04/erlang-mnesia/
[mongodb]: https://github.com/comtihon/mongodb-erlang
[ranch]: https://github.com/ninenines/ranch
[protobuf]: https://github.com/basho/erlang_protobuffs
[dict_mongodb]: http://wudaijun.com/2015/07/erlang-mongodb/
