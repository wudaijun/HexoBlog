---
title: Erlang 服务器落地机制
layout: post
tags: 
- erlang
categories: erlang
---

游戏服务器中用得最多的就是gen_server，比如游戏中的Player进程，由于gen_server提供的完善的进程设施，我们无需过多地担心进程崩溃而造成的数据丢失的问题(至少还有个terminate用于做善后工作)。因此在进行数据写回时，可以通过定时写回的机制来减轻数据库负担。这一点也是C服务器望尘莫及的。

## 落地流程

落地时机应由PlayerManager触发，PlayerManager管理所有的Player进程，每隔一段时间进行数据落地。为了避免同时对所有玩家落地造成的热点，可以将Player进程简单分区，每次对其中一个区进行落地，如此轮流。

落地操作交由Player进程，因为我们的绝大部分关于Player的数据都是放在进程字典中的。

Player进程首先遍历其相关的所有Model，取出其中变化的数据，然后更新数据库。

<!--more-->

为了模块化，将相关模块描述为：

- player: 玩家进程，玩家主要业务逻辑处理，消息分发
- player_model: 业务逻辑与数据层的中间模块，负责数据初始化和落地
- state: 辅助管理所在进程的进程字典，跟踪数据变化。提供查询和更改进程字典，获取进程字典变化数据的接口。
- model: 数据层，负责和数据库交互，提供insert, update等基本接口

## 实现机制

落地实现最核心的两个模块是 player_model 和 state，前者负责Player所有数据的初始化和落地，后者负责管理Player进程字典数据，并且追踪数据的变更状态。

### player_model

player_model 建立了业务层到模型层的映射，它仅提供两个最重要的接口：init(PlayerId) 和 save(PlayerId)，分别负责Player所有模块的初始化(数据库 -> 进程字典)和落地(进程字典 -> 数据库)。

在player_model中，有所有Model的相关信息，包括名字，类型和所在模块等等。

	module_map() ->
	  [
	   {player_info, {?INFO_STATE, single}, 
	    model_user, ?model_record(db_user_info)},
	    
	    .....
	    %{业务逻辑模块, 进程字典中的Key和存储类型 single or list},
	    %{数据存储模块, 数据存储字段}
	  ]

这样业务逻辑层和Model层被关联起来，对于save来说，最重要的是第二个字段和第三个字段，分别代表该Model在进程字典的状态，以及Model名。save流程主要如下：

1. 遍历module_map()，获取各个Model数据在进程字典中变更数据
2. 根据变更状态调用对应Model接口 完成回写
3. 回写完成之后，再重置各个Model的变更状态

注意：

- 1，2步是事务性的，所有Model的回写要么都成功，要么都失败，以免各个模块数据之间的数据相关性造成数据不一致的问题。在写入成功后，再次遍历module_map()，重置各个Model的状态。
- 对于list 和 single两种类型的Model需要分开处理，它们获取变更数据和回写的接口不一样，这可能还需要Model层的支持。这一点在下面state模块介绍中会提到。

关于获取Model在进程字典中状态管理，通过state模块来管理。

### state

state模块管理进程字典中的数据，进程字典虽然为简单的Key-Value，但对于我们的Model来说，Value可能为单个记录(如玩家信息)或列表(如玩家建筑列表)。

最简单的情况是，我们单独用一个进程字典，如{Name, state}来获取Model的数据状态，数据状态可分为 origin(初始化) new(创建未保存)， update(更新) delete(删除) 在数据更新时，修改状态，在每次落地同步时，取出所有被修改的Model，并且进行落地同步。之后将数据的状态重置为origin。

然而这种做法对于list类型的Model效率太低，一是业务逻辑上的每次更改都需要改动每个数组，典型的例子是任务列表，玩家对某个任务领奖，导致整个任务列表的拷贝，还可能产生不必要的查找过程。更不可忍受的是，数据落地时，也将重写整个任务列表到数据库。

因此还有另一种方案：将list Model中的记录分开存放，并且分别标记状态，提高查找和回写效率：

	
	%% ------ list Model ----------
	
	% 存放list中各个key的状态
	{Name, list} -> [{key1, update}, {key2, delete}, ...]
	
	% 存放列表中各元素的实际数据
	{Name, Key} ->	Data
	
	% 存放被删除的元素列表(将不能通过{Name, Key}找到)
	{Name, delete} -> [DeleteData1, DeleteData2, ....]
	
	%% ------- single Model -------
	
	% 通过 Name 存取
	Name -> Value
	
	% 存放Model的更改状态
	{Name, state} -> State
	
如此便对Model进行了高效灵活的管理，大大减少了回写数据量。

state封装了进程字典的增删查改操作，并维护进程字典状态。

读取直接通过`erlang:get(Name, Key)`，对于任务列表来说，这个Key通常是任务ID

更新时：

对于列表:

1. 通过{Name, list}检查更新Key的状态
2. 对{Name, Key}执行修改
3. 对于删除操作，还需要将删除的数据放入{Name, delete}中

对于单值:

1. 通过{Name, state}检查修改状态
2. 对Name执行修改

落地相关接口：

	% 获取list Model中的变更数据
	% 返回: {InsertList, UpdateList, DeleteList}
	get_list_changed(Name)

	% 获取single Model中的数据状态
	% 返回: {State, Value}
	get_single_changed(Name)

	% 重置list Model中的数据状态为origin 并且删除所有状态为delete的数据
	reset_list(Name)
	
	% 重置single Model
	reset_single(Name)

player_mode根据module_map中的条目依次获取变更数据，在使用model模块更新时，可让model模块也提供对single和list两种类型回写的支持。提供各个Model的特殊化处理，如有些Model可以忽略删除列表。

## 数据加载

最后再谈谈关于这套框架的数据加载，player_model提供一个init(PlayerId)完成数据的加载，module_map中业务逻辑模块到数据Model层的映射，也是为此准备的。

player_model遍历module_map，调用Model:get(PlayerId)，取出各个Model的数据，然后通过module_map找到对应的业务逻辑模块，回调业务逻辑层初始化函数，该函数可默认指定，比如叫init_callback，每个module_map中的业务逻辑模块都需要提供init_callback进行初始化处理，如同步客户端等等，之后也由init_callback决定是否将数据存往进程字典(通过state模块)。
