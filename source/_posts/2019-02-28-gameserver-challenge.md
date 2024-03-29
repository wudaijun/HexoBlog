---
title: 游戏服务器的挑战
layout: post
categories: gameserver
tags: gameserver
---

聊聊游戏服务器的一些难点，以及它和Web服务器的差异。

## 一. 状态性

游戏服务器是后端，做后端的，每天耳濡目染横向扩展，自动伸缩等炫酷的特性，要说放在以前，这些特性还是巨头的"专利"，我们想要自己实现这些东西挑战性是比较大的，但近几年有了容器生态如k8s的加持，只要你实现了一个无状态应用，你几乎马上就可以得到一个可伸缩的集群，享受无状态本身带来的各种好处，机器挂了自动重启，性能不够了就自动扩展等等。而作为一名游戏服务器开发者，自然也想充分享受容器时代的红利，所以我们来捋捋无状态游戏服务器的可行性。

<!--more-->

我将游戏服务器的状态性分为连接状态性和数据状态性。

### 1. 连接状态性

连接的状态性比较好理解，即我们通常所说的长连接和短连接，游戏服务器通常使用TCP长连接，TCP有如下好处:

- 时序性: 指对请求的顺序性保证，即客户端先发出的请求会被先处理，如果服务器是顺序一致性的，那么响应也满足顺序性。
- 状态性: 在连接建立时进行鉴权，之后这个连接的所有消息都附带上下文(如玩家ID，权限等)，而不用每次请求都带 Header。
- 服务器推送: 这个对游戏来说还是比较重要的，邮件/聊天/广播等功能都依赖于服务器主动推送。

TCP也有一些问题:

- 双端强耦合: 客户端网络环境切换、游戏场景切换、服务端重启等，都需要重新建立连接，并且服务端很难做透明扩展，负载均衡等
- 弱网体验: 因为TCP的特性，一旦丢包就会重发，阻塞住后续的数据包，造成较大的瞬时延迟

针对这两个问题，部分游戏会选择在C/S交互中放弃TCP方案:

为了避免第一个问题，对延迟、性能和推送要求不是很高的游戏，如部分棋牌，卡牌，C/S会直接使用HTTP通信。

为了避免第二个问题，对延迟非常敏感的游戏，如部分即时动作，MOBA，吃鸡，C/S使用UDP来通信，当然，需要基于UDP封装一层可靠(或部分可靠)传输机制。这方面已经有一些成熟的轮子，如[kcp](https://github.com/skywind3000/kcp)，[QUIC](https://github.com/lucas-clemente/quic-go)等。

对于其他大部分游戏而言，C/S和服务器内部主要都还是使用TCP，引入网关来做连接管理、心跳检测、断线重连，流控等，并对客户端屏蔽服务器内部网络拓扑，避免切换场景时需要重新建立连接。

至于服务器集群内部节点间的通信，由于局域网网络比较稳定，基本不存在弱网问题，而针对强耦合问题，通常会对各节点的耦合进行分级，比如支付，Auth这类独立服务通常使用HTTP通信，逻辑交互则使用TCP，但当逻辑节点数量和耦合上去后，另一个需要考虑的问题是节点网络拓扑和全联通。此时通常会引入消息中间件来简化内部网络拓扑，我在[这里](https://wudaijun.com/2018/12/gameserver-communication-model/)也有讨论。

### 2. 数据状态性

通常游戏服务器都是会先将数据更新到内存中，再定期存盘，这意味着服务器内存数据状态和数据库中的数据状态有一定的不一致窗口，这就是所谓的数据状态。

理想情况下，无数据状态服务器的逻辑节点本身只是 Handler，真正的数据放到DB(或Redis缓存)等数据服务中，由于逻辑服务通常是不稳定的，而数据服务通常是相对稳定的，如此逻辑服务更容易做扩展或者主从，逻辑节点挂掉不会造成数据丢失或不一致，并且可以透明重启(暂不考虑连接状态)。

那么游戏服务器为什么不做成无数据状态呢，在游戏中，玩家单个请求，可能造成数10个关联字段的更新，比如一个使用道具的请求就可能涉及到道具，Buff，任务，活动，排行榜等数据更新。这种数据耦合下，范式化分表会带来极大的事务压力(如果不做事务，那么无状态也就意义不大了，因为无法安全地横向扩展)，而反范式化会带来极大的DB数据吞吐压力(每个请求要加载和更新过多的数据)。

另外，对某些逻辑需求而言，无状态服务相对比较难实现的，比如游戏服务器中海量定时器，事件订阅，跨天处理，地图跑桢等等。

因此游戏服务器中，除了极少部分比较独立的服务尽量实现成无状态之外，大部分业务逻辑仍然是有状态的，有数据状态意味着:

1. 横向扩展受限，因此更注重单点性能，需要在逻辑层用并发，异步等各种手段来保证服务器的负载能力。尤其看重异步编程思维。
2. 对服务可用性要求更高，对峰值和边界情况的处理需要更健壮，因为服务不可用的代价很大: 公告+维护+补偿三件套，重新部署，处理意外停机可能导致的数据不一致，玩家流失等。

小结一下，游戏服务器的无状态主要受限于连接状态性和数据状态性，连接状态性还能够针对性地解决，数据状态则难得多，这是游戏业务需求复杂的特性决定的，它一方面限制了游戏服务器的横向扩展能力，另一方面也让服务器对健壮性的要求更高，如果出现一些逻辑上的BUG，停服维护的代价是很大的，特别对于静态语言而言，有状态+无热更=如履薄冰。做很多功能的时候一方面要尽可能保证其正确性，另一方面也要考虑到其容错性，比如出错之后如何监控/调试/修复。别到时候服务器出现问题了，重启一次来打印Log/上下文，再重启一次来修复Bug。或者是等到玩家已经利用该漏洞刷了大量道具，最后修了Bug还要修数据。

## 二. 性能

由于数据状态一定程度地限制了并发粒度(或者是并发的难度)，因此性能也是游戏服务器的关键指标，对游戏服务器而言，性能压力主要来自于:

1. 强交互玩法: 如MOBA,SLG,MMO, 相关的技术优化方案有: 分区服，分房间，分线，AOI，无缝地图，桢同步，客户端演算等。这类强交互玩法会导致服务器大量的演算和推送，如SLG的上行/下行数据量比平均是1:10左右，多人同屏战斗的情况下，可超过1:100
2. 运营峰值: 游戏非常依赖各种运营活动来聚集玩家维持生态，如开服导量，跨服活动，限时Boss等，服务器的一切资源和优化，都是为可能预估到的最大峰值而非均值而准备的
3. 低延迟容忍: 玩家对游戏的响应延迟容忍度是比较低的，排除C/S网络延迟，通常业务层需要保证绝大部分的请求响应延迟在50ms内

## 三. 快速迭代

需求变更快应该是所有互联网行业的共性，但在手游里面会更为突出一些，手游属于内容行业的快消品，讲究唯快不破，频繁地调整玩法体验，然后通过数据分析或AB Test来验证。这非常考验研发[持续快速稳定交付](https://wudaijun.com/2021/07/software-engineering-ability/)的能力，大部分团队前期会比较注重短期快速交付，而忽略持续(毕竟游戏能不能成都不知道)与稳定(缺乏测试框架，通过QA/玩家BUG反馈来修复)。一旦游戏上线后，数据不错，业务需求继续向前推进，服务器非常容易举步维艰，因为此时需要考虑到版本兼容，数据兼容，稳定性风险等。比如对于SLG这类游戏而言，一旦成功推广，运营生命周期通常都是5-10年，很可能在运营过程中，出现如跨服活动，跨服联盟这类"伤筋动骨"的需求，那么如何在项目快速迭代的同时，保持游戏服务器的健壮性和灵活性，是我看来区分技术人员和工程师的分水岭。

为了尽可能延缓架构腐化，游戏服务器由于技术架构和业务模型的差异，通常需要自己搭建[测试框架](通常自己逐步建立[测试框架](https://wudaijun.com/2020/08/gs-testing-practice/))，[DevOps](https://wudaijun.com/2018/08/gs-devops/)，监控报警(可用性/响应延迟/日志/容器/物理机/CCU等)，以保证持续的稳定交付能力。除此之外，还需要不断提炼和重构业务模型代码(比如我们最近在尝试借鉴领域驱动设计的思维进行模块拆分)，保持服务器代码的健康度，以适应后续灵活的需求变更。

## 四. 总结

本文从状态性，性能和快速迭代三个方面简单谈了谈自己的一些理解，其中状态性讲得比较多，因为我认为状态性是导致游戏服务器比常规Web服务器更复杂的直接原因之一，也导致游戏服务器要做到高性能和高可用，需要付出更多的努力。游戏服务器的另一个特性就是需求变更变速，版本迭代快，这需要更灵活地架构设计，更严格的软件工程实践。在游戏行业，唯一不变的就是变化，唯一可信的就是"这个地方不要写死，可能会改"。
