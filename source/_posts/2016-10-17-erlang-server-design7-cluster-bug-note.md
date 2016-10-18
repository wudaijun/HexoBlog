---
title: 开发笔记(7) 记线上一次回档BUG
layout: post
categories: 
- gameserver
tags:
- erlang
- distribution

---
### 问题描述

有十几个玩家报告被回档，几小时到一两天不等

### 问题背景

在我们的[集群架构](http://wudaijun.com/2016/01/erlang-server-design5-server-node/)中，集群有若干GS节点，每个GS节点可部署N个GS服务器，整个集群所有的玩家进程注册于cluster，我们通过为每个服开一个player_mgr来维护单服玩家状态，player_mgr维护{player_id, agent_pid, player_pid}三元组，用户处理多点登录，单服逻辑，离线玩家LRU等。cluster本身只提供服务注册/注销，如果做服务替换(如agent)，确保服务的唯一性(如player)应该由外部逻辑来确保，cluster并不知晓内部各种服务的特性。player进程启动/终止时，会向player_mgr和cluster分别注册/注销自己。

<!--more-->

### 问题追踪

1. error日志中出现几十个rewrite player process(重写cluster中player服务)的错误日志，并且这些玩家基本都属于一个公会
2. 所有玩家进程的启动(login, get_fork)均由player_mgr控制，player_mgr确保玩家进程唯一，依赖的是自身的State数据，而不是cluster，问题可能出在player_mgr 和 cluster 状态不一致上
3. 写了个检查脚本，查出仍有有个别玩家存在于cluster而不在player_mgr中，这类玩家在get_fork或login时，player_mgr会重新开一个player进程，导致rewrite player process，此时同一时刻就存在两个player进程(老玩家进程Pid0，新玩家进程Pid1)，已有Agent消息会被重新路由(通过cluster服务查找)到Pid1进程上，而Pid0不在cluster和player_mgr中，不会被终止，但会不断写盘，称第三方进程，这是导致玩家回档的根本原因
4. 现在问题焦点：为什么player_mgr维护的数据和cluster不一致(比cluster少)
5. 在player_mgr LRU剔除玩家进程时，是先在自己State中删除玩家进程，再cast消失让玩家进程终止，最后在player_server:terminate中，再向player_mgr和cluster注销自己。那么存在这样一种情况：player_mgr LRU剔除玩家进程Pid0到 player_server:terminate从cluster中注销自己之间，新的login或get_fork请求到来，此时player_mgr再启动了Pid1，并且rewrite player process，那么当Pid0 terminate时，检查到cluster中当前服务不是自己，不会更新cluster，之后，Pid0还会向player_mgr注销自己，并且没有带上Pid进行Pid检查，因此将Pid1从player_mgr中删除了！至此，player_mgr和cluster出现了不一致，cluster中存在Pid1程，而player_mgr中没有。下一次玩家login或get_fork一个新的Pid2时，Pid1被rewrite，Pid1也就成了第三方进程
6. 上面的概率看起来很小，但由于公会等组逻辑，可能导致N个玩家同时被get_fork起来，而LRU又是player_mgr统一定期(10分钟)清理的，因此如果alliance前后10分钟get_fork两次，问题出现的概率就被放大了，这也是本次出问题的玩家基本都在一个公会的原因

### 问题来源

1. player_mgr在没有确认玩家进程已经退出时(此时可能还有一堆消息没处理完)，就删除了它
2. 玩家进程在向player_mgr注销自己时，没有做Pid检查，注销了其它进程(没有考虑容错)

### 问题修复

线上热更的方案：

1. player_mgr和cluster均在player terminate时才确认注销
2. 服务注销时做Pid检查
3. 在玩家进程定期存盘时检查其cluster和player_mgr状态，并stop掉第三方进程

### 问题反思

 本质上来说，这次的问题源于：
 
 1. 数据冗余导致短暂的不一致状态(player_mgr和cluster不一致)
 2. 在这种不一致状态下的特定事件(player login/get_fork)，导致不一致的影响被放大(存在第三方玩家进程)
 3. 对这种不一致状态缺乏检查和处理，导致BUG(玩家回档)
 
在Code Review的过程中，还发现一些其它并发和异步问题。在多Actor异步交互模型中，调度时序，网络时延都可能导致状态不一致。在分布式系统中，想要从根本上杜绝不一致，是几乎不可能的(我们对同步和事务非常敏感)，因此我们不只是要从问题预防上考虑，还要从错误恢复上着手，让系统具备一定程度的"自愈能力"：

预防：减少不一致的可能性

1. 减少数据冗余，将cluster作为数据的第一参照，player_mgr的优先级降低，并只用于全服逻辑
2. 简化player_mgr的功能，如将离线玩家的LRU移到player自身去管理

恢复：检查并修复不一致

1. 在服务启动/运行/终止时，加上检查和修复机制，并记录日志
2. 跑定时脚本检查player_mgr和cluster的一致性，并予以临时修复和报警

最后，总结出的经验是，在分布式系统中，对问题的检查和修复，和问题的预防同样重要。


     
