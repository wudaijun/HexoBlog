---
title: 一些GS设计理念
layout: post
categories: gameserver
tags: gameserver

---
关于GS设计的一些体会，纯属个人理解。

## 一. 系统结构

解耦是在做系统设计时，最应该铭记于心的原则，解耦的目的是让**系统组件可以独立变化**，构建易于理解，测试，维护的系统。

解耦的手段通常有如下几种：

### 1. 依赖倒置

依赖倒置的原则：上层模块不应该依赖于下层模块，它们共同依赖于一个抽象。抽象不能依赖于具象，具象依赖于抽象。

[依赖倒置][]原则的目的是把高层次组件从对低层次组件的依赖中解耦出来，这样使得重用不同层级的组件实现变得可能。如模块A依赖于模块B，那么在A和B之间加一层接口(interface)，A调用(依赖)该接口，B实现(依赖)该接口，这样，只要接口稳定，A，B即可独立变化。

这种依赖抽象的思想，在GOF的设计模式中，有大量宝贵实践，如策略模式，模板方法模式等。

<!--more-->

### 2. 控制反转

依赖倒置描述的是组件之间的依赖关系被倒置，而控制反转更强调的是控制流程，体现了控制流程的依赖倒置。典型的实现方式：

#### 依赖注入

反转依赖对象的获取，由框架注入组件所依赖的对象(被动接收对象)。

#### 依赖查找

反转依赖对象的获取，由组件通过框架提供的方法获取所需依赖对象(主动查找对象)。微服务系统中的服务发现(比如我们的[cluster_server][])，就是一种依赖查找机制。

#### 事件发布/订阅

反转对事件的处理，发布方不再关心有哪些接收方依赖了某个事件，由接收方主动订阅事件并注册处理函数。在GS设计中，经常会用到，如任务系统，通知中心等。

向依赖和耦合宣战，就是和混乱和失控划清界限，解耦也有助于更好地复用代码，在我看来，重复和耦合一样危险。在发现已有系统不能很好地兼容变化时，就应该理清组件依赖，将变化封装起来。这里有一篇关于[依赖导致和控制反转][ref 1]不错的文章，在GOF设计模式中有更全面精辟的实践经验。

## 二. 系统拆分

在系统结构中，更多地去梳理系统内部的结构和对象行为的关系，而系统拆分则尝试从架构设计的角度将系统拆分为多个小系统(服务)，这些服务独立运行(Routine/Actor/进程等)，服务之间遵循某种通信规范(Message/RPC/TCP/Channel等)。不同粒度的服务的优劣各不相同，一方面我们希望服务彼此独立并且无状态，另一方面我们也希望有服务间的通信足够高效(通过缓存，消息，或远程调用)。需要注意的是，这里所说的服务，并不只是微服务，像Erlang中的Actor，Go中的goroutine，都可以叫服务。以下只讨论最基本的服务设计。

### 1. 服务的数据管理

以Erlang为例，GS中存在多种实体(Actor)，玩家，公会，地图等，实体之间的交互产生了一些关联数据，我们需要明确这类数据的归属权和数据的同步方式，制定清晰的数据边界。数据只能由其所属Actor进行更新和同步，并且是数据的唯一正确参照。关于数据同步，此前我们一直严格遵循"通过通讯来共享"，在带来很好的隔离性的同时，也带来更高的复杂度，大量的Actor数据同步通信，非必要的实时性同步，多份数据副本等等。之后开始使用Ets做Cache，数据冗余和逻辑复杂度都小了很多。使用Cache时，需要严格遵守单写入者，即数据的Cache只能由数据所属Actor进行更新。

### 2. 服务发现

前面也提到，服务发现实则是对服务之间的依赖关系的倒置，服务发现是系统具备良好扩展性和容灾性的基础。目前已经有一些成熟的服务发现和配置共享工具，如etcd，zookeeper等。

### 3. 无状态服务

服务应该尽量被设计为无状态的，这样对容错和透明扩展都有巨大好处，在[这篇博客][battle_node]中我曾提到到无状态服务的实践。


## 三. 过度设计

在设计系统时，有时候我们会为了设计而设计，过度抽象和封装，这种过度设计会导致：

- 浪费不必要的开发时间和精力在很简单的逻辑上
- 产生很多不必要的约定和限制，随着项目需求的变更和增长，会成为系统的负担，很可能也并不能满足新需求

如何辨别过度设计，我的理解是，首先这个系统是否需要重构，如果系统足够简单，或者足够稳定，那就let it alone。将精力花在核心系统上，并且在必要的时候(已有架构不能满足当前需求(不是YY的需求)或者已经带来大量的复杂度)再进行重构，特别是对于游戏服务器来说，需求迭代很快，提供可靠的服务才是宗旨，不要陷入设计的漩涡。

## 四. 防御式编程

防御是为了隔离错误，而不是为了容忍错误。在实际运用中，API职责不单一，过度防御，都可能将错误隐藏或扩散出去，对系统调试带来麻烦。应该遵循职责单一，语义明确的API设计理念，对Erlang OTP这种高容错的系统，提倡让错误尽早暴露而不是容忍，对于一些严重错误，甚至应该Crash。错误的尽早暴露有利于Debug，找到问题的源头。

## 五. 注重测试

测试分为黑盒和白盒，对后端来说，黑盒相当于模拟客户端，发出请求，并确保得到正确响应。白盒为服务器内部的函数测试，模块测试，数据检查等。

就实现上来说，游戏服务器主要的测试的方式有：

### 1. 测试用例

以逻辑功能为测试单元，模拟客户端请求流程，尽可能多地覆盖正常分支和异常分支。优点是覆盖完善，使用简单，可以检查并暴露出绝大部分问题。缺点是维护麻烦，对上下文环境(配置，流程，协议等)进行了过多地依赖，适用于需求稳定，流程简单的功能模块。

### 2. 测试状态机

状态机是一个独立的Actor，也叫做Robot，通常基于有限状态机，对所有事件(外部命令，服务器消息，内部事件)作出响应。在Erlang中可以用gen_fsm来实现，一般被设计为可扩展的事件处理中心，Robot的优点有很多，灵活，强大，可以对服务器进行压测，针对性测试，以及长期测试。将一些常用的测试模式做成一个Mode集成到状态机中，如大地图测试，登录流程测试等，再结合bash脚本和后台定时任务，一个服务器测试框架的雏形就有了。对于一些来不及写测试用例的功能模块，通过Robot也可以进行快速测试，这也是我们目前主要使用的测试手段。在这方面可以进一步探索的还有很多，比如将测试用例集成到测试状态机中，外部只定义期望的消息交互流程(如发送req1, 期望收到ack1, ack2,发送req2, 期望收到...)，再导入到状态机中进行执行，并判断整个流程是否符合预期。

### 3. 内部测试

前两者更像是黑盒测试，而内部测试更像白盒，针对API，模块进行测试，除此之外，内部测试还包括一些服务器自身的数据逻辑检查，这类检查关注服务器本身的数据和服务的正确性，尽早地暴露问题，及时进行数据修复和调试。比如我们的大地图就有一些数据一致性检查，比如实体状态，实体交互，资源刷新等等，这类检查在开发期间可以直接作为routine让进程定时跑，配合机器人测试，能查出大量问题。

测试的重要性怎么强调也不为过，对服务器开发来说，测试的优点有：

- 节省大量和客户端以及QA的调试和交互时间
- 确保重构/改动的正确性
- 进一步理解交互流程
- 预先暴露问题，并获得更加详尽的错误信息
- 多种测试并行，加速测试流程


[依赖倒置]: https://zh.wikipedia.org/wiki/%E4%BE%9D%E8%B5%96%E5%8F%8D%E8%BD%AC%E5%8E%9F%E5%88%99
[控制反转]: https://zh.wikipedia.org/wiki/%E6%8E%A7%E5%88%B6%E5%8F%8D%E8%BD%AC
[cluster_server]: http://wudaijun.com/2015/08/erlang-server-design1-cluster-server/
[battle_node]: http://wudaijun.com/2015/09/erlang-server-design2-erlang-lua-battle/
[ref 1]: http://dotnetfresh.cnblogs.com/archive/2005/06/27/181878.html
