---
title: MongoDB 存储引擎
layout: post
categories: database
tags: mongodb

---

MongoDB目前支持三种存储引擎：MMAPv1 Storage Engine，In-Memory Storage Engine, WiredTiger Storage Engine。

## MMAPv1 Storage Engine

MongoDB3.2之前版本的默认引擎。

- 数据文件通过系统级[mmap][]映射到内存空间进行管理
- MongoDB将所有的变更操作日志并间歇写入磁盘(默认100ms)，日志可用于数据恢复，对于实际数据文件延迟写入(默认60s)。操作系统mmap本身也会flush
- 支持collection级别的并发
- 文档在磁盘中连续存放，文档变大时，会导致重新分配文档空间，并更新索引(可能导致磁盘碎片，更新效率低)
- 在MongoDB3.0中，使用"Power of 2 Sized Allocations"分配策略，减少了文档移动并且被移动或删除后的文档空间可被新文档复用，并且可定制分配策略([Power of 2 Sized Allocations][] or [no padding][])
- 由于mmap()机制，MongoDB Cache总是尝试占用更多的内存，因此，将其部署在内存大的机器上，会有显著的性能提升


## In-Memory Storage Engine

限企业版，64bits。

- 不维护任何磁盘数据，包括配置数据，索引，用户证书，等等，Everything In Memory
- 文档级别的并发支持
- 在启动时配置最大使用内存，默认1GB，超出使用内存将会报错
- 不可落地，不可恢复
- 支持分片，复制集

## WiredTiger Storage Engine

限MongoDB version>3.0 在MongoDB3.2中，已将WiredTiger作为默认存储引擎。

- 文档级别的并发支持(乐观锁)
- 支持快照落地，每60s或超过2GB的变更日志执行一次，在写最新快照时，上一个快照仍然有效，防止MongoDB在快照落地时挂掉，在快照落地完成后，上一个快照将被删除
- 和MMAPv1一样，支持通过变更日志故障恢复，并且可关闭日志记录，此时，故障恢复主要依赖于快照。日志恢复可与快照恢复一同使用
- 支持日志，文档数据块，索引压缩，可配置或关闭压缩算法
- 使用的最大内存可以设定

参考：

MongoDB MMAPv1内部实现：    http://www.mongoing.com/archives/1484
MongoDB WiredTiger内部实现：http://www.mongoing.com/archives/2540
MongoDB存储特性与内部原理： http://shift-alt-ctrl.iteye.com/blog/2255580

[mmap]: "http://www.cnblogs.com/huxiao-tee/p/4660352.html"
[no padding]: "https://docs.mongodb.com/manual/reference/command/collMod/#noPadding"
[Power of 2 Sized Allocations]: "https://docs.mongodb.com/manual/core/mmapv1/#power-of-2-sized-allocations"


