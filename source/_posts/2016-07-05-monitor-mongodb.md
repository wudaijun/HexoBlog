---
title: MongoDB 状态监控
layout: post
categories: database
tags: mongodb

---

## 一. 关键指标

- 慢查询：当MongoDB处理能力不足时，找出系统中的慢查询，分析原因，看能否通过建立索引或重新设计schema改进
- 内存使用：MongoDB吃内存(特别是MMAPv1)，至少要给MongoDB足够的内存存放索引，最理想的情况是能够存放所有数据。当内存占用过高，或者page faults过高时，考虑能不能给MongoDB预留更多的内存。
- 磁盘占用：特别是对于MMAPv1，涉及到磁盘占用的因素有很多，不合理的schema(文档频繁移动)或集合/文档的删除都可能会导致磁盘空间利用不足。前期需要设计好schema，后期维护也需要定期整理磁盘数据。
- 连接数：MongoDB为每个连接分配一个线程，因此连接是占资源的，并且也不是越多连接越好。合理地控制连接数。
- 索引不命中：查看所有查询的索引不命中情况，尽量让所有查询都通过索引
- 锁等待：锁等待的原因有很多，连接数过多，操作频繁，慢操作，schema设计过于反范式化等，可从上面的原因针对性解决。

<!--more-->
## 二. 监控工具

### 1. mongostat

mongodb自带的状态检测工具，按照固定时间间隔(默认1s)获取mongodb的当前运行状态，适用于对临时异常状态的监控：

	// from MongoDB 3.0 MMAPv1
    ▶ mongostat
    insert query update delete getmore command flushes mapped vsize    res faults qr|qw ar|aw netIn netOut conn     time
        *0    40      1     *0       0     1|0       0   4.3G 11.1G 150.0M      0   0|0   0|0    2k    12k  201 19:07:04
        *0    20     *0     *0       0     1|0       0   4.3G 11.1G 150.0M      0   0|0   0|0    1k    11k  201 19:07:05
        *0    *0      1     *0       0     1|0       0   4.3G 11.1G 150.0M      0   0|0   0|0  244b    10k  201 19:07:06
        *0    20     *0     *0       0     1|0       0   4.3G 11.1G 150.0M      0   0|0   0|0    1k    11k  201 19:07:07
        *0    20     *0     *0       0     2|0       0   4.3G 11.1G 150.0M      0   0|0   0|0    1k    11k  201 19:07:08

具体各列的意义都很简单，见官方文档即可。比较重要的字段有：

- res:      常驻内存大小
- mapped:   通过mmap映射数据所占用虚拟内存大小(只对MMAPv1有效)
- vsize:    mongodb进程占用的虚拟内存大小
- faults:   page fault次数，如果持续过高，则可以考虑加内存
- qr/qw:    读取/写入等待队列的大小，如果队列很大，表示MongoDB处理能力跟不上，可以看看是否存在慢操作，或者减缓请求
- conn:     当前连接数，conn也会占用MongoDB资源，合理控制连接数
- idx miss: 索引不命中所占百分比 如果太高则要考虑索引是否设计得不合理
- flushes:  通常为0或1，对于MMAPv1，表示后台刷盘次数(默认60s)，对于WiredTiger，表示执行checkpoint次数(默认60s或2GB journal日志)
- lr/lw:    读取/写入操作等待锁的比例 (New In MongoDB 3.2, Only for MMapv1)
- lrt/lwt:  读取/写入锁的平均获取时间(微妙)

更多[参考][mongostat]。


### 2. db.serverStatus()

返回数据库服务器信息，该命令返回的数据量很大，但执行很快，不会对数据库性能造成影响，其中比较重要的字段有：

- db.serverStatus().mem: 当前数据库内存使用情况
- db.serverStatus().connections: 当前数据库服务器的连接情况
- db.serverStatus().extra_info: 在Linux下，包含page fault次数
- db.serverStatus().locks: 数据库各种类型锁竞态情况
- db.serverStatus().backgroundFlushing: 数据库后台刷盘情况(默认60s)一次，仅针对MMAPv1存储引擎

更多[参考][db.serverStatus()]。


### 3. Profiler

主要用于分析查询性能，默认是关闭的，Profiler获取关于查询/写入/命令等操作的详细执行数据，并将这些分析数据写入system.profile集合。Profiler有三个Level：

- Level 0: 意味着关闭Profiler，并不收集任何数据，也是mongod的默认配置。注意mongod总是会将"慢操作"(执行时间超过[slowOpThresholdMs][]，默认100ms)的操作写入mongod日志(不是system.profile集合)
- Level 1: 只收集所有慢操作的信息，慢操作执行时间可通过[修改slowOpThresholdMs参数][modify slowOpThresholdMs]指定
- Level 2: 收集所有的数据库操作执行信息

需要注意，一个操作执行慢，可能是索引不合理，也可能是page fault从磁盘读数据等原因导致。需要进一步分析。

使用示例：

	> db.setProfilingLevel(2)
	{ "was" : 0, "slowms" : 100, "ok" : 1 }
	>
	> db.getProfilingStatus()
	{ "was" : 2, "slowms" : 100 }
	> db.user.insert({"name":"wdj"})
	WriteResult({ "nInserted" : 1 })
	> db.system.profile.find()
	{ "op" : "insert", "ns" : "test.user", "query" : { "insert" : "user", "documents" : [ { "_id" : ObjectId("577e62991fa7b960bb8bf0af"), "name" : "wdj" } ], "ordered" : true }, "ninserted" : 1, "keyUpdates" : 0, "writeConflicts" : 0, "numYield" : 0, "locks" : { "Global" : { "acquireCount" : { "r" : NumberLong(2), "w" : NumberLong(2) } }, "Database" : { "acquireCount" : { "w" : NumberLong(1), "W" : NumberLong(1) } }, "Collection" : { "acquireCount" : { "w" : NumberLong(1), "W" : NumberLong(1) } } }, "responseLength" : 25, "protocol" : "op_command", "millis" : 32, "execStats" : {  }, "ts" : ISODate("2016-07-07T14:09:29.690Z"), "client" : "127.0.0.1", "allUsers" : [ ], "user" : "" }
	>

system.profile集合中，关键字段：op(操作类型), ns(操作集合), ts(操作时间)，millis(执行时间ms),query(操作详情)。

更多[参考][Profiler]。

### 4. db.currentOp()

当MongoDB比较繁忙或者在执行比较慢的命令时，可能会阻塞之后的操作(视数据库和操作的并发级别而定)。可通过db.currentOp()来获取当前正在进行的操作，并可通过db.killOp()来干掉它。

更多[参考][db.currentOp()]。

### 5. db.stats()

返回对应数据库的信息，包括集合数量，文档总大小，文档平均大小，索引数量，索引大小等静态信息：

	> db.stats()
	{
	        "db" : "test",
	        "collections" : 2,
	        "objects" : 3,
	        "avgObjSize" : 430,
	        "dataSize" : 1290,
	        "storageSize" : 49152,
	        "numExtents" : 0,
	        "indexes" : 1,
	        "indexSize" : 16384,
	        "ok" : 1
	}
	>

更多[参考][db.stats()]。

### 6. db.collStats()

返回集合详细信息.

更多[参考][db.collStats()]。


[db.serverStatus()]: "https://docs.mongodb.com/manual/reference/command/serverStatus/"
[mongostat]: "https://docs.mongodb.com/manual/reference/program/mongostat/"
[Profiler]: "https://docs.mongodb.com/manual/tutorial/manage-the-database-profiler/"
[slowOpThresholdMs]: "https://docs.mongodb.com/manual/reference/configuration-options/#operationProfiling.slowOpThresholdMs"
[modify slowOpThresholdMs]: "https://docs.mongodb.com/manual/tutorial/manage-the-database-profiler/#database-profiling-specify-slowms-threshold"
[db.currentOp()]: "https://docs.mongodb.com/manual/reference/method/db.currentOp/"
[db.stats()]: "https://docs.mongodb.com/manual/reference/command/dbStats/"
[db.collStats()]: "https://docs.mongodb.com/manual/reference/command/collStats/#dbcmd.collStats"
