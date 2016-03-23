这是从系统运维上来说的，你可能只管理着整个系统的一部分，一方面你需要诊断系统问题的工具，这一点上来说，Erlang提供了比较完善的调试诊断系统，并且支持热更。另一方面，你需要做好系统各个部分间的通讯协议，以管理各个子系统的不同版本的兼容问题。

数据传输代价为零

这里的代价包括时间代价和金钱代价，前者指数据的序列化和反序列化时间，后者指数据对带宽的占用，从这个角度来看，将消息优化得小而短又一次被证明是很重要的。基于Erlang的历史，Erlang并没有对网络传输数据做任何压缩处理(尽管提供了这样的函数)，Erlang的设计者选择让开发者自己按需实现其通讯协议，减小数据传输的代价。

集群是同质的

这里的同质(Homogeneous)指的是同一种语言(或协议)，在分布式集群中，你不能对所有节点都是同质的作出假设，集群中的节点可能由不同的语言实现，或者遵从其它通讯协议。你应该对集群持开放原则而不是封闭原则，