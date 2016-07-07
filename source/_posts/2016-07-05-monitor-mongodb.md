---
title: MongoDB 状态监控
layout: post
categories: database
tags: mongodb

---

## 一. MongoDB状态关键指标



## 监控工具

### 1. [db.serverStatus()][]

该命令返回的数据量很大，但执行很快，不会对数据库性能造成影响，其中比较重要的字段有：

- db.serverStatus().mem: 当前数据库内存使用情况
- db.serverStatus().connections: 当前数据库服务器的连接情况
- db.serverStatus().extra_info: 在Linux下，包含page fault次数
- db.serverStatus().locks: 数据库各种类型锁竞态情况
- db.serverStatus().backgroundFlushing: 数据库后台刷盘情况(默认60s)一次，仅针对MMAPv1存储引擎


### 2. [mongostat][]

mongodb自带的状态检测工具，按照固定时间间隔(默认1s)获取mongodb的当前运行状态，适用于对临时异常状态的监控：

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

[db.serverStatus()]: "https://docs.mongodb.com/manual/reference/command/serverStatus/"
[mongostat]: "https://docs.mongodb.com/manual/reference/program/mongostat/"
