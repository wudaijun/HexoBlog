---
title: Erlang Map映射到Record
layout: post
categories: erlang
tags: erlang

---

在游戏服务器中，通常要面临对象到模型的映射，以及对象到协议的映射，前者用于GS和DB交互，后者用于GS和Client交互。我们的项目中做到了[对象到模型的自动映射](http://wudaijun.com/2015/11/erlang-server-design3-mongodb-driver/)，这样在开发过程中无需关心GS和DB的交互，很方便。

而现在我们还没有实现对象(map)到协议(record)的自动映射，我觉得这个特性是比较有用的，特别是在同步一些实体数据的时候。无需写一堆Packer函数来将对象数据打包为协议。因此就研究了一下如何将map的数据自动映射到[protobuffer](https://github.com/basho/erlang_protobuffs)，也就是转换为record。

<!--more-->

我希望实现一个接口：

```
% RecordName: 	type:atom, 协议名字 如hero
% MapData:		type:map,  对象数据
% RecordData:	type:tuple, 被转换后的协议包
map2record(RecodName, MapData) -> RecordData.

如：
> rd(hero, {id, level, star}).
> HeroMap = #{id => 1, level => 2, star => 3}.
> {hero, 1, 2, 3} = map2record(hero, HeroMap).
```
在实际使用中，还应该考虑到protobuffer中的嵌套结构，map2record应该能够实现嵌套结构，repeated字段的自动解析。

### 实现

#### 1. 识别record

由于record类型在erlang运行时并不存在，因此我们无法判断一个原子是否是record，也无法获取它的字段。因此需要实现`is_record/1`和`record_fields/1`接口。

在网上找到[这篇博客](http://jixiuf.github.io/erlang/record_info.html)为此提供了一个很好的解决方案。它通过[erlang epp](http://www.erlang.org/doc/man/epp.html)模块对record定义进行语义级的解析，并且手动生成我们所需要的函数。我只需要其中的`record_fields`接口，并对`is_record`接口进行了一些修改，让其判断一个原子是否是一个record名字，而不是判断一个数据是不是record类型。

#### 2. 填充record

填充比较简单，参见代码：

```
{% codeblock lang:erlang %}
-module(map2record).

-export([auto_transfer/2]).

auto_transfer(RecordName, MapData) ->
  case {myhead_util:is_record(RecordName), is_list(MapData)} of
    {true, true} ->
      lists:map(fun(SubData) ->
        auto_transfer(RecordName, SubData)
      end, MapData);
    {true, false} ->
      Fields = myhead_util:fields_info(RecordName),
      Values = lists:map(fun(Field) ->
        auto_transfer(Field, maps:get(Field, MapData, undefined))
      end, Fields),
      list_to_tuple([RecordName|Values]);
    {false, _} ->
      MapData 
  end.
{% end codeblock %}
```
整个填充需要满足一些条件，

- record中的field名字要和map中的key一致
- repeated字段，在map中的值，也应该是个list
- 对于嵌套record，字段名应该为被嵌套的record名字

举个例子：

```
// 协议文件
message hero{
	required int32 id              = 1;
	required hero_base hero_base   = 2;
	repeated hero_skill hero_skill = 3;
}

// 那么内测中的HeroMap应该是这样：
#{	
    id          => 1,
    hero_base   => #{ ... }
    hero_skill  => [#{...}, #{...}]
}
```

### 结语

完整代码参见Github: https://github.com/wudaijun/erl_utils/tree/master/map2record

由于我们项目中大部分列表型实体都被组织成了譬如skill_id => SkillData的map，因此在项目中并没有采用这份方案，也不知具体实践会遇到什么问题。暂时只当个map2record的工具吧。