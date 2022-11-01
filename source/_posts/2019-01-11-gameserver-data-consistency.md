---
title: 游戏服务器的数据一致性
layout: post
categories: gameserver
tags: gameserver
---

前段时间又和同事讨论到 GS 中的 数据一致性，在这里简单聊聊。这里的数据一致性即系统内部的数据一致性(ACID中的C)，而非分布式系统对外体现的一致性(CAP中的C)。

假设我们有一个业务逻辑叫做行军，玩家需要先消耗一定的钻石，才能发起行军。在单线程下，其逻辑如下:

```
if !checkDiamond(cost) {
    return error_Diamond_not_enough
}

if !checkMarch(troopId) {
    return error_troop_can_not_march
}

deductDiamond(cost)
startMarch(troopId)
```
    
这个逻辑在单线程下是没什么问题的，如果现在我们由于性能原因，将 Play(玩家数据逻辑) 和 Map(大地图玩法) 分为了两个 Actor (如goroutine,节点)，玩家钻石由 Play Actor 管理，部队数据由 Map Actor 管理，那么我们现在的逻辑变成了分布式中最常见的 Check-Do 模型:

<!--more-->

| Play | Map |
| --- | --- |
| checkDiamond | checkMarch |
| deductDiamond | startMarch |

现在我们讨论如何在这种情形下尽可能提升数据一致性，假设 Play 和 Map 以异步消息的方式交互，然后我们来考虑如下执行流:

执行流A:

| Steps | Play | Map |
| --- | --- | --- |
| 1 | checkDiamond |  |
| 2 | deductDiamond |  |
| 3 |  | checkMarch |
| 4 |  | startMarch |

该执行流的异步交互少(理想情况下只需要一次)，但问题也比较明显，出现数据不一致的概率(时间窗口)太大了: Play在完全没有检查Map行军状态的时候，就扣钻石了。当Map执行到`checkMarch`检查失败时，通常有两种做法:

- 回滚: 发消息给Play把钻石加回来，开发复杂度上去了，玩家体验还不一定好(大概率会看到钻石扣了又涨)
- 不回滚: 玩家差评和客服工单正在路上

为了减少数据回滚的可能性，我们先总结第一条 Rule: 先 Check 再 Do:

执行流B:

| Steps | Play | Map |
| --- | --- | --- |
| 1 | checkDiamond |  |
| 2 |  | checkMarch |
| 3 |  | startMarch |
| 4 | deductDiamond |  |

这个执行流稍微要复杂一些，通过先 check 再 do 的方式缩小了数据不一致的时间窗口，避免了逻辑检查(`checkMarch`)导致需要回滚的问题。但异步交互本身的不一致问题仍然存在，比如Play在checkDiamond之后，立马收到并处理了一条购买消息，扣除了钻石，导致行军deductDiamond时，钻石不够了，此时就麻烦了: 玩家做了事，但没扣(够)钻石，还很难回滚行军(广播，任务统计等牵扯系统太多)，并且玩家很可能会总结并找到这种刷漏洞的方法。因此，我们可以总结出第二条 Rule: 先 Deduct 再 Do。

执行流C:

| Steps | Play | Map |
| --- | --- | --- |
| 1 | checkDiamond |  |
| 2 |  | checkMarch |
| 3 | deductDiamond |  |
| 4 |  | startMarch |

现在这个执行流异步交互最复杂，如果 Step 1,3 发生不一致，Step 3失败，行军逻辑无法继续。但如果 Step 2,4 发生不一致，Step 4失败，此时钻石已经扣除，可以通过 Step 5 发消息给 Play 把钻石加回来，也可以通过日志手动 Fix(当逻辑回滚比较复杂，或者是非关键业务时)。

执行流D:

上例中，其实我们有假设deductDiamond和startMarch内部包含checkDiamond和checkMarch逻辑，以保证API的原子性。如果deductDiamond不包含checkDiamond语义的话(比如deductDiamond在钻石不够时，会尝试将剩余的钻石全部扣除，而不是直接返回错误码)，那么逻辑层应该显式再check一遍，确保逻辑的完备性。因此，更完整的执行流是这样的:

| Steps | Play | Map |
| --- | --- | --- |
| 1 | checkDiamond |  |
| 2 |  | checkMarch |
| 3 | checkDiamond |  |
| 4 | deductDiamond |  |
| 5 |  | checkMarch |
| 6 |  | startMarch |

到目前为止，我们来理理前面提到的:

1. 整个执行链，应该是 Check 链 + Do 链，减少数据不一致的时间窗口
2. 必要时，Do之前再Check一次，保证Do语义的准确性
3. Do链中，先 Deduct 再 Give，保证数据安全性(如玩家刷道具)以及回滚的可行性
4. 关键或易发的数据不一致可以逻辑回滚(如涉及到货币扣除)，其他数据不一致可通过排查日志来修复

下面是几个常见问题:

Q1. 为什么不通过分布式事务或锁来保证一致性？

分布式事务，如常见的2PC、3PC、TCC、SAGA等(我在[一致性杂谈](https://wudaijun.com/2018/09/consistency/)中有聊过)，对游戏服务器而言，通常都过于重度。以2PC为例，它其实和我们的执行流C有点类似，都是先询问各个参与者(Play, Map)是否可以提交(CanCommit)，再执行提交(DoCommit)，只不过2PC中的协调者可用性和可靠性更高。但引入2PC，会带来如单点问题，响应延迟，开发效率等新的问题。

分布式锁(如redis锁)也有类似的问题，并且锁主要是解决数据互斥访问的问题，而非数据事务一致性的问题。不恰当地用锁来解决解决事务一致性问题，会严重降低系统的吞吐量，甚至降低服务器的健壮性。

游戏服务器的大部分场景，是数据一致性不敏感但性能敏感(包括吞吐量和响应延迟)的，我们会时常为了性能舍弃部分数据一致性。因此通常在游戏服务器中，只有极少数关键业务场景，才会考虑用事务和锁来实现数据一致性。

Q2. 为什么不用同步RPC？

为了避免`checkDiamond`和`deductDiamond`，以及`checkMarch`和`startMarch`的不一致性，我们可以让 Map `checkMarch` 后，直接同步调用 Play 的`deductDiamond`，然后根据扣除是否成功执行后续操作。这样很大程度上避免了不一致性。然而同步调用可能会带来更多的问题(吞吐量，环形阻塞，雪崩等)，我在[游戏服务器中的通信模型](https://wudaijun.com/2018/07/gameserver-communication-model/)中有详细讨论。

Q3. 关于超时?

考虑这样一种情况，当执行流C Step3 `deductDiamond`之后，Map 因为各种原因(网络波动，甚至节点挂掉)没有处理到 `startMarch` 这条消息，然后整个执行流就断掉了，就没有下文了(这也是2PC 协调者单独存在的一个作用)。那么我们是否应该给异步调用一个超时，让发起者可以对对端无响应有所感知加以处理？这个问题我在游戏服务器中的通信模型也提到过(异步消息和异步请求-响应的区别)。就我们目前的实践而言，这类逻辑耦合较重的场景会被实现为异步请求-响应式而非单纯异步消息，而一个完整的请求-响应语义，是应该带超时机制的。

Q4. 通过更细粒度的 Actor 化异步为同步？

既然异步交互维护数据一致性这么麻烦，并且开发效率也低，那如果是将Actor粒度拆细，比如单个玩家一个goroutine，甚至单请求一个goroutine，那么同步调用的代价也就不那么可怕了。道理是这样的，但是一方面在游戏后端，业务复杂性才是限制并发模型的主要原因(数据耦合越重，拆分越困难，比如地图线程)，另一方面，细粒度Actor+同步本质只一定程度减轻(没有根治)了同步调用带来的吞吐量和雪崩的问题，没有解决环形阻塞问题，并且还有Actor管理，调度开销等新引入的问题要纳入考虑。最终还是开发效率、性能、健壮性、数据一致性以及业务需求(比如棋牌/卡牌就比较适合Actor模型)上的综合权衡。对游戏服务器而言，大部分情况下，对性能和健壮性的考量，要优于数据一致性。

