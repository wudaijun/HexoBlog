---
title: GS 测试规范实践
layout: post
categories: gameserver
tags: gameserver
---

在之前的博客中几次简单提及过给GS做测试，关于测试的必要性不用再多说，但在实际实践过程中，却往往会因为如下原因导致想要推进测试规范困难重重:

-. Q1: 写测试代码困难: 代码耦合重，各种相互依赖，全局依赖，导致写测试代码"牵一发而动全身"，举步维艰
-. Q2: 测试时效性低: 需求变更快，数值变更频繁，可能导致今天写好的测试代码，明天就"过时"了
-. Q3: 开发进度紧: 不想浪费过多时间来写测试代码，直接开发感觉开发效率更高

要想推进测试规范，上面的三个问题是必须解决的。这里简单聊聊我们在Golang游戏后端中的测试实践和解决方案。我们在GS中尝试的测试方案主要分为四种: 单元测试，集成测试，压力测试，以及模拟测试。

<!--more-->

### 单元测试

单元测的优点是与业务逻辑和外部环境关联度最小，同时go test也很容易集成到CI/CD流程中。单元测试的缺点就是上面提到的Q1(耦合依赖问题)，对此，我们的解决方案是:

1. 持续重构，解耦降低依赖。有点废话，但是写易于测试的代码确实是一种修行
2. 通过[goconvey](https://github.com/smartystreets/goconvey)测试框架简化单元测试的编写
3. 通过[gomock](https://github.com/golang/mock) Mock掉接口依赖
4. 实在Mock不掉的，通过[gomonkey](https://github.com/agiledragon/gomonkey) Hack掉依赖，不过要记得禁用内联
5. 对于一些复杂的单元测试，如涉及到发消息，创建玩家，启动定时器等，可以创建通用的Mock组件和环境，便于使用

goconvey+gomonkey+gomock 三件套在实践中足够灵活强大，具体使用参考文档即可，比较简单，就不展示了。

### 集成测试

集成测试我们又称之为用例测试，它是一种黑盒测试，以C/S交互协议为边界，站在客户端视角来测试服务器运行结果，黑盒测试本质上是消息流测试。它的优点是覆盖面广，网络层，集群管理，消息路由等细节都被会覆盖到。黑盒测试的难点在于易变性，协议变更，配置更新等都可能造成测试用例不可用，即上面提到的Q2(用例时效性问题)。对此，我们的实践是:

1. 将消息流测试离线化，即封装基本原语(Send,Wait,Expect,Select等)，化编译型为解释型，让测试用例可以通过类似配置文件的方式来描述，简化与服务器的交互细节，甚至理论做到交付给非技术人员使用。技术上除了对模拟客户端的封装外，主要是对json的处理: [gojsonq](https://github.com/thedevsaddam/gojsonq), [jsondiff](https://github.com/nsf/jsondiff), [jsonx](https://github.com/mkideal/pkg/tree/master/encoding/jsonx)
2. 写可重入的测试用例，可重入即用例不应该依赖于当前服务器和用例机器人的初始状态，做到可重复执行
3. 保存一份专用于用例测试策划配置快照，避免频繁的数值调整导致测试用例不可用。服务器和测试客户端都使用这份配置。即GS需要支持不同的配置源(如DB/File)

以下是一个省掉很多细节的测试用例(yml格式描述):

```
# 封装一个Function，从预定义变量varRole[n]中提取字段放到自定义变量中
InitAttackCmds:
  - find LoginAck.city.coord.X from varRole1 to varCity1X
  - find LoginAck.city.coord.Z from varRole1 to varCity1Z
  - find LoginAck.city.cityID from varRole1 to varCity1ID

# 单个测试用例
AttackPersonCityWinTest:
  # 创建两个Robot，以Rbt1 Rbt2 标识
  - newrobot 2
  # 此时机器人已经登录完成，初始化自定义变量
  - call InitAttackCmds
  # 获取Rbt1初始化城防值
  - Rbt1 send CityDefenseReq {}
  # wait 后面的消息支持json局部字段比较(包含匹配)
  - Rbt1 wait CityDefenseAck {isCombustion:false}
  - Rbt1 find cityDefense from varLastAck to varCityDefensePreVal
  # Rbt2 向 Rbt1 城池行军
  - Rbt2 send NewTroopReq {"Action":1,"Soldiers":{"11211001":500,"11211301":500},"EndCoord":{"X":%v,"Z":%v},"Mission":{"IsCampAfterHunt":false,"IsRally":false},"TargetID":%v} varCity1X varCity1Z varCity1ID
  - Rbt2 wait NewTroopAck {errCode:0,action:1}
  # 防守失败后被烧城
  - Rbt1 wait CombustionStateNtf {isCombustion:true}
  - Rbt1 find cityDefense from varLastAck to varCityDefensePostVal
  # 掉城防值
  - should varCityDefensePostVal < varCityDefensePreVal
```

### 压力测试

压力测试也是黑盒测试的一种，它的目标是放大服务器的性能问题以及并发状态下的正确性问题。我在[如何给GS做压测](https://wudaijun.com/2019/09/gs-pressure-test/)中简单地阐述过压测的一些注意事项。简单来说，用例测试注重特例和自动化，而压力测试注重随机和覆盖率。

### 模拟测试

模拟测试是指通过类似console的方式来模拟客户端，它的功能主要分为两部分:

1. 动态构造消息并返回响应数据
2. 支持一些简单的GM，如查看/修改自身数据

它最大的优点在于灵活性，主要有两个作用:

1. 服务器新功能开发完成进行快速自测验证(脱离客户端)，提升开发效率
2. 出现某些疑似服务器的BUG时，登录已有角色进行数据验证和Debug

以下是我们的模拟测试的样子:

```
// 注: FC[...]# 为输入行，其余为输出行    "//..."表示省略消息具体内容
FakeClient connect successed
FC[NotAuth]# auth test
send msg: AuthReq:type:"anonymous" passport:"user_fakeclienttest" password:"user_fakeclienttest"
recv msg: AuthAck //... 
FC[Authed:281474976712031]#
FC[Authed:281474976712031]# char login 11
send msg: LoginReq: // ...
recv msg: LoginAck playerID:27113 // ...
FC[Logined:27113]#
FC[Logined:27113]#send HeartBeatReq {ClientTs:111}
send msg: HeartBeatReq:clientTs:111 
recv msg: HeartBeatAck clientTs:111 serverTs:1597664509306
FC[Logined:27113]#
FC[Logined:27113]# self all
{"ID":27113,"name":"Newbie 27113", // ...
```

### 最后

集成测试，压力测试，模拟测试，核心都需要一个模拟客户端，因此完全可以构建一套通用的fakeclient逻辑，包含基础网络通信，登录流程，数据状态同步等等。比如我们还基于fakeclient搭建了用于监控线上服务器可用性的监控机器人。

前面分别提到Q1，Q2的解决方案，至于Q3，我们的经验是，同学们之所以不愿意写测试，大部分原因都是测试框架还不够完善易用。另外，应该达成共识的是，开发效率并不只算单方面当前的开发时间，还应该包括客户端联调，QA验证反馈，后续重构负担等的时间，从这个角度来说，良好的测试规范起到的作用毋容置疑。




