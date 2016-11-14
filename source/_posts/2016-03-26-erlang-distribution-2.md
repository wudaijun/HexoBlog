---
title:  Erlang 分布式系统(2)
layout: post
tags:
- erlang
- distribution
categories: erlang

---
## 一. 分布式Erlang

Erlang为分布式提供的基础设施

1. 良好的函数式编程语义，为并发而生
2. 异步通信模型，屏蔽底层通讯细节(Erlang进程间/系统进程间/物理机间)，将本地代码扩展为分布式程序非常容易
3. 透明的通信协议，完善的序列化/反序列化支持
4. 完善的监控能力：监督(supervisor), 监视(monitor), 链接(link)等
5. 其它分布式组件：如global,epmd,mnesia等

<!--more-->

## 二. Erlang分布式基础

### 1. Erlang node

一个Erlang分布式系统由多个Erlang节点(node)组成，每一个节点即为一个Erlang虚拟机，这些节点可以彼此通信。不同节点节点上Pid之间通信(link,monitor等)，是完全透明的。

集群中每个Erlang节点都有自己的名字，通过`-sname`或`-name`设置节点名字，前者在局域网中使用，后者在广域网中使用，两种命名方式的节点不能相互通信。也可在节点启动后通过`net_kernel:start/1`来将一个独立节点转换为分布式节点。

Erlang节点之间通过TCP/IP建立连接并通信，集群中的节点是松散连接的(loosely connected)，只有当第一次用到其它节点名字时，才会和该节点建立连接(并且校验cookie)。但同时连接也是扩散(transitive)的，比如现有节点A,B相连，C,D相连，此时节点B连接节点C，那么A,B,C,D将两两相连形成一个全联通集群。要关闭Erlang节点的transitive行为，使用虚拟机启动选项`-connect_all false`。当节点挂掉后，其上所有的连接都会被关闭，也可通过`erlang:disconnect_node/1`关闭与指定节点的连接。

### 2. cookie

cookie是Erlang节点连接时的简单验证机制，只有具有相同cookie的节点才能连接。通过`-setcookie`选项或`erlang:set_cookie/2`设置cookie，后者可以为一个节点设置多个cookie，在连接不同的节点时使用不同的cookie，连接到多个集群中。如果没有指定，将使用`~/.erlang.cookie`中的字符串作为cookie。由于cookie是明文的，并且共享于所有节点，更像是一种分隔集群的方式，而不是一种安全机制。

### 3. hidden node

通过为节点启动参数`-hidden`，让一个节点成为hidden节点，hidden节点与其它节点的连接不会扩展，它们必须被显示建立。通过`nodes(hidden)`或`nodes(connected)`才能看到与本节点连接的hidden节点。

### 4. net_kernel

net\_kernel管理节点之间的连接，通过`-sname`或`-name`启动参数或在代码中调用`net_kernel:start/1`可以启动net_kernel进程。net_kernel默认会在引用到其它节点时(如rpc:call/5, spawn/4, link/1等)，自动与该节点建立连接，通过`-dist_auto_connect false`选项可以关闭这种行为，如此只能通过`net_kernel:connect_node/1`手动显式地建立连接。

### 5. epmd

epmd(Erlang Port Mapper Daemon)是Erlang节点所在主机上的守护进程，它维护本机上所有Erlang节点名到节点地址(Host:Port)的映射。

epmd会在主机上第一个Erlang分布式节点启动时自动后台启动，默认监听4369端口。当分布式节点启动时，VM会监听一个端口(可通过`inet_dist_listen_min`和`inet_dist_listen_max`限制端口范围)用于接收其它节点连接请求，之后节点会将节点名(@前半部分)和监听地址发给epmd进程，当节点和epmd进程断开TCP连接后，epmd会注销该节点地址信息。

当节点A(`node_a@myhost1`)尝试连接节点B(`node_b@myhost2`)时，节点A会先向myhost2上的empd进程(`myhost2:4369`)根据节点B名字(nodeb)查询节点监听地址，之后再连接这个监听地址和B节点通信。

默认配置下，epmd在物理机上的监听端口为4369，这意味着：

1. 因为是周知端口，所以通过查询目标机器上的4369，就可以知道这个机器上节点的情况。
2. 在同一机器可能会部署不同的Erlang集群，希望不要互相干扰。
3. 防火墙不允许过4369端口，或者不在开放端口之列表。

我们可以指定epmd监听端口：

	// 单独启动epmd进程
	empd -daemon -port 5000
	// epmd随分布式节点启动而自动启动时，也可指定epmd的启动方案
	erl -name hello -epmd "epmd -port 5001 -daemon" -epmd_port 5001
	
可以在虚拟机启动时，通过`-epmd_port`(或`ERL_EPMD_PORT`环境变量)指定要连接的epmd端口：

	// 通过启动选项
	erl -name hello -epmd_port 5000
	// 通过环境变量
	ERL_EPMD_PORT=5000 erl -name hello
	

需要注意的是，一旦节点采用定制的epmd port，那么节点在连接其它节点的时候，也将使用定制的epmd端口访问epmd。因此，**同一个集群的epmd端口必须是一致的**。

参考：

1. http://erlang.org/doc/man/epmd.html
2. http://www.cnblogs.com/me-sa/p/erlang-epmd.html
3. http://erlang.org/doc/apps/erts/erl\_dist\_protocol.html


### 6. global

global模块功能主要通过global\_name\_server进程完成，该进程在节点启动时启动。global模块主要包含如下功能：

#### 全局锁

global模块提供全局锁功能，可以在集群内对某个资源进行访问控制，当某个节点尝试lock某个资源时，global\_name\_server会muticall集群中所有节点上的global\_name\_server进程，只要其中一个节点上操作失败，本次lock也会失败，并引发下次重试或整个操作的失败。

global模块会在当前所有known(`nodes()`)节点中推选出一个Boss节点(简单通过`lists:max(Nodes)`选出)，在设置全局锁时，会先尝试在Boss节点上上锁，再对其它节点上锁，这样保证全局资源的唯一性，又不需要单独设置中心节点。

#### 全局名字管理

global\_name\_server另一个职责是管理集群全局名字信息，global\_name\_server将全局名字信息缓存在ets，因此对全局名字的解析是非常快的，甚至不走消息流程。但是对名字的注册，需要先上全局锁，再muticall所有的global\_name\_server，进行本地ets名字更新，整个过程至少要muticall集群所有节点两次，对于这类耗时的操作，global\_name\_server有一个小技巧：

{% codeblock lang:c %} 

% 外部进程（call调用）
gen_server:call(global_server, {something, Args})

% global_name_server（任务异步分发）
handle_call({something Args}, State) ->
	State#state.worker ! {someting, Args, self()}

% Worker进程（实际任务，通过gen_server:reply手动模拟call返回）
loop_the_worker() ->
    receive 
        {do_something, Args, From} ->
            gen_server:reply(From, do_something(Args));
	Other ->
            unexpected_message(Other)
    end,
    loop_the_worker().
   
{% endcodeblock %}

#### 维护全联通网络

global的最后一个职责就是维护全联通网络，在global模块的源码注释中可以看到其网络信息同步协议：

	%% Suppose nodes A and B connect, and C is connected to A.
	%% Here's the algorithm's flow:
	%%
	%% Node A
	%% ------
	%% << {nodeup, B}
	%%   TheLocker ! {nodeup, ..., Node, ...} (there is one locker per node)
	%% B ! {init_connect, ..., {..., TheLockerAtA, ...}}
	%% << {init_connect, TheLockerAtB}
	%%   [The lockers try to set the lock]
	%% << {lock_is_set, B, ...}
	%%   [Now, lock is set in both partitions]
	%% B ! {exchange, A, Names, ...}
	%% << {exchange, B, Names, ...}
	%%   [solve conflict]
	%% B ! {resolved, A, ResolvedA, KnownAtA, ...}
	%% << {resolved, B, ResolvedB, KnownAtB, ...}
	%% C ! {new_nodes, ResolvedAandB, [B]}
	%%
	%% Node C
	%% ------
	%% << {new_nodes, ResolvedOps, NewNodes}
	%%   [insert Ops]
	%% ping(NewNodes)
	%% << {nodeup, B}
	%% <ignore this one>

在上面的源码注释中，可以看到global模块的全联通维护机制，集群中被连接的节点(Node A)，会将新加入的节点(Node B)介绍给集群中的其它节点(Node C)。同名字注册一样，global\_name\_server将全联通集群管理放在另一个Worker中执行。

global模块的名字注册只能在全联通网络下进行，这样才能在任意节点进行信息更新。在非全联通集群中(`-connect_all false`)，全局锁机制仍然是可用的。

注意到整个同步协议中，nodeup和nodedown消息是由net_kernel进程发布的。

global模块更加具体的实现细节没有细究，待后续详细理解。能够在不可靠的网络上实现一套全局锁和全联通管理方案，本身就是非常复杂的，因此还是值得一读。

### 7. mnesia

参见：http://wudaijun.com/2015/04/erlang-mnesia/

