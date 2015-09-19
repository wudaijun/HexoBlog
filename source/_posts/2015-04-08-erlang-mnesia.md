---
layout: post
title: Erlang mnesia
tags: erlang
categories: erlang
---

mnesia是erlang提供的一个基于分布式的数据库管理系统。它的分布式和erlang一样都是"天生的"。集群，备份，主从这些在mnesia上面都非常简单。

<!--more-->

## mnesia 基础

### 1. 官方文档

* [Erlang Mnesia Man Page][1]
* [Building A Mnesia Database][2]
* [Mnesia 中文版 用户手册][3]

### 2. 表的存储形式

mnesia中的表有三种存储形式：ram_copies, disc_copies, disc_only_copies。

* ram_copies: 表仅存储于内存，可通过`mnesia:dump_tables(TabList)`来将数据导入到硬盘。
* disc_copies: 表存储于内存中，但同时拥有磁盘备份，对表的写操作会分为两步：1.将写操作写入日志文件 2. 对内存中的表执行写操作
* disc_only_copies: 表仅存储于磁盘中，对表的读写将会更慢，但是不会占用内存

表的存储形式可以在表的创建中指出，默认为ram_copies。也可以在创建表后通过`change_table_copy_type/3`来修改。

### 3. 表的重要属性

表的属性由`mnesia:create_table(Name, TableDef)`中的TableDef指定，TableDef是一个Tuple List，其中比较重要的属性有：

* type: 表的类型，主要有set, ordered_set和bag三种。前两者要求key唯一，bag不要求key唯一，但要求至少有一个字段不同。另外set和bag通过哈希表实现，而ordered_set则使用其它数据结构(如红黑树)以对key排序。type属性默认为set。
* attributes: 表中条目的字段，通常由record_info(fields, myrecord)得出，而myrecord一般则用作表名。
* local_content: 标识该表是否为本地表，local_content属性为true的表将仅本地可见，不会共享到集群中。local_content默认为false。
* index: 表的索引。
* ram_copies: 指名该表在哪些节点上存储为ram_copies。默认值为[node()]。即新建表默认都存储为ram_copies。
* disc_copies: 该表在哪些节点上存储为disc_copies。默认为[]。
* disc_only_copies: 该表在哪些节点上存储为disc_only_copies。默认为[]。

### 4. schema表

schema表是mnesia数据库一张特殊的表，又叫模式表。它记录数据库中其它表的信息，schema表只能有ram_copies或disc_copies两种存储形式。并且一旦schema表存储为ram_copies，那么该节点上的其它表，也将只能存储为ram_copies。

mnesia需要schema表的初始化自身，可在mnesia启动前，通过`create_schema/1`来创建一个disc_copies类型的schema表，如果不调用`create_schema/1`，直接启动`mnesia:start/0`，默认生成一个ram_copies类型的schema表，此时我们称该mnesia节点为"无盘节点"，因为其所有表都不能存储于磁盘中。
	
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

`record_info(fileds, person)`返回`[name,sex,age]`。`mnesia:create_table/2`默认将attributes属性中的第一个field作为key，即name。

mnesia:read, mnesia:write, mnesia:select等API均不能直接调用，需要封装在事务（transaction）中使用：

	F = fun() ->  
    	Rec = #person{name="BigBen", sex=1, age=99},  
    	mnesia:write(Rec)  
	end,  
	mnesia:transaction(F). 

而对应的mnesia:dirty_read mnesia:dirty_write，即"脏操作"，无需事务保护，也就没有锁，事务管理器等。dirty版本的读写一般要比事务性读写快十倍以上。但是失去了原子性和隔离性。

### 6. 表名与记录名

mnesia表由记录组成，记录第一个元素为是记录名，第二个元素为标识记录的键。{表名，键}可以唯一标识表中特定记录，又称为记录的对象标识(Oid)。

mnesia要求表中所有的记录必须为同一个record的实例，前面的例子中，表名即为记录名，表字段则为记录的域。而实际上，记录名可以是但不一定是表名，记录名可通过record_name属性指出，没有指定table_name则记录名默认为create_table第一参数指定的表名。

	mnesia:dirty_write(Record) ->
		Tab = element(1, Record), 
		mnesia:dirty_write(Tab, Record). % 这里提取出表名，表名和表中记录原型实际上是分离的

表名和记录名不一致使我们可以定义多个以同一record的原型的table。

---

## mnesia 集群

[这篇FAQ][4]中归纳了mnesia集群的大多数问题。

### 1. 启动节点

erlang中，一个节点(node)即为一个erlang虚拟机，比如一个erl shell终端就是一个节点。前面我们启动erl shell时，使用的是单节点模式，要使本节点能与其它的节点通信，需要在erl shell启动时，通过`-name ABC`或`-sname ABC`指定节点名字。erlang 节点名字规范为`nodename@hostname`，nodename即我们指定的ABC，hostname则分为longname(`-name`)和shortname(`-sname`)，longname包含本地完整域名地址，适合广域网使用。而shortname则是本地在局域网上的名字，适合局域网和本机使用。

	erl -sname MyNode
	
	(MyNode@T4F-MBP-15)1>

在erlang脚本中启动节点，需要调用`net_kernel:start([NodeName, NameType])`.

### 2. 创建/加入集群

schema模式表本身带有集群节点的信息，因此我们可以通过 `create_schema(['node1@host,'node2@host'])` 来将node1，node2初始化一个集群，并且指定schema表为disc_copies。在启动的时候，Mnesia使用其模式表来确定应该与哪些节点尝试建立联系。如果其它节点已经启动，启动的节点将其表定义与其它节点带来的表定义合并。这也应用于模式表自身的定义。

应用参数 extra_db_nodes 包含一个 Mnesia 除了在其模式表中找到的节点之外也应该建立联系的节点列表。其默认值为空列表[ ]。因此，当无盘节点需要从一个在网络上的远程节点找到模式定义时，我们需要通过应用参数 `-mnesia extra_db_nodes NodeList` 提供这个信息。没有这个配置参数集，Mnesia 将作为单节点系统启动。也有可能在 Mnesia 启动后用`mnesia:change_config/2`赋值给'extra_db_nodes'强制建立连接, 即`mnesia:change_config (extra_db_nodes, NodeList)`。

mnesia会同步集群中节点上所有的表信息，如果某节点需要自己本地维护一张表而不希望共享该表，可以在创建表时指定local_content属性。

此时运行`mnesia:info()`，可以看到集群中的数据表，并且类型为remote，即远程数据库。事实上，remote可以看做mnesia集群中，表的第四种存储形式。

在添加一个节点入集群时，mnesia会尝试合并(merge)新节点和集群中的schema表，这种合并往往会在新节点已有disc_copies的schema表时失败：`{error,{merge_schema_failed,"Incompatible schema cookies. ...`

### 3. 退出集群

通过`mnesia:del_table_copy(schema, 'mynode@host')`将会把'mynode@host'移出集群，但需要先将'mynode@host'上的mnesia停止运行。如果在'mynode@host'节点上有一个磁盘驻留模式(disc_copies)，应该将整个 mnesia目录删除。可用 `mnesia:delete_schema/1` 来完成。如果 mnesia 再次在'mynode@host'节点上启动并且目录还没有被清除，mnesia 的行为是不确定的。

### 4. 添加本地备份

如果我们希望取得更快的访问速度，或者需要对远程数据库备份的话，可以通过`mnesia:add_table_copy(Tab, Node, Type)`备份远程数据库，type字段为ram_copies, disc_copies, disc_only_copies之一，但仍受限于schema(schema表为ram_copies，则本节点上其它表只能为ram_copies)。

集群中的每张表，在不同的node上，可以有不同的存储形式(remote, ram_copies, disc_copies, disc_only_copies)。通过`mnesia:info()`可以查看各个表在不同的node上的存储形式。

添加备份后，mnesia会自动同步各节点对同一张表的更新操作。

[1]: http://www.erlang.org/doc/man/mnesia.html "erlang mnesia"
[2]: http://www.erlang.org/doc/apps/mnesia/Mnesia_chap3.html "building a mnesia database"
[3]: http://www.hitb.com.cn/c/document_library/get_file?p_l_id=10190&folderId=11012&name=DLFE-1103.pdf "mnesia用户手册"
[4]: http://veniceweb.googlecode.com/svn/trunk/public/daily_tech_doc/erlang_faq_20091125.txt
