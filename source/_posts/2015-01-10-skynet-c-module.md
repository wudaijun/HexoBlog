---
layout: post
title: skynet C模块
categories:
- gameserver
tags:
- lua
- skynet
---

这些天一直在拜读云风的[skynet][1]，由于对lua不是很熟悉，也花了一些时间来学习lua。这里大概整理一下这些天学习skynet框架的一些东西。

skynet核心概念为服务，一个服务可以由C或lua实现，服务之间的通信已由底层C框架保证。用户要做的只是注册服务，处理消息。如云风的[skynet综述][2]中所说：

**作为核心功能，Skynet 仅解决一个问题：**

**把一个符合规范的 C 模块，从动态库（so 文件）中启动起来，绑定一个永不重复（即使模块退出）的数字 id 做为其 handle 。模块被称为服务（Service），服务间可以自由发送消息。每个模块可以向 Skynet 框架注册一个 callback 函数，用来接收发给它的消息。每个服务都是被一个个消息包驱动，当没有包到来的时候，它们就会处于挂起状态，对 CPU 资源零消耗。如果需要自主逻辑，则可以利用 Skynet 系统提供的 timeout 消息，定期触发。**

**Skynet 提供了名字服务，还可以给特定的服务起一个易读的名字，而不是用 id 来指代它。id 和运行时态相关，无法保证每次启动服务，都有一致的 id ，但名字可以。**

<!--more-->

在云风的[这篇博客][3]中更详细地介绍道：

**这个系统是单进程多线程模型。**

**每个内部服务的实现，放在独立的动态库中。由动态库导出的三个接口 create init release 来创建出服务的实例。init 可以传递字符串参数来初始化实例。比如用 lua 实现的服务（这里叫 snlua ），可以在初始化时传递启动代码的 lua 文件名。**

**每个服务都是严格的被动的消息驱动的，以一个统一的 callback 函数的形式交给框架。框架从消息队列里取到消息，调度出接收的服务模块，找到 callback 函数入口，调用它。服务本身在没有被调度时，是不占用任何 CPU 的。框架做两个必要的保证。**

**一、一个服务的 callback 函数永远不会被并发。**

**二、一个服务向两一个服务发送的消息的次序是严格保证的。**

**我用多线程模型来实现它。底层有一个线程消息队列，消息由三部分构成：源地址、目的地址、以及数据块。框架启动固定的多条线程，每条工作线程不断的从消息队列取到消息。根据目的地址获得服务对象。当服务正在工作（被锁住）就把消息放到服务自己的私有队列中。否则调用服务的 callback 函数。当 callback 函数运行完后，检查私有队列，并处理完再解锁。**

### 符合规范的C模块

skynet C服务均被编译为动态链接库so文件，由框架在需要时加载并使用。前面说的"符合规范的C模块"指的是一个能被框架正确加载使用的C服务模块应该导出如下三个接口：

```
// 服务创建接口 返回服务实例数据结构
struct xyz* xyz_create(void);

// 初始化服务 主要是根据param启动参数初始化服务 并注册回调函数
int xyz_init(struct xyz * inst, struct skynet_context *ctx, const char * param)；

// 释放服务
void xyz_release(struct xyz* inst);
```

其中"xyz"是C服务名，需要和最终编译的动态库名一致，skynet根据这个名字来查找"xyz.so"并加载。服务模块还需要导出 xyz_create xyz_init xyz_release三个函数用于服务的创建，初始化和释放。xyz_create返回服务自定义的数据结构，代表一个服务实例的具体数据。xyz_init中根据启动参数完成服务的初始化，并且注册回调函数：

```
typedef int (*skynet_cb)(
 		struct skynet_context * context,
 		void * ud,
 		int type,
 		int session, 
 		uint32_t source ,
 		const void * msg,
 		size_t sz
);
// 注册消息回调函数cb和回调数据ud
skynet_callback(struct skynet_context * context, void *ud, skynet_cb cb);
```
	
通过skynet_callback可以注册回调函数和回调自定义数据ud(一般就是模块create函数的返回值)，之后每次调用回调函数都会传入ud。

在skynet/service-src/下，定义了四个C服务，其中最简单的是skynet_logger.c，它是C写的一个logger服务。关于C服务的写法一看便知。

### C服务上下文skynet_context

skynet_context保存一个C服务相关的上下文。包括服务的消息队列，回调函数cb，回调数据ud，所在模块，以及服务的一些状态等。skynet核心层管理的每个C服务都需要对应一个skynet_context。skynet建立服务的唯一id(handle)到skynet_context的一一对应。

在向服务发送消息时，指定其handle即可。skynet根据该handle找到skynet_context，并将消息push到skynet_context的msgqueue中。skynet还为服务提供了全局名字注册，这样可以通过指定服务名向服务发送消息，skynet会根据name找到handle，最终仍通过handle来找到服务的消息队列。

msgqueue中也保存了其所属服务handle。这样消息调度器在处理到某个msgqueue时，可通过msgqueue中的handle找到skynet_context，并调用其回调函数。



[1]: https://github.com/cloudwu/skynet "skynet on github"
[2]: http://blog.codingnow.com/2012/09/the_design_of_skynet.html "skynet综述"
[3]: http://blog.codingnow.com/2012/08/skynet.html "skynet开源"
