---
title: 开发笔记(3) mongodb driver
layout: post
tags: erlang
categories: erlang
---

erlang mongodb驱动地址: https://github.com/comtihon/mongodb-erlang

先说说mongodb-erlang驱动的一些特性：

- 支持atom和binary作为Key，atom最终是转换为binary进行存储的，而在读取时，驱动并不会将对应binary转换为atom(它也不知道怎么转)
- 不支持integer，string(对erlang来说是字符串，对mongodb来说是数组)作为Key
- 支持atom，binary，integer作为值，这三者的存取是透明的，不需要特殊转换，在mongodb中，atom被存为`Symbol(xxx)`
- 支持string作为值，但实际上存的是字符数组，如果想存字符串，应使用binary
- 目前最新的mongodb-erlang驱动使用erlang map来存储doc(之前版本用的是bson list)

基于游戏服务器的需求，我们希望：

- mongodb driver能够支持integer作为key
- 从模型到对象的转换是透明的，无需我们关心

<!--more-->

之前我们服务器逻辑中的数据模型是Dict，而mongodb-erlang使用的是bson-list来表示文档，在此之上做了一些比较繁杂转换。自mongodb-erlang支持map之后，我们也将数据结构由dict改为了map(PS: 非直观的是，map的效率不比dict差，参见[测试代码](https://github.com/wudaijun/Code/blob/master/erlang/map_test.erl))，如此我们需要对驱动读取的map的key value做一些类型转换。为了达到以上两点，我们对mongodb-erlang驱动做了些更改：

1. 修改mongodb-erlang的依赖[bson-erlang](https://github.com/comtihon/bson-erlang)，在src/bson_binary.erl中添加对integer key的存储支持：

		put_field_accum(Label, Value, Bin) when is_atom(Label) ->
  			<<Bin/binary, (put_field(atom_to_binary(Label, utf8), Value))/binary>>;
  		% add this line to suport integer key
		put_field_accum(Label, Value, Bin) when is_integer(Label) ->
  			<<Bin/binary, (put_field(integer_to_binary(Label), Value))/binary>>;
		put_field_accum(Label, Value, Bin) when is_binary(Label) ->
  			<<Bin/binary, (put_field(Label, Value))/binary>>.
2. 在读取时，为了支持atom key和integer key的透明转换，我们约定了服务器只使用integer和atom(不能是integer atom，如'123')作为key，这样我们可以在驱动读取完成后，进行key的自动转换：
	
		% 将Key由二进制串 转为整数或者原子
		convert_map_key(Map) when is_map(Map) ->
		  maps:fold(fun(Key, Value, NewMap) ->
		    NewKey = case catch binary_to_integer(Key) of
		      {'EXIT', {badarg, _R}} -> binary_to_atom(Key, utf8);
		      IntegerKey -> IntegerKey
		    end,
		    maps:put(NewKey, convert_map_key(Value), NewMap)
		  end, maps:new(), Map);
		
		convert_map_key(List) when is_list(List) ->
		  lists:map(fun(Elem) ->
		    convert_map_key(Elem)
		  end, List);
		
		convert_map_key(Data) -> Data.
3. 最后还有一个小问题，就是mongodb-erlang的[mongo.erl](https://github.com/comtihon/mongodb-erlang/blob/master/src/api/mongo.erl)中，在插入文档时，会自动检查文档是否包含<<"\_id">>键，如果没有，则会为其生成一个ObjectId()作为<<"\_id">>键的值，这里我们需要将其改为检查'\_id'原子键，否则我们在逻辑中创建的包含'\_id'键的文档，最终存入时，mongodb中的"\_id"键的值是驱动自动生成的ObjectId()，而不是我们定义的'_id'键的值：


		assign_id(Map) when is_map(Map) ->
		  case maps:is_key('_id', Map) of
		    true -> Map;
		    false -> Map#{'_id' => mongo_id_server:object_id()}
		  end;
		assign_id(Doc) ->
		  case bson:lookup('_id', Doc) of
		    {} -> bson:update('_id', mongo_id_server:object_id(), Doc);
		    _Value -> Doc
		  end.


现在我们已经支持integer，atom作为key，binary，integer，atom，list作为value，基于这些类型的key/value是无需我们关心模型到对象的映射转换的。对于一个游戏服务器来说，基本上已经能够满足大部分需求了。对于一些极为特殊的模块，再通过设定回调(on_create/on_init/on_save)等方式特殊处理。



