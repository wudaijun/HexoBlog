---
title: Erlang mongodb
layout: post
tags: erlang
categories: erlang
---

erlang mongodb驱动地址: https://github.com/comtihon/mongodb-erlang

<!--more-->

**1. 存取**

首先，该驱动不支持将List和Integer作为Key，事实上，它将erlang中List看做数组而不是字符串：

	mongo:insert(Connection, Collection, {"key1", value1})      % ERROR
	mongo:insert(Connection, Collection, {1, value1})           % ERROR
	 					
	mongo:insert(Connection, Collection, {key1, value1})        % OK
	mongo:insert(Connection, Collection, {<<"key1"">>, value1}) % OK
	
其次，我们在存List作为Value时，实际上存入mongodb的是一个整数数组：

	mongo:insert(Connection, Collection, {key1, "abc"}) % in mongdb: {"key1":[97,98,99]}
	
	以下方式可将Value正确保存为字符串:
	mongo:insert(Connection, Collection, {key1, abc})
	mongo:insert(Connection, Collection, {key1, bson:utf8("abc")})
	mongo:insert(Connection, Collection, {key1, <<"abc">>})
	
而在游戏开发逻辑中，我们市场会遇到integer作为key的的情况，因此就需要在Mongodb的存取层做一次转换，落地时integer_to_atom，加载时尝试atom_to_integer(需要捕获异常)。

**2. 转换**

从mongodb读出的数据是bson格式的：{key1, value1, key2, {key21, value21}, ...}`，需要执行到逻辑层数据结构的转换，比如逻辑层将mongodb的一个Doc对应一个Dict，则需要完成Bson到Dict之间的转换：

```
dict_to_bson(Dict) ->
  List = dict:to_list(Dict),
  parse_list(List, []).

parse_list([], List) ->
  bson:document(List);
parse_list([{Key, Val} | RestList], List) ->
  DBKey = dbkey(Key),
  case catch dict:is_empty(Val) of
    {'EXIT', {function_clause, _R}} ->
      parse_list(RestList, [{DBKey, Val} | List]);
    _ ->
      ParsedList = dict_to_bson(Val),
      parse_list(RestList, [{DBKey, ParsedList} | List])
  end.

% 1 -> '1'
dbkey(Key) when is_integer(Key) ->
  misc:integer_to_atom(Key);
dbkey(Key) ->
  Key.


bson_to_dict(Doc) ->
  FieldList = bson:fields(Doc),
  parse_fields(FieldList, dict:new()).

parse_fields([], Dict) -> Dict;
parse_fields([{Key, Val} | RestFields], Dict) ->
  NewDict = dict:store(dictkey(Key), Val, Dict),
  parse_fields(RestFields, NewDict).

% '1' -> 1
dictkey(Key) when is_atom(Key) ->
  case catch misc:atom_to_integer(Key) of
    {'EXIT', {badarg, _R}} -> Key;
    DictKey -> DictKey
  end;
dictkey(Key) ->
  Key.
```

上面的转换并不是完美的，对于dict_to_bson，可以深度递归解析出完整的Bson，而对于bson_to_dict，只能解析最外一层，因为对于一个bson格式tuple，你无法判断逻辑层是使用为dict还是bson tuple本身，除非和逻辑层有这样一种约定: 应用层使用的dict中的key不能是tuple，这样bson_to_dict中，只要看到tuple，就转换为dict。否则只能自定义二级Bson解析。



