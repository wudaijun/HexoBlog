---
title: MongoDB 使用要点
layout: post
categories: database
tags: mongodb

---


## 文档大小

MongoDB中Bson文档的最大限制为16MB，超过这个限制的文档可能需要使用GridFs等其它手段来存储。

## 一. 查询

### 1.1 "多段式"查询

当执行find操作的时候，只是返回一个游标，并不立即查询数据库，这样在执行之前可以给查询附加额外选项。几乎所有游标对象的方法都返回游标本身，因此可以按任意顺序组成方法链。以下查询是等价的：

    > var cursor = db.foo.find().sort({"x":1}).limit(1).skip(10)
    > var cursor = db.foo.find().limit(1).sort({"x":1}).skip(10)
    > var cursor = db.foo.find().skip(10).limit(1).sort({"x":1})

此时，我们只是构造了一个查询，并没有执行实际操作，当我们执行：

    > cursor.hasNext()

这时，查询被发往服务器，sell立即获取第一个块(前101个文档或前1M数据，取其小者)，这样下次调用next或hasNext时，就不必再次向服务器发起一次查询。客户端用完了第一组结果，shell会再次向服务器获取下一组结果(大小不超过4MB)， 直至结果全部返回。可通过[batchSize][cursor.batchSize()]设置游标返回的块的文档数量。

注：如果在shell中，没有将返回的游标赋给一个var，shell将自动迭代游标20次，显示出前20调记录。

### 1.2 快照查询

由于find()操作是**多段式**的，集合在游标查询的过程中，文档可能由于大小改变而发生了移动，比如某个文档由于增大，超过了原来分配的空间，导致文档被移动到集合的末尾处，此时使用游标查询可能会再次返回这些被移动的文档。解决方案是对查询进行[快照][cursor.snapshot()]:

    > db.foo.find().snapshot()

## 1.3 游标释放

前面看到的游标都是客户端游标，每个客户端游标对应一个数据库游标，数据库游标会占用服务器资源，因此合理地尽快地释放游标是有必要的。以下几种情况将会释放数据库游标：

- 客户端主动发起关闭游标请求
- 游标迭代完匹配结果
- 客户端游标不在作用域(客户端游标被析构/GC)，会向服务器发送消息销毁对应数据库游标
- 游标10分钟未被使用，数据库游标会自动销毁，可通过[noCursorTimeout][cursor.noCursorTimeout()](注意和[maxTimeMS][cursor.maxTimeMs()]的区别)取消游标超时

## 1.4 cursor.explain()

游标的另一个很有用的函数是explain()，它能够提供`db.collection.find()`操作的详尽分析，包括

- 查询方案的决策：使用和何种方案(如使用哪个索引)，查询方向
- 执行结果分析：扫描了多少文档，多少个索引条目，花费时间等
- 服务器信息：地址，端口，版本等
- 分片信息：如果集合使用了分片，还会列出访问了哪个分片，即对应的分片信息

这些信息对于开发期间的查询性能分析和索引的对比性测试是非常有帮助的，关于它的详细解释，参见[cursor.explain][cursor.explain]官方文档。

## 1.5 读取策略

在目前最新的MongoDB 3.2版本中，新加了读取策略([ReadConcern][read concern])，支持local和majority两种策略，前者直接读取当前的MongoDB实例，但是可能会读到副本集中不一致的数据，甚至可能回滚。majority策略读取那些已经被副本集大多数成员所认可的数据，因此数据不可能被回滚。目前majority并不被所有的MongoDB引擎所支持，具体要求和配置，参见官方文档。

## 1.6 其它查询技巧

    1. 不要使用skip()来实现分页，这样每次都会查询所有文档，可利用每页最后一个文档中的key作为查询条件来获取下一页。
    2. 获取随机文档，不要先将所有的文档都找出来，然后再随机。而是为所有的文档加一个随机Key，每次查询{"$gte":randomkey}或{"$lt":randomkey}即可
    3. MongoDB对内嵌文档的支持非常完善，可通过{"key1.key2": value2}直接查询内嵌文档，也可以在内嵌文档Key上建立索引

## 二. 写入

### 2.1 写入策略

MongoDB支持灵活的写入策略([WriteConcern][write concern]):

用法：`db.collection.insert({x:1}, {writeConcern:{w:1,j:false}})`

1. w: 数据写入到number个节点才向客户端确认
    - {w: 0}: 对客户端的写入不需要发送任何确认，适用于性能要求较高，但不关注正确性的场景
    - {w: 1}: 默认的写入策略，数据写入到Primary就向客户端发送确认
    - {w: "majority"}: 数据写入到副本集大多数成员后向客户端发送确认，适用于对数据安全性要求高的场景，但会降低写入性能
2. j: 写入操作的journal持久化后才向客户端确认(需要w选项所指定的节点均已写入journal)，默认为false。
3. wtimeout: 写入超时时间，仅当w选项的值大于1才有效，当写入过程出现节点故障，无法满足w选项的条件时，超过wtimeout时间，则认定写入失败。

关于写入策略的具体实现，参见：http://www.mongoing.com/archives/2916

### 2.2 

[cursor.snapshot()]: "https://docs.mongodb.com/manual/reference/method/cursor.snapshot/"
[cursor.noCursorTimeout()]: "https://docs.mongodb.com/manual/reference/method/cursor.noCursorTimeout/#cursor.noCursorTimeout"
[cursor.maxTimeMs()]: "https://docs.mongodb.com/manual/reference/method/cursor.maxTimeMS/"
[cursor.batchSize()]: "https://docs.mongodb.com/manual/reference/method/cursor.batchSize/#cursor.batchSize"
[write concern]: "https://docs.mongodb.com/manual/reference/write-concern/"
