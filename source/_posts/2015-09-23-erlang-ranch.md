---
title: ranch
layout: post
tags: erlang
categories: erlang

---

### 一. 简介

[ranch](https://github.com/ninenines/ranch)是erlang的一个开源网络库，提供一个高效的监听进程池，并且将数据传输和数据处理分离开来。使用起来非常简单，灵活。关于ranch的更多介绍和使用，参见[官方文档](https://github.com/ninenines/ranch/tree/master/doc/src)。
<!--more-->

### 二. 功能

ranch将网络连接分为传输层(transport)和协议层(protocol)，传输层是底层数据的传输方式，如tcp, udp, ssl等。协议层负责数据在业务逻辑上的处理，是开发者真正需要关心的部分。而ranch的一个目标就是将传输层和逻辑层很好的分离开来。

对服务器端来说，传输层需要负责管理监听套接字和连接套接字。ranch提供一个可设置的进程池，用于高效地接受新连接，将新连接套接字交予用户定义的连接进程，进行业务逻辑上的处理。

ranch做了什么：

- 允许多个应用同时使用，即可有多个listener，每个listener通过名字标识
- 每个listenr可单独设置acceptor进程池的大小和其它选项
- 可设置最大连接数，并且可动态改变其大小
- 到达最大连接数时，后续连接(已经accept的连接)进程将被阻塞，待负载降下来或最大连接数变大后被唤醒
- 提供安全的网络退出方式

### 三. 使用

	ok = application:start(ranch).
	
	{ok, _} = ranch:start_listener(tcp_echo, 100, % 监听器名字和监听进程池大小
		ranch_tcp, [{port, 5555}],		% 定义底层transport handler及其选项 ranch_tcp由ranch提供，底层使用gen_tcp
		echo_protocol, []				% 自定义的protocol handler进程所在模块，及其选项
	).

之后我们需要做的，就是定义echo_protocol，ranch会在每个新连接到达时，调用`echo_protocol:start_link/4`，生成我们的协议处理进程。参见[官网示例](https://github.com/ninenines/ranch/blob/master/examples/tcp_echo/src/echo_protocol.erl)。使用起来非常简单。

### 四. 结构

ranch的进程结构如下：

![](/assets/image/201509/erlang_ranch.png "ranch进程结构")

#### ranch_server: 
维护全局配置信息，整个ranch_app唯一，由多个listener共享。通过ets维护一些配置信息和核心进程的Pid信息，格式`\{\{Opt, Ref\}, OptValue\}`，Ref是listener名字。

#### ranch_listener_sup:
由`ranch:start_listener/6`启动，其子进程有ranch_conns_sup和ranch_acceptors_sup，以`rest_for_one`策略启动，亦即一旦ranch_conns_sup挂了，ranch_acceptors_sup也将被终止，然后再依次重启。

#### ranch_acceptors_sup:
由它创建监听套接字，并启动N个ranch_accepter执行accept操作(`gen_tcp:accept`本身支持多process执行)。

#### ranch_acceptor:
执行loop，不断执行accept操作，将新conn socket的所属权交给ranch_conns_sup(`gen_tcp:controlling_process`)，通知其启动新protocol handle进行处理，并阻塞等待ranch_conns_sup返回。

#### ranch_conns_sup:
维护当前所有连接，当新连接到达时，调用`your_protocol:start_link/4`创建新进程，之后将conn socket所属权交给新连接进程。当连接到达上限时，阻塞前来通知开启新连接的Acceptor进程。直到阀值提高，或有其它连接断开，再唤醒这些Acceptor。ranch的实际最大连接数 = max_conns + NAcceptor。

#### your_protocol
开发者定义protocol，当有新连接到达时，将调用`your_protocol:start_link/4`启动新进程，之后的处理交予开发者。


### 五. 其它
 
- 对于不需要接收其它进程消息的进程，应该定义通过receive清理进程信箱，避免意料之外的消息一直堆积在信箱中。见[ranch_accepter.erl](https://github.com/ninenines/ranch/blob/master/src/ranch_acceptor.erl)。
- rest_for_one，实现更加强大灵活的监督者。
- ranch将网络的退出方式(brutal_kill，Timeout，infinity等)，交给开发者定制，而不放在框架中。
- 注意套接字所属权的转移：`ranch_acceptor` -> `ranch_conns_sup` -> `your_protocol`。

#### proc_lib

ranch中多处用到了proc\_lib启动进程，proc\_lib是OTP进程的基石，所有OTP behaviour进程都通过proc\_lib来创建新进程。

proc_lib的使用方法：

1. `proc_lib:start_link(M, F, A)`启动一个符合OTP规范的进程
2. 在`M:F(A)`中，通过`proc_lib:init_ack(Parent, Ret)`来告诉父进程自身已经初始化完成，此时`proc_lib:start_link/3`方才返回
3. 如果进程本身为OTP进程，此时可通过`gen_server:enter_loop(Module, Opts, State)`来进入OTP进程的主循环

proc_lib使用情形：

1. 为了让非OTP进程，能够以OTP规范启动，这样才能融入监督树中并被正确重启。如`gen_server:start_link`最终也通过`proc_lib:start_link`来启动进程。见[ranch_conns_sup.erl](https://github.com/ninenines/ranch/blob/master/src/ranch_conns_sup.erl)。
2. 让OTP进程在`init()`中进行消息处理，本来在init未返回之前，进程还未初始化完成，这个时候进程处理消息，会陷入死锁，但通过`proc_lib:init_ack/2`可以先让本进程伪初始化完成，然后进行消息处理，最后通过`gen_server:enter_loop`进入gen_server主循环。








