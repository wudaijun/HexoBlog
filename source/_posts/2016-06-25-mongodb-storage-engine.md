---
title: MongoDB 存储引擎
layout: post
categories: database
tags: mongodb

---

MongoDB目前支持三种存储引擎：MMAPv1 Storage Engine，In-Memory Storage Engine, WiredTiger Storage Engine。

## MMAPv1 Storage Engine

MongoDB3.2之前版本的默认引擎。

### 1. 存储原理

文档在磁盘中连续存放，文档所占用的磁盘空间包括文档数据所占空间和文档填充(padding)。

![](/assets/image/mongodb/MMAPv1_storage_engine.png)

摘自：MongoDB MMAPv1内部实现：http://www.mongoing.com/archives/1484

<!--more-->

#### 1.1 文档移动

由于文档在磁盘中连续存放，当文档大小增长时，可能需要重新分配文档空间，并更新索引。这会使写入效率降低，因此通常MongoDB为文档分配的record空间会包括document数据和padding空间。这样减少了文档移动的可能性，提高了写入效率。

#### 1.2 padding算法

 在MongoDB3.0之前，MMAPv1使用填充因子([padding factor][])来决定空间分配，填充因子会根据文档移动的频繁度动态调整(初始时为1.0)，当padding factor = 1.5时，MMAPv1将为文档分配`sizeof(record) = 1.5 * sizeof(document)`的空间，其中`0.5*sizeof(document)`用作padding。

padding factor这种方式看起来很智能，但是由于文档的record大小不一，在文档删除或移动之后，文档原来分配的空间很难被再次利用，从而造成了磁盘碎片，这也是MongoDB3.0之前数据占用磁盘空间大的主要原因之一。

因此在MongoDB3.0之后，不再使用padding factor填充机制，而使用[Power of 2 Sized Allocations][]，为每个文档分配2的N次方的空间(超过2MB则变为2MB的倍数增长)，这样做既可以减少文档的移动，文档被删除或移动后的空间也可以被有序地组织起来，达成复用(只能被其所在collection的文档复用)。除了Power of 2 Sized Allocations外，MongoDB3.0还提供了[no padding][]分配策略，即只分配文档实际大小的磁盘空间，但应用程序需要确保文档大小不会增长。

虽然Power of 2 Sized Allocations解决了磁盘碎片的问题，但改进后的MMAPv1引擎仍然在数据库级别分配文件，数据库中的所有集合和索引都混合存储在数据库文件中，并且删除或移动文档后的空间会被保留用以复用，因此磁盘空间无法无法即时自动回收的问题仍然存在(即使drop collection)。

### 2.并发能力

在MongoDB3.0之前，只有MMAPv1存储引擎支持，并且只支持Database级的锁，有时候不得不刻意将数据分到多个数据库中提升并发能力。在MongoDB3.0之后，MMAPv1终于支持collection级的并发，并发效率提升了一个档次。参考[MongoDB concurrency FAQ][]。

### 3. 故障恢复

MongoDB默认记录所有的变更操作日志([journal][MMAPv1 journaling])并写入磁盘，MongoDB flush变更日志的频率(默认100ms)比flush数据的频率(默认60s)要高，因此journal是MongoDB故障恢复的重要保障。

### 4. 内存占用

由于MMAPv1使用[mmap][]来将数据库文件映射到内存中，MongoDB总是尽可能的多吃内存，以映射更多的数据文件。并且页面的换入换出基本交给OS控制(MongoDB不建议[修改][MMAPv1 journal]flush频率)，因此，将MongoDB部署在更高RAM环境下，是提升性能的最有效的方式之一。

### 5. 遗留问题

- 磁盘占用，运维人员可能需要定期的整理数据库([compat][]，[repairDatabase][])
- 内存占用，基本是有多少吃多少
- collection级的并发控制仍然偏弱

## WiredTiger Storage Engine

MongoDB version3.0中引入，在MongoDB3.2中，已将WiredTiger作为默认存储引擎。

### 1. 并发能力

文档级别的并发支持，WiredTiger通过MVCC实现文档级别的并发控制，即文档级别锁。这就允许多个客户端请求同时更新一个集合内存的多个文档。更多MongoDB并发模型，参见[MongoDB concurrency FAQ][]。

### 2. 故障恢复

支持checkpoint和journal两种方式进行持久化。

checkpoint是数据库某一时刻的快照，每60s或超过2GB的变更日志执行一次，在写最新快照时，上一个快照仍然有效，防止MongoDB在快照落地时挂掉，在快照落地完成后，上一个快照将被删除。

和MMAPv1一样，支持通过变更日志故障恢复，journal可与checkpoint集合使用，提供快速，可靠的数据恢复。可禁用wiredtiger journal，这在一定程度上可以降低系统开支，对于单点MongoDB来说，可能会导致异常关闭时丢失checkpoint之间的数据，对于复制集来说，可靠性稍高一点。在MongoDB3.2之前的版本中，WiredTiger journal默认在日志超过100MB时持久化journal一次，系统宕机最多会丢失100MB journal数据。在3.2版本中，加入了默认50ms时间间隔刷盘条件。参见官方文档[journaling wiredtiger][]。

### 3. 磁盘占用

不同于MMAPv1在数据库级别分配数据文件，WiredTiger将每个collection的数据和索引单独存放，并且会即时回收文档和集合占用空间。

WiredTiger的另一个两点是支持日志，文档数据块，索引压缩，可配置或关闭压缩算法，大幅度节省了磁盘空间。

### 4. 内存占用

WiredTiger支持内存使用容量配置，用户可通过[WiredTiger CacheSize][]配置MongoDB WiredTiger所能使用的最大内存，在3.2版本中，该参数默认值为`max(60%Ram-1GB, 1GB)`。这个内存限制的并不是MongoDB所占用的内存，MongoDB还使用OS文件系统缓存(文件可能是被压缩过的)。

### 5. 遗留问题

相较于MMAPv1，压缩算法和新的存储机制，极大减少了磁盘空间占用，文档级别的并发控制，在多核上吞吐量有明显提升。MongoDB WiredTiger仍然是个吃内存的家伙，虽然可以配置内存最高占用，但更多的内存确实能带来更好的读写效率。


## In-Memory Storage Engine

纯内存版的MongoDB，限企业版，64bits。简单介绍一下：

- 不维护任何磁盘数据，包括配置数据，索引，用户证书，等等，Everything In Memory
- 文档级别的并发支持
- 在启动时配置最大使用内存，默认1GB，超出使用内存将会报错
- 不可落地，不可恢复
- 支持分片，复制集

总结：为啥不用Redis？

## 参考：

1. MongoDB Storage Engine: https://docs.mongodb.com/manual/core/storage-engines/
2. MongoDB Storage FAQ: https://docs.mongodb.com/manual/faq/storage/
3. MongoDB MMAPv1内部实现：    http://www.mongoing.com/archives/1484
4. MongoDB WiredTiger内部实现：http://www.mongoing.com/archives/2540
5. MongoDB存储特性与内部原理： http://shift-alt-ctrl.iteye.com/blog/2255580
6. MongoDB3.0官方性能测试报告：http://www.mongoing.com/archives/862

[mmap]: "http://www.cnblogs.com/huxiao-tee/p/4660352.html"
[no padding]: "https://docs.mongodb.com/manual/reference/command/collMod/#noPadding"
[Power of 2 Sized Allocations]: "https://docs.mongodb.com/manual/core/mmapv1/#power-of-2-sized-allocations"
[padding factor]: "http://openmymind.net/Whats-A-Padding-Factor/"
[MMAPv1 journaling]: "https://docs.mongodb.com/manual/core/journaling/#journaling-and-the-mmapv1-storage-engine"
[MMAPv1 journal]: "https://docs.mongodb.com/manual/core/mmapv1/#journal"
[compat]: "https://docs.mongodb.com/manual/reference/command/compact/"
[repairDatabase]: "https://docs.mongodb.com/manual/reference/command/repairDatabase/"
[journaling wiredtiger]: "https://docs.mongodb.com/manual/core/journaling/#journaling-wiredtiger"
[WiredTiger CacheSize]: "https://docs.mongodb.com/manual/reference/configuration-options/#storage.wiredTiger.engineConfig.cacheSizeGB"
[MongoDB concurrency FAQ]: "https://docs.mongodb.com/manual/faq/concurrency/"
