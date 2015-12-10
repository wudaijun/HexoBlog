---
title: Erlang 常用数据结构实现
layout: post
tags: erlang
categories: erlang

---

简单介绍一下Erlang常用数据结构的内部实现和特性，主要参考[Erlang OTP 18.0][erlang_otp_18_src]源码，和网上很多优秀博客(参见附录)，原创并不多，整理了一些自己项目中常用到的。

Erlang虚拟机使用一个字(64/32位)来表示所有类型的数据，即Eterm。具体的实施方案通过占用Eterm的后几位作为类型标签，然后根据标签类型来解释剩余位的用途。这个标签是多层级的，最外层占用两位，有三种类型：

- 01: list，剩下62位是指向列表Cons的指针
- 10: boxed对象，即复杂对象，剩余62位指向boxed对象的对象头。包括元组，大整数，外部Pid/Port等
- 11: immediate立即数，即可以在一个字中表示的小型对象，包括小整数，本地Pid/Port，Atom，NIL等


这三种类型是Erlang类型的大框架，前两者是可以看做是引用类型，立即数相当于是值类型，**但无论对于哪种类型，Erlang Eterm均用一个字表示所有数据结构**，理解这一点是很重要的。

<!-- more -->

对于二三级标签的细分和编码，一般我们无需知道这些具体的底层细节，对于我们常用的类型，以下几点是值得注意的：

### 一. 常用类型

#### 1.Pid/Port

本地进程Pid可直接用立即数表示，但当将Pid发往其它node时，Erlang会自动将为Pid加上本地节点信息，并打包为一个boxed对象，占用6个字。另外，Erlang需要维护Pid表，每个条目占8个字节，当进程数量过大时，Pid表将占用大量内存，Erlang默认可以使用18位有效位来表示Pid，可通过+P参数调节，最大值为28，此时Pid表占用内存为2G

#### 2. atom

atom用立即数表示，依赖于高效的哈希和索引表，Erlang的atom比较像整数一样高效，但是atom表是不回收的，并且默认最大值为1024*1024，超过这个限制Erlang虚拟机将会崩溃，可通过+t参数调整该上限。

#### 3. list

列表以标签01标识，剩余62位指向列表的Cons单元，Cons是[Head|Tail]的组合，在内存中体现为两个相邻的Eterm，Head可以是任何类型的Eterm，Tail是列表类型的Eterm。因此形如`L2 = [Elem|L1]`的操作，实际上构造了一个新的Cons，其中Head是Elem Eterm，Tail是L1 Eterm，然后将L2的Eterm指向了这个新的Cons，因此L2即代表了这个新的列表。对于`[Elem|L2] = L1`，实际上是提出了L1 Eterm指向的Cons，将Head部分赋给Elem，Tail部分赋给L2，注意Tail本身就是个List的Eterm，因此list是单向列表，并且构造和提取操作是很高效的。需要再次注意的是，Erlang所有类型的Eterm本身只占用一个字大小。这也是诸如list,tuple能够容纳任意类型的基础。

Erlang中进程内对对象的重复引用只需占用一份对象内存(只是Eterm本身一个字的拷贝)，但是在对象跨进程时，对象会被展开，执行速深度拷贝：

	Eshell V7.0.2  (abort with ^G)
	1> L1 = [1,2,3].
	[1,2,3]
	2> erts_debug:size(L1).		  
	6
	3> L2 = [L1,L1,L1].
	[[1,2,3],[1,2,3],[1,2,3]]
	4> erts_debug:size(L2).		  % 获得L2对象树的大小 3*2+6
	12
	5> erts_debug:flat_size(L2). 	% 获得对象平坦展开后的大小 3*(2+6)
	24
	6> P1 = spawn(fun() -> receive L -> io:format("~p~n",[erts_debug:size(L)]) end end).
	<0.45.0>
	7> P1 ! L2.					  % 在跨进程时，对象被展开 执行深度拷贝
	24
	[[1,2,3],[1,2,3],[1,2,3]]

#### 4. tuple

tuple属于boxed对象的一种，每个boxed对象都有一个对象头(header)，boxed Eterm即指向这个header，这个header里面包含具体的boxed对象类型，如tuple的header末6位为000000，前面的位数为tuple的size：

![](/assets/image/erlang/erlang_tuple_format.png "")

tuple实际上就是一个有头部的数组，其包含的Eterm在内存中紧凑排列，tuple的操作效率和数组是一致的。

list和tuple是erlang中用得最多的数据结构，也是其它一些数据结构的基础，如record，map，摘下几个关于list，tuple操作的常用函数，便于加深对结构的理解：

	 {% codeblock lang:c %} 
	// 位于 $OTP_SRC/erts/emulator/beam/bif.c
	BIF_RETTYPE tuple_to_list_1(BIF_ALIST_1)
	{
	    Uint n;
	    Eterm *tupleptr;
	    Eterm list = NIL;
	    Eterm* hp;
	
	    if (is_not_tuple(BIF_ARG_1))  {
		BIF_ERROR(BIF_P, BADARG);
	    }
	
		// 得到tuple Eterm所指向的tuple对象头
	    tupleptr = tuple_val(BIF_ARG_1);
	    // 得到对象头中的tuple size		    
	    n = arityval(*tupleptr);
	    hp = HAlloc(BIF_P, 2 * n);
	    tupleptr++;
	
		// 倒序遍历 因为list CONS的构造是倒序的
	    while(n--) {
	    // 相当于hp[0]=tupleptr; hp[1] = list; make_list(hp);
	    // 最后返回的是指向hp的list Eterm
		list = CONS(hp, tupleptr[n], list);
		hp += 2;
	    }
	    BIF_RET(list);
	}
	
	BIF_RETTYPE list_to_tuple_1(BIF_ALIST_1)
	{
	    Eterm list = BIF_ARG_1;
	    Eterm* cons;
	    Eterm res;
	    Eterm* hp;
	    int len;
	
	    if ((len = erts_list_length(list)) < 0 || len > 		ERTS_MAX_TUPLE_SIZE) {
		BIF_ERROR(BIF_P, BADARG);
	    }
		// 元素个数 + 对象头
	    hp = HAlloc(BIF_P, len+1);
	    res = make_tuple(hp);
	    *hp++ = make_arityval(len);
	    while(is_list(list)) {
		cons = list_val(list);
		*hp++ = CAR(cons);
		list = CDR(cons);
	    }
	    BIF_RET(res);
	}
	{% endcodeblock %}
	
可以看到，list，tuple中添加元素，实际上都是在拷贝Eterm本身，Erlang虚拟机会追踪这些引用，并负责垃圾回收。

### 二. 复合类型

基于list和tuple之上，Erlang还提供了一些其它的数据结构，这里列举几个key/value相关的数据结构，在服务器中会经常用到。

#### 1. record

这个类型无需过多介绍，它就是一个tuple，所谓record filed在预编译后实际上都是通过数值下标来索引，因此它访问field是O(1)复杂度的。
#### 2. map

虽然record的语法糖让我们在使用tuple时便利了不少，但是比起真正的key/value结构仍然有许多限制，如key只能是原子，key不能动态添加或删除，record变动对热更的支持很差等。proplists能够一定程度地解决这种问题，但是它适合键值少的情况，通常用来做选项配置，并且不能保证key的唯一。

map是OTP 17引进的数据结构，是一个boxed对象，它支持任意类型的Key，模式匹配，动态增删Key等，并且最新的[mongodb-erlang][mongodb-erlang]直接支持map。

map的内存结构为：

	 {% codeblock lang:c %} 
	//位于 $OTP_SRC/erts/emulator/beam/erl_map.h
	typedef struct flatmap_s {
	    Eterm thing_word;	// 	boxed对象header
	    Uint  size;			// 	map 键值对个数
	    Eterm keys;      	// 	keys的tuple
	} flatmap_t;
	{% endcodeblock %}

该结构体之后就是依次存放的Value，因此maps的find操作，需要先遍历keys tuple，找到key所在下标，然后在value中取出该下标偏移对应的值。因此是O(n)复杂度的。参见maps:find源码：

	 {% codeblock lang:c %} 
	//位于 $OTP_SRC/erts/emulator/beam/erl_map.h
	erts_maps_get(Eterm key, Eterm map)
	{
	    Uint32 hx;
	    if (is_flatmap_rel(map, map_base)) {
			Eterm *ks, *vs;
			flatmap_t *mp;
			Uint n, i;
		
			mp  = (flatmap_t *)flatmap_val_rel(map, map_base);
			n   = flatmap_get_size(mp);
		
			if (n == 0) {
			    return NULL;
			}
			// 取出keys tuple 跳过tuple boxed header
			ks  = (Eterm *)tuple_val_rel(mp->keys, map_base) + 1;
			// 取出 values起始地址 偏移为flatmap_t的大小
			// #define flatmap_get_values(x) (((Eterm *)(x)) + 3)
			vs  = flatmap_get_values(mp);
			
			// 如果key是立即数 直接比较
			if (is_immed(key)) {
			    for (i = 0; i < n; i++) {
					if (ks[i] == key) {
					    return &vs[i];
					}
			    }
			}
			// 否则通过eq_rel比较 Eterm
			for (i = 0; i < n; i++) {
			    if (eq_rel(ks[i], map_base, key, NULL)) {
					return &vs[i];
			    }
			}
			return NULL;
	    }
	    ASSERT(is_hashmap_rel(map, map_base));
	    hx = hashmap_make_hash(key);
	
	    return erts_hashmap_get_rel(hx, key, map, map_base);
	}
	{% endcodeblock %}

实际使用中，maps效率还是非常高的，[这里][map_test]有一份maps和dict的简单测试函数，通常情况下，我们应当优先使用maps，比起dict，它在模式匹配，mongodb支持，可读性上都有很大优势。

#### 3. array

Erlang有个叫array的结构，其名字容易给人误解，它有如下特性：

1. array下标从0开始
2. array有两种模式，一种固定大小，另一种按需自动增长大小，但不会自动收缩
3. 支持稀疏存储，执行array:set(100,value,array:new())，那么[0,99]都会被设置为默认值(undefined)，该默认值可修改。

在实现上，array最外层被包装为一个record:

	 {% codeblock lang:erlang %} 
	-record(array, {
		size :: non_neg_integer(),	%% number of defined entries
		max  :: non_neg_integer(),	%% maximum number of entries
		default,	%% the default value (usually 'undefined')
	    elements :: elements(_)     %% the tuple tree
	}).
	{% endcodeblock %}
	
elements是一个tuple tree，即用tuple包含tuple的方式组成的树，叶子节点就是元素值，元素默认以10个为一组，亦即完全展开的情况下，是一颗十叉树。但是对于没有赋值的节点，array用其叶子节点数量代替，并不展开：

	Eshell V7.0.2  (abort with ^G)
	1> array:set(9,value,array:new()).
	{array,10,10,undefined, % 全部展开
	       {undefined,undefined,undefined,undefined,undefined,
	undefined,undefined,undefined,undefined,value}}
	
	% 只展开了19所在的子树 其它9个节点未展开 
	% 注意tuple一共有11个元素，最后一个元素代表本层节点的基数，这主要是出于效率考虑，能够快速检索到元素所在子节点
	2> array:set(19,value,array:new()).
	{array,20,100,undefined,
	       {10,		
	        {undefined,undefined,undefined,undefined,undefined，	undefined,undefined,undefined,undefined,value},
	        10,10,10,10,10,10,10,10,10}}
	
	% 逐级展开了199所在的子树
	3> array:set(199,value,array:new()).
	{array,200,1000,undefined,
	       {100,
	        {10,10,10,10,10,10,10,10,10,
	         {undefined,undefined,undefined,undefined,undefined,
	 undefined,undefined,undefined,undefined,value},
	         10},
	        100,100,100,100,100,100,100,100,100}}
	4>

由于完全展开的tuple tree是一颗完全十叉树，因此实际上array的自动扩容也是以10为基数的。在根据Index查找元素时，通过div/rem逐级算出Index所属节点:

	 {% codeblock lang:erlang %} 
	%% 位于$OTP_SRC/lib/stdlib/src/array.erl
	get(I, #array{size = N, max = M, elements = E, default = D})
	  when is_integer(I), I >= 0 ->
	    if I < N ->		% 有效下标
		    get_1(I, E, D);
	       M > 0 ->		% I>=N 并且 array处于自动扩容模式 直接返回DefaultValue 
		    D;
	       true ->		% I>=N 并且 array为固定大小  返回badarg
		    erlang:error(badarg)
	    end;
	get(_I, _A) ->
	    erlang:error(badarg).
	
	%% The use of NODEPATTERN(S) to select the right clause is just a hack,
	%% but it is the only way to get the maximum speed out of this loop
	%% (using the Beam compiler in OTP 11).
	
	% -define(NODEPATTERN(S), {_,_,_,_,_,_,_,_,_,_,S}). % NODESIZE+1 elements!
	get_1(I, E=?NODEPATTERN(S), D) ->		% 到达已展开的中间节点 向下递归
	    get_1(I rem S, element(I div S + 1, E), D);
	get_1(_I, E, D) when is_integer(E) ->	% 到达未展开的中间节点 返回默认值
	    D;
	get_1(I, E, _D) ->						% 到达叶子节点层
	    element(I+1, E).

	set(I, Value, #array{size = N, max = M, default = D, elements = E}=A)
	  when is_integer(I), I >= 0 ->
	    if I < N ->
		    A#array{elements = set_1(I, E, Value, D)};
	       I < M ->		% 更新size, size的主要作用是让读取更加高效 
		    %% (note that this cannot happen if M == 0, since N >= 0)
		    A#array{size = I+1, elements = set_1(I, E, Value, D)};
	       M > 0 ->		% 自动扩容
		    {E1, M1} = grow(I, E, M),
		    A#array{size = I+1, max = M1,
			    elements = set_1(I, E1, Value, D)};
	       true ->
		    erlang:error(badarg)
	    end;
	set(_I, _V, _A) ->
	    erlang:error(badarg).
	
	%% See get_1/3 for details about switching and the NODEPATTERN macro.
	
	set_1(I, E=?NODEPATTERN(S), X, D) ->		% 所在节点已展开，向下递归
	    I1 = I div S + 1,
	    setelement(I1, E, set_1(I rem S, element(I1, E), X, D));
	set_1(I, E, X, D) when is_integer(E) ->	% 所在节点未被展开，递归展开节点 并赋值
	    expand(I, E, X, D);
	set_1(I, E, X, _D) ->						% 到达叶子节点
	    setelement(I+1, E, X).
	{% endcodeblock %}

更多细节可以参见源码，了解了这些之后，再来看看Erlang array和其它语言数组不一样的地方：

- 索引不是O(1)复杂度，而是O(log10n)
- array并不自动收缩
- array中的max和size字段，和array具体占用内存没多大关系(节点默认未展开)
- array中并没有subarray之类的操作，因为它根本不是线性存储的，而是树形的，因此如果用它来做递归倒序遍历之类的操作，复杂度不是O(n)，而是O(n*log10n)
- array中对于没有赋值的元素，给予默认值undefined，这个默认值可以在array:new()中更改，对使用者来说，明确赋值undefined和默认值undefined并无多大区别，但对array内部来说，可能会导致节点展开。

### 三. 参考

1. Erlang数据结构实现文章汇总: http://www.iroowe.com/erlang_eterm_implementation/
2. [zhengsyao] Erlang系列精品博客: http://www.cnblogs.com/zhengsyao/category/387871.html
3. [坚强2002] Erlang array: http://www.cnblogs.com/me-sa/archive/2012/06/14/erlang-array.html


[mongodb-erlang]: https://github.com/comtihon/mongodb-erlang
[map_test]: https://github.com/wudaijun/Code/blob/master/erlang/map_test.erl
[erlang_otp_18_src]: http://www.erlang.org/download_release/29