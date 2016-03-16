### 分布式Erlang

一个Erlang分布式系统由多个Erlang节点(node)组成，每一个节点即为一个Erlang虚拟机，这些节点可以彼此通信。不同节点节点上Pid之间通信(link,monitor等)，是完全透明的。

一个节点要加入集群需要两个条件：

1. 通过`-sname`或`-name`设置节点名字，前者在局域网中使用，后者在广域网中使用，两种命名方式的节点不能相互通信。
2. 设置自己的cookie，可通过`-setcookie`设置，默认为'nocookie'，只有具备相同cookie的节点才能建立连接。

Erlang节点之间通过TCP/IP建立连接并通信，集群中的节点是松散连接的(loosely connected)，只有当第一次用到其它节点名字时，才会和该节点建立连接(并且校验cookie)。但同时连接也是扩散(transitive)的，如果节点A尝试连接节点B，而节点B连接又连接了节点C，那么A也会尝试和C连接：

	# node1
	erl -sname "node1" -setcookie "123"                                                               
	(node1@myhost)1> nodes().
	[]

	# node2
	erl -sname "node2" -setcookie "123"                                                               
	(node2@myhost)1> nodes().
	[] % loosely connected
	(node2@myhost)1> net_adm:ping('node1@myhost').
	pong
	(node2@myhost)1> nodes().
	['node1@myhost']
	
	# node3
	erl -sname "node3" -setcookie "123"
	(node3@myhost)1> net_kernel:connect_node('node1@myhost').
	true
	(node3@myhost)2> nodes().
	['node1@myhost', 'node2@myhost'] % transitive
	
要关闭Erlang节点的transitive行为，使用虚拟机启动选项`-connect_all false`。当节点挂点后，其上所有的连接都会被关闭，可通过`nodes()`来查看本节点连接的所有可见节点。

Erlang节点通过epmd(Erlang Port Mapper Daemon)守护进程来获取节点名字到节点IP地址的映射，empd是每台电脑上的守护进程，

### Erlang集群

Erlang为分布式提供的基础设施

1. 良好的函数式编程语义，为并发而生
2. 统一的通信方式(Pid)，屏蔽底层通讯细节(Erlang进程间/系统进程间/物理机间)，将本地代码扩展为分布式程序非常容易
3. 透明的通信协议，完善的序列化/反序列化支持
4. 完善的监控能力：监督(supervisor), 监视(monitor), 链接(link)等
5. 其它分布式组件：如epmd, mnesia等

Erlang让构建一个分布式系统变得很简单，但事实上，分布式一点也不简单，在分布式系统中，有如下悖论：

基础支撑：

集群节点通过向master节点注册/注销自己来加入/退出集群，master节点不止一个，有周知的IP，端口。集群节点之间的信息共享通过mnesia来实现。这些信息包括集群中所有节点信息，以及所有进程的索引信息。
 
#### 容灾能力

Erlang OTP为进程级别的容错和恢复提供了保障，因此主要考虑节点级的容灾，如果Erlang节点挂掉了或者物理机宕机，master节点会收到**nodedown**消息，此时从集群中删除宕机节点信息，并将宕机节点上已有的进程重新分发到其它节点。master本身至少会有两个，部署在不同的机器上。

#### 负载均衡

根据mnesia中的统计信息，我们可以轻易实现为新进程分配节点的算法。并且可以通过master节点定期监控调整节点负载。

#### 可伸缩性

支持节点的动态添加和删除，节点的增删信息将由master统一管理，通过mnesia分享到整个集群。

#### 全局一致性

前面的各种特性都依赖于两点：

1. Erlang的net_kernel为节点集群提供基础服务
