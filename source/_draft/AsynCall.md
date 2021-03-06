
前面比较过Erlang和Go在设计理念上的一些区别和理论基础，这里简单讨论一下在应用层面上的具体体现。

总的来说，通信实体间的交互方式无非两种，同步和异步。先来看看Erlang和Go中同异步实现：

Erlang中的异步原语`!`向进程发送一条消息，并忽略任何错误，同步在异步的基础上，通过`receive`阻塞等待对方进程

从理论上来讲，两个通信实体间的交互都应该是异步的，因为你无法确保对方的当前状态(Normal/Crash/Busy)，因此使用同步是比较危险的，要想"安全"地使用同步，你需要处理超时和异常，

同步比较好理解，相当于一次远程函数调用(RPC)，调用方可以按照处理正常函数返回一样处理调用结果。而相比同步，异步才是大多数情况下通信实体的正确的交互方式，特别在分布式下。以Erlang和Go为例，先看看异步的实现。


异步调用的几种状态，如异步加载一个玩家：

1. 处理结果: 加载后的玩家数据/错误
2. 局部状态: 玩家ID，LoginReq等
3. 全局状态: 当前时间等

发起一个异步调用，如何保存这些状态，	