---
title: docker 网络
layout: post
categories: tool
tags: docker
---

以Docker为平台部署服务器时，最应该理解透彻的便是网络配置。离上次学习，Docker网络又更新了不少内容，重新温习一下。

通过`docker run`的`--network`选项可配置容器的网络，Docker提供了多种网络工作模式，none, host, bridge, overlay 等。

### none 

不为Docker容器进行任何网络配置，容器将不能访问任何外部的路由(容器内部仍然有loopback接口)，需要手动为其配置网卡，指定IP等，否则与外部只能通过文件IO和标准输入输出交互，或通过`docker attach 容器ID`进入容器。

### host 

与宿主机共用网络栈，IP和端口，容器本身看起来就像是个普通的进程，它暴露的端口可直接通过宿主机访问。相比于bridge模式，host模式有显著的性能优势(因为走的是宿主机的网络栈，而不是docker deamon为容器虚拟的网络栈)。

### bridge 

默认网络模式，此模式下，容器有自己的独立的Network Namespace。简单来说，Docker在宿主机上虚拟了一个子网络，宿主机上所有容器均在这个子网络中获取IP，这个子网通过网桥挂在宿主机网络上。Docker通过NAT技术确保容器可与宿主机外部网络交互。

<!--more-->

![](/assets/image/201711/docker-bridge.png "")

Docker服务默认会创建一个docker0网桥，并为网桥指定IP和子网掩码(通常为172.17.0.1/16)。当启动bridge模式的容器时，Docker Daemon利用veth pair技术，在宿主机上创建两个虚拟网络接口设备。veth pair技术保证无论哪一个veth收到报文，都将转发给另一方。veth pair的一端默认挂在docker0网桥上，另一端添加到容器的namespace下，并重命名为eth0，保证容器独享eth0，做到网络隔离。连接在同一个Docker网桥上的容器可以通过IP相互访问。如此实现了宿主机到容器，容器与容器之间的联通性。

关于网桥:

- 网桥(Bridges):
	工作在数据链路层，连接多个端口，负责转发数据帧。网桥知道它的各个端口的数据链路协议(目前几乎都是以太网)，将来自一个端口的数据帧转发到其它所有端口。有多个端口的网桥又叫做交换机，目前这两个概念没有本质区别。
	
	网桥可以用来连接不同的局域网(LAN)，按照最简单的方法，网桥会将某个端口收到的数据无脑转发给其它所有端口，这种泛洪(Flooding)算法效率过低，网桥依靠转发表来转发数据帧，通过自学习算法，记录各个Mac地址在对应哪个端口(转发表数据库)，辅之超时遗忘(Aging)和无环拓扑算法(Loop-Free Topology，典型地如Spanning Tree Protocol, STP)。
	
- Linux网桥:
	
	Linux下网桥是一个虚拟设备，你可以通过命令创建它，并且为其挂载设备(物理或虚拟网卡)。可通过`brctl`命令来创建和Linux网桥。管理Linux bridge的具体用法参考: https://wiki.linuxfoundation.org/networking/bridge。
	
- Docker网桥:
	
	Docker网桥通过Linux网桥实现，加上NAT, veth pair, 网络命名空间等技术，实现网络隔离和容器互联。可通过`sudo docker network inspect bridge`查看Docker网桥配置以及状态。

当容器需要和宿主机外部网络交互时，会在宿主机上分配一个可用端口，通过这个端口做SNAT转换(将容器IP:Port换为宿主机IP:Port)，再向外部网络发出请求。当外部响应到达时，Docker再根据这一层端口映射关系，将响应路由给容器IP:Port。

外部网络要访问容器Port0，需要先将Port0与宿主机Port1绑定(外部网络无法直接访问宿主机二级网络)，将宿主机IP:Port1暴露给外部网络，外部网络请求到达宿主机时，会进行DNAT转换(将宿主机IP:Port1换为容器IP:Port0)。

从实现上来讲，Docker的这种NAT(实际上是NATP，包含IP,Port的转换)规则，是Docker Daemon通过修改ipatables规则来实现的，ubuntu下可通过`sudo ipatbles -t nat -L`来查看和NAT相关的规则。

总之，Docker容器在bridge模式下不具有一个公有IP，即和宿主机的eth0不处于同一个网段。导致的结果是宿主机以外的世界不能直接和容器进行通信。虽然NAT模式经过中间处理实现了这一点，但是NAT模式仍然存在问题与不便，如：容器均需要在宿主机上竞争端口，容器内部服务的访问者需要使用服务发现获知服务的外部端口等。另外NAT模式会一定程度的影响网络传输效率。

默认设置下，Docker允许容器之间的互联，可通过`--icc=false`关闭容器互联(通过iptables DROP实现)，此时容器间相互访问只能通过`--link`选项链接容器来实现容器访问。`—link` 选项实际在链接容器的/etc/hosts中添加了一行被链接容器名和其IP的映射，并且会在被链接容器重启后更新该行(这样即使IP有变动也可以通过容器名正确连接)，此外还会添加一条针对两个容器允许连接的iptables规则。但Docker官方文档说`--link`已经是遗留的选项，更推荐通过已有或自定义网络模式实现互连。

### overlay

前面提到的网络模式，主要解决同一个主机上容器与容器，容器与主机，容器与外界的连接方案。overlay网络可以实现跨主机的容器VLAN，主要用于 docker swarm 上，docker 文档中也基本是两者同时出现，因此docker swarm是跨主机的容器与容器之间的官方标准通信方案。[这里](wudaijun.com/2018/03/08/docker-swarm/)有关于 docker swarm 的更多介绍。当初始化 swarm 时，会生成如下东西:

- docker_gwbridge: 用于实现 host 上的 container 互联，类似 docker0，以及对swarm container暴露端口的SNAT, DNAT转换
- ingress: 用于实现跨主机的 swarm 网络，相同集群的不同节点上的 swarm cotainer 属于同一个 ingress
- ingress-sbox: 一个隐藏的 container，连接 ingress 和 docker_gwbridge，实现 routing mesh (ipvs)

比如我们有两个host，node1, node2, 在node2上启动了ngnix，并通过`-p 80:8080`将端口暴露到 host:8080，当我们对 node1:1080发起请求时:

1. 通过 iptables DNAT 转换，将 node1:1080 通过 docker_gwbridge 转到 node1 上的ingress_sbox:1080
2. ingress-sbox PREROUTING Chain 将目的端口1080 转换为 80
3. ingress-sbox POSTROUTING Chain 将该请求路由到 ngnix 的 vip(ingress 上), [ipvs](http://www.zsythink.net/archives/2134) 是 Linux 内核提供的四层负载均衡器
4. ipvs 中记录了vip -> 真实ip 的映射，比如目前只有 node1上ingress:1080 可用，则转发到该地址。

![](/assets/image/201711/docker-overlay.png "")

[图片出处](https://neuvector.com/network-security/docker-swarm-container-networking/)

关于 overlay 更多实现细节推荐阅读参考4和5。
### 网络管理

同一个容器可以加入多个不同的网络，并在每个网络中获得一个 IP，由 Docker Daemon 充当 DHCP Server 角色:

	
	# 容器启动时，它默认只能连接到一个网络
	docker run --name alpine1 --network bridge -dit alpine ash
	
	# 通过`docker network create`可创建一个指定类型的网络
	# 如果创建的是 overlay 网络，则需要添加--attachable选项后才能加入其它独立容器
	docker network create -d bridge my_bridge
	
	# 手动将容器添加到其它已有网络
	docker network connect my_bridge alpine1
	
	# 查看容器网络配置，可发现其存在于bridge 和 my_bridge 两个网络中
	# ip 分别为 172.17.0.2，172.18.0.2
	docker inspect alpine1 
	
	# 将容器移除网络
	docker network disconnect my_bridge alpine1
	
	# 删除网络
	docker network rm alpine1


### 其它

在使用Docker时，要注意平台之间实现的差异性，如[Docker For Mac]的实现和标准Docker规范有区别，Docker For Mac的Docker Daemon是运行于虚拟机(xhyve)中的(而不是像Linux上那样作为进程运行于宿主机)，因此Docker For Mac没有docker0网桥，不能实现host网络模式，host模式会使Container复用Daemon的网络栈(在xhyve虚拟机中)，而不是与Host主机网络栈，这样虽然其它容器仍然可通过xhyve网络栈进行交互，但却不是用的Host上的端口(在Host上无法访问)。bridge网络模式 -p 参数不受此影响，它能正常打开Host上的端口并映射到Container的对应Port。文档在这一点上并没有充分说明，容易踩坑。参考[Docker文档](https://docs.docker.com/docker-for-mac/networking/) 和 [这篇帖子](https://forums.docker.com/t/should-docker-run-net-host-work/14215)


### 参考

1. [Docker源码分析(七)：Docker Container网络(上)](http://www.infoq.com/cn/articles/docker-source-code-analysis-part7)
2. [Docker networking](https://docs.docker.com/engine/userguide/networking/)
3. [理解Docker跨多主机容器网络](http://tonybai.com/2016/02/15/understanding-docker-multi-host-networking/)
4. [How Docker Swarm Container Networking Works](https://neuvector.com/network-security/docker-swarm-container-networking/)
5. [How does it work? Docker! Part 3](https://blog.octo.com/en/how-does-it-work-docker-part-3-load-balancing-service-discovery-and-security/)