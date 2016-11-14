---
title: 探索Docker在Erlang集群中的应用
layout: post
categories: tool
tags: docker

---

接[上篇](http://0.0.0.0:4444/2016/11/docker-basic/)，结合Erlang，对Docker的实际应用进一步理解。并探索将Docker应用到Erlang集群的方案。

## 简单Docker交互

下面是个简单的echo server：

	-module(server_echo).
	-export([start/0]).
	  
	start() ->
	     io:format("SERVER Trying to bind to port 2345\n"),
	     {ok, Listen} = gen_tcp:listen(2345, [ binary
	                                         , {packet, 0}
	                                         , {reuseaddr, true}
	                                         , {active, true}
	                                         ]),
	     io:format("SERVER Listening on port 2345\n"),
	     accept(Listen).
	 	
	 accept(Listen) ->
	     {ok, Socket} = gen_tcp:accept(Listen),
	     WorkerPid = spawn(fun() -> echo(Socket) end),
	     gen_tcp:controlling_process(Socket, WorkerPid),
	     accept(Listen).
	 	
	 echo(Socket) ->
	     receive
	         {tcp, Socket, Bin} ->
	             io:format("SERVER Received: ~p\n", [Bin]),
	             gen_tcp:send(Socket, Bin),
	             echo(Socket);
	         {tcp_closed, Socket} ->
	             io:format("SERVER: The client closed the connection\n")
	     end.

简单起见，我们直接用`telnet`命令对echo server进行测试。现在，考虑如何在Docker容器中运行echo server。

<!--more-->

### 容器中运行

	sudo docker run -it --rm -v ~/docker:/code -w /code erlang erl
	Erlang/OTP 19 [erts-8.1] [source] [64-bit] [smp:4:4] [async-threads:10] [hipe] [kernel-poll:false]
	
	Eshell V8.1  (abort with ^G)
	1> c(server_echo).
	{ok,server_echo}
	2> server_echo:start().
	SERVER Trying to bind to port 2345
	SERVER Listening on port 2345
	
在`docker run`中，我们将本地代码路径挂载到容器的/code目录，并且将/code作为容器的工作目录，此后对本地代码的修改，将直接反映在容器中，而无需拷贝。运行容器后会进入erl shell，并且当前路径(/code)即为本地代码路径(~/docker)，之后编译运行server即可。


### 宿主机访问容器

如下方案可以让宿主机能访问容器端口：

- 在`docker run`中指定`-p 2345:2345`导出2345端口，之后访问宿主机的2345端口等同于访问容器2345端口
- 在`docker run`中指定`--network host`使容器和宿主机共享网络栈，IP和端口
- 通过`docker inspect`查询容器IP地址(如:`172.17.0.2`)，可在宿主机上通过该IP访问容器


### 容器之间访问

容器间交互方式主要有三种：

- 通过`docker inspect`得到容器IP地址，通过IP地址进行容器间的交互
- 通过`docker run`中指定`--network container:<name or id>`，将新创建的容器与一个已经存在的容器的共享网络栈，IP和端口
- 通过`docker run`的`--link <name or id>`选项链接两个容器，之后可以将容器名或容器ID作为Hostname来访问容器，注意`--link`选项仅在`--network bridge`下有效

### 定义Dockerfile

前面我是通过挂载目录的方式将本地代码映射到容器中，这种方式在本地开发中比较方便，但是在项目部署或环境配置比较复杂时，我们需要通过Dockerfile来构建自己的镜像(而不是基于官方Erlang镜像)，初始化项目环境，就本例而言，Dockerfile非常简单：


	FROM erlang
	  
	RUN mkdir code
	  
	COPY server_echo.erl code/server_echo.erl
	  
	RUN cd code && erlc server_echo.erl
	
	WORKDIR /code
	 
	ENTRYPOINT ["erl", "-noshell", "-run", "server_echo", "start"]


## Erlang多节点通信

### 再谈Erlang分布式通信

Erlang的分布式节点有自己的通信机制，这套通信机制对上层用户是透明的，我们只需一个节点名(`node@host`)，即可访问这个节点，而无需关心这个节点是在本机上还是在其它主机上。在这之上封装的Pid，进一步地屏蔽了节点内进程和跨节点进程的差异。

在[Erlang分布式系统(2)]中，我提到了Erlang的分布式设施，其中epmd扮演着重要的角色：它维护了本机上所有节点的节点名到节点监听地址的映射，并且由于epmd进程本身的监听端口在集群内是周知的(默认为4369)，因此可以根据节点名`node@host`得到节点所在主机上epmd的监听地址(`host:4369`)，进而从epmd进程上查询到节点名`node`所监听的地址，实现节点间通信。

### 在同主机不同容器中部署集群

现在回到Docker，我们先尝试在同一个主机，不同容器上建立集群：

	# 容器A 启动后通过docker inspect查询得到IP地址: 172.17.0.2
	sudo docker run -it erlang /bin/bash
	root@4453d880b5a5:/# erl -name n1@172.17.0.2 -setcookie 123
	Eshell V8.1  (abort with ^G)
	(n1@172.17.0.2)1> 
	
	# 容器B 启动后通过docker inspect查询得到IP地址: 172.17.0.4
	sudo docker run -it erlang /bin/bash
	root@dd0f30178036:/# erl -name n2@172.17.0.4 -setcookie 123
	Eshell V8.1  (abort with ^G)
	(n2@172.17.0.4)1> net_kernel:connect_node('n1@172.17.0.2').
	true
	(n2@172.17.0.4)2> nodes().
	['n1@172.17.0.2']

和在宿主机上一样，我们可以直接通过容器IP架设集群。这里使用的是`-name node@host`指定的longname，而如果使用shortname：

	# 容器A
	root@4453d880b5a5:/# erl -sname n1 -setcookie 123
	Eshell V8.1  (abort with ^G)
	(n1@4453d880b5a5)1>
	
	# 容器B
	root@dd0f30178036:/# erl -sname n2 -setcookie 123
	Eshell V8.1  (abort with ^G)
	(n2@dd0f30178036)1> net_kernel:connect_node('n1@4453d880b5a5').
	false

在shortname方案中，我们并不能通过nodename访问节点，本质上是因为`n2`节点不能通过`4453d880b5a5:4369`访问到`n1`节点所在主机上的epmd进程。我们测试一下网络环境：

	# 通过容器A名字ping
	ping 4453d880b5a5
	ping: unknown host
	
	# 直接ping容器A IP
	ping 172.17.0.2
	PING 172.17.0.2 (172.17.0.2): 56 data bytes
	64 bytes from 172.17.0.2: icmp_seq=0 ttl=64 time=0.099 ms
	64 bytes from 172.17.0.2: icmp_seq=1 ttl=64 time=0.089 ms

发现是hostname解析出了问题，容器链接来解决这个问题：

	# 重新启动容器B 并链接到容器A
	docker run -it --link 4453d880b5a5 erlang /bin/bash
	root@7692c8c71218:/# erl -sname n2 -setcookie 123
	Eshell V8.1  (abort with ^G)
	(n2@dd0f30178036)1> net_kernel:connect_node('n1@4453d880b5a5').
	true

有个有趣的问题是，当容器B link了容器A，那么容器B能通过容器A的Id或名字访问容器B，而反过来，容器A却不能以同样的方式访问容器B。也就是说link是单向的，这同样可以通过ping来验证。

### 在不同的主机上部署集群

在不同的主机上部署集群，问题开始变得复杂：

1. 不同的主机上的Docker容器处于不同的子网(一台主机对应一个子网)，因此不同主机上的容器不能直接访问，需要先发布(publish)Erlang节点监听端口
2. Erlang节点在Docker容器中的监听地址是由Erlang VM启动时分配的，因此我们无法在启动容器时就获知Erlang节点监听端口(从而发布该端口)
3. 假定我们预配置了Erlang节点的监听端口xxx，如果我们使用`-p xxx:xxx`将可能导致端口争用(亦即一台物理机只能运行一个Docker容器)，如果我们使用`-p xxx`将该端口发布到主机任意一个端口，那么这个发布的主机端口，将只能通过Docker Daemon获取到(命令行下可通过`docker port`查看)
4. 再来看epmd，每个Docker容器中都会跑一个epmd进程，它记录的是节点名到**节点在容器中的监听地址**，因此，epmd本身返回的地址是不能直接被其它主机上的节点使用的

#### Erlang In Docker

基于上面的种种限制，有人给出了一套解决方案：[Erlang In Docker][]。这套方案对Erlang集群做了如下制约：

1. 每个Docker容器只能运行一个Erlang节点
2. 预配置Erlang节点的监听端口
3.	Erlang节点名格式为`DockerContainerID@HostIP`
4. 使用Docker Daemon而不是epmd来获取节点监听端口

这套方案的核心思路是用Docker Daemon替换epmd做节点监听的服务发现，原因有二：

- Docker Daemon运行于主机同级网络中
- 维护了容器端口和主机端口的映射关系

如果节点A想要访问节点B，则节点A需要提供：

- 节点B所在主机地址: Host
- 节点B所在主机上Docker Daemon的监听端口: DaemonPort
- 节点B所在容器ID: ContainerID
- 节点B在所在容器中的监听端口: Port0

之后就可以通过Docker Daemon(`Host:DaemonPort`)查询到`ContainerID`容器的`Port0`端口在主机上对应的发布端口`Port1`，之后节点A即可通过`Host:Port1`与节点B通信。

然而节点A只有节点B的名字，要在节点B中编码这四条信息是非常困难的，因此Erlang In Docker的做法是，预配置Port0(12345)和DaemonPort(4243)，剩下的主机地址和容器ID则编码在节点名中：`DockerContainerID@HostIP`。

EID代码并不复杂，得益于Erlang可替换的分布式通信协议，EID只自定义了`eid_tcp_dist`(替换默认的`inet_tcp_dist`模块)和dpmd(通过与Docker Daemon交互模拟epmd的功能)两个模块。

#### 总结

将Erlang应用到Docker上比较困难的主要原因是Erlang已经提供了非常完备的分布式设施(参见[Erlang分布式系统(2)][])，并且这一套对上层都是透明的。EID这套方案看起来限制很多，但细想也没多大问题，具体还要看在生产环境中的表现，目前我比较顾虑它的通信效率(NAT)和`eid_tcp_dist`是否足够健壮。

[Erlang分布式系统(2)]: http://wudaijun.com/2016/03/erlang-distribution-2/
[Erlang In Docker]: https://github.com/Random-Liu/Erlang-In-Docker