---
title: Erlang+Lua的一次重构
layout: post
categories: erlang
tags:
- erlang
- lua

---

目前所在的项目基于[erlang cluster][1]搭建框架，再接入lua用于写逻辑。由于之前有一些erlang+lua的开发经验，因此着手项目的重构和优化，过程中一些体会，记录于此。

先简述一下项目架构，erlang做集群，网络层，节点交互，DB交互等，lua层只写逻辑。一个erlang的Actor持有一个luastate，为了加速erlang和lua之间的交互效率：

1. 将逻辑数据置于lua中而不是erlang中，在落地时，以二进制格式丢给erlang进行DB操作
2. 以`lual_ref`和msgid等方式，尽量用整数代理字符串
3. erlang和lua异步运行，lua跑在原生线程池中，这在[这篇博文][2]中介绍过

<!--more-->

除了这些，还需要注意lua的沙盒环境管理，错误处理，热更新等，这里不再详述。就目前这种结构而言，还有一些缺陷：

1. 原子线程池忙碌可能导致的erlang虚拟机假死，需要保证原生线程池最多占用的核数不超过erlang虚拟机能使用的核数
2. lua state本身带来的不稳定性，特别是内存，在Actor过多时将会非常明显

第二点，也是目前我们遇到的最棘手的问题，我们知道，在lua中，模块，函数，均是一个闭包，闭包包含函数和外部环境(UpValue，ENV等)，因此在lua中，每个lua state都完整包含加载的所有模块和函数，并且很难共享。我们项目通过一个share lua state完成了对配置表这类静态数据的共享(跨系统进程级的共享可参考[云风blog][3])，但本身逻辑代码占用内存仍然很大，随着逻辑和功能模块的增加，基本一个lua state加载完模块什么也不做，会占用6-7M内存。意味着如果一个玩家一个lua state，那么一台16G内存的服务器，基本只能容纳2000个玩家，内存吃紧，而CPU过剩。因此本次重构也只要针对这个问题。

之前项目组曾针对玩家进行了优化，将主城位于一个岛的玩家归位一组，再将岛按照`%M`的方式放到M个lua state容器上，这样得到一个复杂的，三层逻辑的lua state。针对玩家这一块的内存占用确实大大减少了，但调试难度也提升了，并且扩展性不好，不能将这种容器扩展到其它service(如Union)上。

按照系统本身的理想设计，一个service(player, union)对应一个lua state，由一个erlang process代理这个lua state，并且通过cluster注册/共享这个service的状态信息。但由于lua state的内存占用，不能再奢侈地将service和lua state 1:1调配，多service在逻辑代码中共用一个lua state已经无可避免，我们可以简单将整个系统分为几个层级，

service|lua state|erlang process|cluster
---|---|---|---
N|1|?|?

因此有以下几种可能的方案：

1. `N 1 N N`：每个service对应一个erlang process，多个erlang process将代理同一个lua state，这就需要lua state可以"被并发"，也就是同一个lua state只能绑定一个原生线程池上执行，这一点是可以实现的。这种方案在erlang层会获得更好的并发性能，并且cluster层语义不变。
2. `N 1 1 N`：一个erlang process作为container的概念代理一个lua state，容纳N个service，并且将service和erlang process的映射关系写入cluster，cluster层对外提供的语义不变，但service的actor属性被弱化，service的一致性状态是个问题。
3. `N 1 1 1`：与上种方案类似，只不过将service到container的映射通过算法算出来，而不写入cluster，container本身被编号（编号时，可考虑将serverid编入，这样开新服有一定的扩展性，PS: [一致性哈希][5]方案不适用于游戏这类强状态逻辑），某个service将始终分配在指定container上。这种方案减少了cluster负担，并且减少了service不一致性的BUG。但由于container有状态，在每次系统启动后，service和container的映射关系就确定了，因此整个集群的可伸缩性降低了。

经过几番讨论，我们最终选择了第三个方案，虽然个人认为这类固定分配的方案，与分布式的理念是相悖的，但目前稳定性和一致性才是首要目标。由于采用计算而不是通过mnesia保存映射关系，mnesia的性能和系统一致性得到了提升。本次重构在某些方面与我上一个项目[针对cluster的优化][4]有点相似，一个对系统服务进行横向切割，另一个则纵向切割，前者的初衷是为了更好地交互效率，后者则是处于对lua state资源的复用，两者都降低了系统的可伸缩性，得到了"一个更大粒度"的service。

整个重构过程中，有几点感触：

erlang和lua结合本身不是一种好的解决方案，或者说，erlang接入其它语言写逻辑都不合适，异质化的系统会打乱erlang本身的调度(不管通过nif还是线程池)，并且给整个系统带来不稳定性(CPU，内存)。另外，接入其它语言可能破坏erlang的原子语义和并发性。拿lua来说，原生线程池会和erlang调度线程抢占CPU并且很难管控，加之lua有自己的GC，因此在内存和CPU这两块关键资源上，erlang失去了控制权，给系统带来不稳定性。再加之lua state的内存占用以及lua state不支持并发，你可能要花更多的时间来调整系统结构，最终得到一个相对稳定的系统。如果处理得不好，用erlang做底层的可靠性和并发性将荡然无存。

系统设计，是一个不断根据当前情况取舍的过程，想要一步到位是不可能的。简单，可控，开发效率高才是主要指标，才能最大程度地适应各种变化，快速响应需求。

[1]: http://wudaijun.com/2015/08/erlang-server-design1-cluster-server/
[2]: http://wudaijun.com/2015/09/erlang-server-design2-erlang-lua-battle/
[3]: http://blog.codingnow.com/2012/07/dev_note_24.html
[4]: http://wudaijun.com/2016/01/erlang-server-design5-server-node/
[5]: http://yikun.github.io/2016/06/09/%E4%B8%80%E8%87%B4%E6%80%A7%E5%93%88%E5%B8%8C%E7%AE%97%E6%B3%95%E7%9A%84%E7%90%86%E8%A7%A3%E4%B8%8E%E5%AE%9E%E8%B7%B5/