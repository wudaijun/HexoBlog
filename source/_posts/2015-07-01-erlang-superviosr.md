---
title: Erlang supervisor
layout: post
tags: erlang
categories: erlang
---

### 一. 简介

Supervisor(监督者)用于监督一个或多个Erlang OTP子进程，Supervisor本身是个behaviour，仅有一个Callback: `init/1`，该函数返回{ok, {ChildSpecList, RestartStrategy}}。ChildSpecs是ChildSpec列表，

<!--more-->

**ChildSpec(子进程规范)**：

指定要监控的子进程的所在模块，启动函数，启动参数，进程类型等等。格式为:

```
child_spec() = {id => child_id(),	   	  % 一般为Child所在Module名
               start => mfargs(),     	% {Module, StartFunc, Arg}
               restart => restart(),  	% permanent:任何原因导致进程终止都重启 | transiend:意外终止时重启 | temporary:永不重启 
               shutdown => shutdown(),	% 终止子进程时给子进程预留的时间(毫秒) | brutal_kill 立即终止 | infinity 无限等待 用于Child也是supervisor的情况
               type => worker(),      	% 子进程类型 worker:工作者 | supervisor:监督者
               modules => modules()}  	% 子进程所依赖的模块，用于定义热更新时的模块升级顺序，一般只列出子进程所在模块
```
**RestartStrategy(重启策略)**:

定义子进程的重启方式，为三元组{How, Max, Within}:


	How: 	one_for_one: 		 仅对终止的子进程进行重启，不会影响到其他进程
			one_for_all: 		 一旦有某个子进程退出，讲终止该监督者下其它所有子进程，并进行全部重启
			rest_for_one: 		 按照ChildSpecList子进程规范列表中的定义顺序，所在在终止子进程之后的子进程将被终止，并按照顺序重启
			simple_one_for_one:   这是一种特殊的监督者，它管理多个同种类型的子进程，并且所有子进程都通过start_child接口动态添加并启动，在监督者启动时，不会启动任何子进程。
			
	Max:	在Within时间片内，最多重启的次数
	
	Within:  时间片，以秒为单位	
			

### 二. 重启机制

子进程终止时，监督者会重启子进程，那么此时我们关心的是我们的State数据(假设我们的子进程是gen_server)，对于simple_one_for_one类型的监督者，经测试，监督者在重启Child的时候，会传入start_child时的初始化参数(该参数分为两部分，一部分是子进程规范中Arg指定的默认参数，以及`supervisor:start_child`传入的参数，将这两部分合并即为StartFunc最终收到的参数)。也就是说子进程终止时，我们的State数据丢失了。

考虑Player进程，它使用simple_one_for_one类型的监督者Player_sup，假设启动参数为PlayerId，在Player进程处理逻辑挂掉时，我们在terminate中将PlayerData落地，并做一些其它处理，如通知Agent。Player_sup在重启该Player进程时，会传入其上次传入的参数，即PlayerId，因此我们可以在init中重新加载玩家数据并通知Agent(Player进程重启后Pid会变化)。
