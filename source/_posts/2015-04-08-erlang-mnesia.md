---
layout: post
title: Erlang mnesia
tags: erlang
categories: erlang
---

mnesia是基于Erlang的分布式数据库管理系统，是Erlang OTP的重要组件。

## 基础特性

### 1. 分布式的ets

mnesia数据库被组织为一个表的集合，每个表由记录(通常被定义为Erlang Record)构成，表本身也包含一些属性，如类型，位置和持久性。这种表集合和记录的概念，和ets表很类似。事实上，mnesia中的数据在节点内就是以ets表存储的。因此，mnesia实际上是一个分布式的ets。

<!--more-->

### 2. 表的存储形式

mnesia中的表在节点内有三种存储形式：

* `ram_copies`: 表仅存储于内存，可通过`mnesia:dump_tables(TabList)`来将数据导入到硬盘。
* `disc_copies`: 表存储于内存中，但同时拥有磁盘备份，对表的写操作会分为两步：1.将写操作写入日志文件 2. 对内存中的表执行写操作
* `disc_only_copies`: 表仅存储于磁盘中，对表的读写将会更慢，但是不会占用内存

表的存储形式可以在表的创建中指出，默认为ram_copies。也可以在创建表后通过`mnesia:change_table_copy_type/3`来修改。

### 3. 表的重要属性

表的属性由`mnesia:create_table(Name, TableDef)`中的TableDef指定，TableDef是一个Tuple List，其中比较重要的属性有：

* `type`: 表的类型，主要有set, ordered\_set和bag三种。前两者要求key唯一，bag不要求key唯一，但要求至少有一个字段不同。另外set和bag通过哈希表实现，而ordered\_set则使用其它数据结构(如红黑树)以对key排序。type属性默认为set。
* `attributes`: 表中条目的字段，通常由record\_info(fields, myrecord)得出，而myrecord一般则用作表名。
* `local_content`: 标识该表是否为本地表，local\_content属性为true的表将仅本地可见，不会共享到集群中。local\_content默认为false。
* `index`: 表的索引。
* `ram_copies`: 指名该表在哪些节点上存储为ram\_copies。默认值为[node()]。即新建表默认都存储为ram\_copies。
* `disc_copies`: 该表在哪些节点上存储为disc\_copies。默认为[]。
* `disc_only_copies`: 该表在哪些节点上存储为disc\_only\_copies。默认为[]。

### 4. schema表

schema表是mnesia数据库一张特殊的表，又叫模式表。它记录数据库中其它表的信息，schema表只能有ram\_copies或disc\_copies两种存储形式。并且一旦schema表存储为ram\_copies，那么该节点上的其它表，也将只能存储为ram\_copies。

mnesia需要schema表的初始化自身，可在mnesia启动前，通过`mnesia:create_schema/1`来创建一个disc\_copies类型的schema表，如果不调用`mnesia:create_schema/1`，直接启动`mnesia:start/0`，默认生成一个ram\_copies类型的schema表，此时我们称该mnesia节点为"无盘节点"，因为其所有表都不能存储于磁盘中。
	
### 5. 单节点使用示例

	➜  ~  erl -mnesia dir '"Tmp/ErlDB/test"'

	Erlang/OTP 17 [erts-6.3.1] [source] [64-bit] [smp:4:4] [async-threads:10] [hipe] [kernel-poll:false] [dtrace]

	Eshell V6.3.1  (abort with ^G)
	# 创建disc_copies存储类型的schema表 但其它表的默认存储类型仍然为ram_copies
	1> mnesia:create_schema([node()]).
	ok
	2> mnesia:start().
	ok
	3> rd(person, {name, sex, age}).
	person
	# 创建disc_copies存储类型的table，table的fields即为person记录的fields
	4> mnesia:create_table(person, [{disc_copies, [node()]}, {attributes, record_info(fields, person)}]).
	{atomic,ok}
	# 等价于mnesia:dirty_write({person, "wdj", undefined, 3})
	5> mnesia:dirty_write(#person{name="wdj", age=3}).
	ok
	6> mnesia:dirty_read(person, "wdj").
	[#person{name = "wdj",sex = undefined,age = 3}]

`record_info(fileds, person)`返回`[name,sex,age]`，`mnesia:create_table/2`默认将attributes属性中的第一个field作为key，即name。

mnesia:read, mnesia:write, mnesia:select等API均不能直接调用，需要封装在事务（transaction）中使用：

	F = fun() ->  
    	Rec = #person{name="BigBen", sex=1, age=99},  
    	mnesia:write(Rec)  
	end,  
	mnesia:transaction(F). 

而对应的`mnesia:dirty_read`，`mnesia:dirty_write`，即"脏操作"，无需事务保护，也就没有锁，事务管理器等。dirty版本的读写一般要比事务性读写快十倍以上。但是失去了原子性和隔离性。

### 6. 表名与记录名

mnesia表由记录组成，记录第一个元素为是记录名，第二个元素为标识记录的键。{表名，键}可以唯一标识表中特定记录，又称为记录的对象标识(Oid)。

mnesia要求表中所有的记录必须为同一个record的实例，前面的例子中，表名即为记录名，表字段则为记录的域。而实际上，记录名可以是但不一定是表名，记录名可通过record_name属性指出，没有指定table\_name则记录名默认为create\_table第一参数指定的表名。

	mnesia:dirty_write(Record) ->
		Tab = element(1, Record), 
		mnesia:dirty_write(Tab, Record). % 这里提取出表名，表名和表中记录原型实际上是分离的

表名和记录名不一致使我们可以定义多个以同一record的原型的table。

## 集群管理
	
	% 创建集群 需要各节点的mnesia都未启动
	mnesia:create_schema(['node1@host,'node2@host'])
	% 创建表 指明在各节点上的存储类型 如果没指定，则为remote类型
	mnesia:create_table(person, [{ram_copies,['node1@host']}])
	% 删除表的所有备份
	mnesia:delete_table(person)
	% 删除整个schema和表数据(包含持久化文件)
	mnesia:delete_table(['node1@host,'node2@host'])
	
	% 集群动态配置能力
	% 动态加入集群(等价于启动参数：-mnesia extra_db_nodes NodeList)
	mnesia:change_config(extra_db_nodes, ['node3@host'])
	% 动态修改表的存储类型
	mnesia:change_table_copy_type(person, node(), disc_copies)
	% 添加远程表的本地备份
	mnesia:add_table_copy(person, 'node3@host', ram_copies)
	% 迁移表备份 表存储类型不变
	mnesia:move_table_copy(person, 'node3@host', 'node4host')
	% 删除表的本节点备份
	mnesia:del_table_copy(person, 'node3@host')
	% 对表的元数据和所有记录进行热升级
	mnesia:transform_table(Tab, Fun, NewAttributeList, NewRecordName)

- [这篇FAQ][4]中归纳了mnesia集群的大多数问题
- 在新节点动态加入集群的过程中，如果新节点mnesia已经启动，启动的节点会尝试将其表定义与其它节点带来的表定义合并。这也应用于模式表自身的定义
- mnesia会同步集群中节点上所有的表信息，如果某节点需要自己本地维护一张表而不希望共享该表，可以在创建表时指定`local_content`属性。该类型的表表名对mnesia可见，但每个节点写入的数据不会被同步，即每个节点都只能看到自己写入的数据
- mnesia后台同步时，会形成一个全联通网络(即使集群节点都是hidden节点)
- 如果新加入节点和已有集群的schema表都是disc\_copies，则会merge schema failed

## 特性总结

mneisa的优势:

- 与Erlang的完美契合，记录字段可以是任意Erlang Term，具备强大的描述能力
- 和传统数据库一样，支持事务，索引，分片等特性
- 分布式特性，表的存储类型和位置对应用透明，支持分布式事务
- 强大的动态配置能力，包括集群的动态伸缩，表的动态配置，增删，转移，升级等

mnesia缺点：

- 多节点事务带来的开销，尽可能少使用事务(在逻辑上配合做处理)
- mnesia全联通网络的维护开销，在使用时需要控制集群节点数量
- 不适合存储大量数据，这会带来网络负载

## 参考文档

* [Erlang Mnesia Man Page][1]
* [Building A Mnesia Database][2]
* [Mnesia 中文版 用户手册][3]

[1]: http://www.erlang.org/doc/man/mnesia.html "erlang mnesia"
[2]: http://www.erlang.org/doc/apps/mnesia/Mnesia_chap3.html "building a mnesia database"
[3]: http://www.hitb.com.cn/c/document_library/get_file?p_l_id=10190&folderId=11012&name=DLFE-1103.pdf "mnesia用户手册"
[4]: http://veniceweb.googlecode.com/svn/trunk/public/daily_tech_doc/erlang_faq_20091125.txt
