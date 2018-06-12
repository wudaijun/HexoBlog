---
title: Erlang 常用数据结构实现
layout: post
tags: erlang
categories: erlang

---

简单介绍一下Erlang常用数据结构的内部实现和特性，主要参考[Erlang OTP 18.0][erlang_otp_18_src]源码，和网上很多优秀博客(参见附录)，整理了一些自己项目中常用到的。

Erlang虚拟机使用一个字(64/32位)来表示所有类型的数据，即Eterm。具体的实施方案通过占用Eterm的后几位作为类型标签，然后根据标签类型来解释剩余位的用途。这个标签是多层级的，最外层占用两位，有三种类型：

- 01: list，剩下62位是指向列表Cons的指针
- 10: boxed对象，即复杂对象，剩余62位指向boxed对象的对象头。包括元组，大整数，外部Pid/Port等
- 11: immediate立即数，即可以在一个字中表示的小型对象，包括小整数，本地Pid/Port，Atom，NIL等


这三种类型是Erlang类型的大框架，前两者是可以看做是引用类型，立即数相当于是值类型，**但无论对于哪种类型，Erlang Eterm本身只占用一个字**，理解这一点是很重要的。

<!-- more -->

对于二三级标签的细分和编码，一般我们无需知道这些具体的底层细节，以下是几种常用的数据结构实现方式。

## 一. 常用类型

### 1. atom

atom用立即数表示，在Eterm中保存的是atom在全局atom表中的索引，依赖于高效的哈希和索引表，Erlang的atom比较和匹配像整数一样高效。atom表是不回收的，并且默认最大值为1024*1024，超过这个限制Erlang虚拟机将会崩溃，可通过`+t`参数调整该上限。

### 2.Pid/Port

	/*  erts/emulator/beam/erl_term.h

	 *
	 *  Old pid layout(R9B及之前):
	 *  
	 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	 *   |s s s|n n n n n n n n n n n n n n n|N N N N N N N N|c c|0 0|1 1|
	 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	 *
	 *  s : serial  每次n到达2^15之后 自增一次 然后n重新从低位开始
	 *  n : number  15位, 进程在本地进程表中的索引
	 *  c : creation 每次节点重启，该位自增一次
	 *  N : node number 节点名字在atom表中索引
	 *
	 *
	 *  PID layout (internal pids):
	 *
	 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	 *   |n n n n n n n n n n n n n n n n n n n n n n n n n n n n|0 0|1 1|
	 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	 *
	 *  n : number 28位进程Pid
	 */

在Old Pid表示中(R9B及之前版本)，在32位中表示了整个Pid，包括其节点名字等信息，也就是本地进程和外部进程都可以用Eterm立即数表示，显示格式为`<N, n, s>`。

在R9B之后，随着进程数量增加和其它因素，Pid只在32位中表示本地Pid(A=0)，将32位中除了4位Tag之外的28位，都可用于进程Pid表示，出于Pid表示的历史原因，仍然保留三段式的显示，本地Pid表示变成了`<0, Pid低15位, Pid高13位>`。对于外部Pid，采用boxed复合对象表示，在将本地Pid发往其它node时，Erlang会自动将为Pid加上本地节点信息，并打包为一个boxed对象，占用6个字。另外，Erlang需要维护Pid表，每个条目占8个字节，当进程数量过大时，Pid表将占用大量内存，Erlang默认可以使用18位有效位来表示Pid(262144)，可通过+P参数调节，最大值为27位(2^27-1)，此时Pid表占用内存为2G。

```erlang
Eshell V8.1  (abort with ^G)
(n1@T4F-MBP-11)1> node().
'n1@T4F-MBP-11'
% 节点名的二进制表示
(n1@T4F-MBP-11)2> term_to_binary(node()).
<<131,100,0,13,110,49,64,84,52,70,45,77,66,80,45,49,49>>
(n1@T4F-MBP-11)3> self().
<0.63.0>
% term_to_binary会将A对应的节点名编码进去
(n1@T4F-MBP-11)4> term_to_binary(self()).
<<131,103,100,0,13,110,49,64,84,52,70,45,77,66,80,45,49,
  49,0,0,0,63,0,0,0,0,2>>
(n1@T4F-MBP-11)5>
```


### 3. lists

列表以标签01标识，剩余62位指向列表的Cons单元，Cons是[Head|Tail]的组合，在内存中体现为两个相邻的Eterm，Head可以是任何类型的Eterm，Tail是列表类型的Eterm。因此形如`L2 = [Elem|L1]`的操作，实际上构造了一个新的Cons，其中Head是Elem Eterm，Tail是L1 Eterm，然后将L2的Eterm指向了这个新的Cons，因此L2即代表了这个新的列表。对于`[Elem|L2] = L1`，实际上是提出了L1 Eterm指向的Cons，将Head部分赋给Elem，Tail部分赋给L2，注意Tail本身就是个List的Eterm，因此list是单向列表，并且构造和提取操作是很高效的。需要再次注意的是，Erlang所有类型的Eterm本身只占用一个字大小。这也是诸如list,tuple能够容纳任意类型的基础。

Erlang中进程内对对象的重复引用只需占用一份对象内存(只是Eterm本身一个字的拷贝)，但是在对象跨进程时，对象会被展开，执行速深度拷贝：

```erlang
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
```
	
此时L1, L2的内存布局如下：

![](/assets/image/201512/erlang_lists_sample.png "")

### 4. tuple

tuple属于boxed对象的一种，每个boxed对象都有一个对象头(header)，boxed Eterm即指向这个header，这个header里面包含具体的boxed对象类型，如tuple的header末6位为000000，前面的位数为tuple的size：

![](/assets/image/201512/erlang_tuple_format.png "")

tuple实际上就是一个有头部的数组，其包含的Eterm在内存中紧凑排列，tuple的操作效率和数组是一致的。

list和tuple是erlang中用得最多的数据结构，也是其它一些数据结构的基础，如record，map，摘下几个关于list，tuple操作的常用函数，便于加深对结构的理解：
```c
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
    // 相当于hp[0]=tupleptr[n]; hp[1] = list; list = make_list(hp);
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
```
	
可以看到，list，tuple中添加元素，实际上都是在拷贝Eterm本身，Erlang虚拟机会追踪这些引用，并负责垃圾回收。

### 5. binary

Erlang binary用于处理字节块，Erlang其它的数据结构(list,tuple,record)都是以Eterm为单位的，用于处理字节块会浪费大量内存，如"abc"占用了7个字(加上ETerm本身)，binary为字节流提供一种操作高效，占用空间少的解决方案。

之前我们介绍的数据结构都存放在Erlang进程堆上，进程内部可以使用对象引用，在对象跨进程传输时，会执行对象拷贝。为了避免大binary跨进程传输时的拷贝开销，Erlang针对binary作出了优化，将binary分为小binary和大binary。

#### heap binary

小于64字节(定义于erl_binary.h `ERL_ONHEAP_BIN_LIMIT`宏)的小binary直接创建在进程堆上，称为heap binary，heap binary是一个boxed对象：

```c
typedef struct erl_heap_bin {
    Eterm thing_word;		/* Subtag HEAP_BINARY_SUBTAG. */
    Uint size;				/* Binary size in bytes. */
    Eterm data[1];			/* The data in the binary. */
} ErlHeapBin;
```

#### refc binary

大于64字节的binary将创建在Erlang虚拟机全局堆上，称为refc binary(reference-counted binary)，可被所有Erlang进程共享，这样跨进程传输只需传输引用即可，虚拟机会对binary本身进行引用计数追踪，以便GC。refc binary需要两个部分来描述，位于全局堆的refc binary数据本身和位于进程堆的binary引用(称作proc binary)，这两种数据结构定义于global.h中。下图描述refc binary和proc binary的关系：

![](/assets/image/201512/erlang_refc_binary.png "")

所有的OffHeap(进程堆之外的数据)被组织为一个单向链表，进程控制块(erl_process.h struct process)中的`off_heap`字段维护链表头和所有OffHeap对象的总大小，当这个大小超过虚拟机阀值时，将导致一次强制GC。注意，refc binary只是OffHeap对象的一种，以后可扩展其它种类。


#### sub binary

sub binary是Erlang为了优化binary分割的(如`split_binary/2`)，由于Erlang变量不可变语义，拷贝分割的binary是效率比较底下的做法，Erlang通过sub binary来复用原有binary。ErlSubBin定义于`erl_binary.h`，下图描述`split_binary(ProBin, size1)`返回一个ErlSubBin二元组的过程：

![](/assets/image/201512/erlang_sub_binary.png "")

ProBin的size可能小于refc binary的size，如上图中的size3，这是因为refc binary通常会通过预分配空间的方式进行优化。

要注意的是，sub binary只引用proc binary(通过orig)，而不直接引用refc binary，因此图中refc binary的refc字段仍然为1。只要sub binary还有效，对应的proc binary便不会被GC，refc binary的计数也就不为0。

#### bit string

当我们通过如`<<2:3,3:6>>`的位语法构建binary时，将得到`<<65,1:1>>`这种非字节对齐的数据，即二进制流，在Erlang中被称为bitstring，Erlang的bitstring基于ErlSubBin结构实现，此时bitsize为最后一个字节的有效位数，size为有效字节数(不包括未填满的最后一个字节)，对虚拟机底层来说，sub bianry和bit string是同一种数据结构。

#### binary追加构造优化

在通过`C = <<A/binary,B/binary>>`追加构造binary时，最自然的做法应当是创建足够空间的C(heap or refc)，再将A和B的数据拷贝进去，但Erlang对binary的优化不止于此，它使用refc binary的预留空间，通过追加的方式提高大binary和频繁追加的效率。

```erlang
Bin0 = <<0>>,                    %% 创建一个heap binary Bin0
Bin1 = <<Bin0/binary,1,2,3>>,    %% 追加目标不是refc binary，创建一个refc binary，预留256字节空间，用Bin0初始化，并追加1,2,3
Bin2 = <<Bin1/binary,4,5,6>>,    %% 追加目标为refc binary且有预留空间 直接追加4,5,6
Bin3 = <<Bin2/binary,7,8,9>>,    %% 同样，将7,8,9追加refc binary预留空间
Bin4 = <<Bin1/binary,17>>,       %% 此时不能直接追加，否则会覆盖Bin2内容，虚拟机会通过某种机制发现这一点，然后将Bin1拷贝到新的refc binary，再执行追加
{Bin4,Bin3}
	
% 通过erts_get_internal_state/1可以获取binary状态
% 对应函数源码位于$BEAM_SRC/erl_bif_info.c erts_debug_get_internal_state_1
f() ->
	B0 = <<0>>,
	erts_debug:set_internal_state(available_internal_state,true), % 打开内部状态获取接口 同一个进程只需执行一次
	f2(B0). % 通过参数传递B0 是为了避免虚拟机优化 直接构造B1为heap binary

f2(B0) ->
  io:format("B0: ~p~n", [erts_debug:get_internal_state({binary_info,B0})]),
  B1 = <<B0/binary, 1,2,3>>,
  io:format("B1: ~p~n", [erts_debug:get_internal_state({binary_info,B1})]),
  B2 = <<B1/binary, 4,5,6>>,
  io:format("B2: ~p~n", [erts_debug:get_internal_state({binary_info,B2})]),
  ok.
	
% get_internal_state({binary_info, B})返回格式:
% proc binary：{refc_binary, pb_size, {binary, orig_size}, pb_flags}
% heap binary：heap_binary
B0: heap_binary
B1: {refc_binary,4,{binary,256},3}
B2: {refc_binary,7,{binary,256},3}
```
	
binary追加实现源码位于`$BEAM_SRC/erl_bits.c erts_bs_append`，B1和B2本身是sub binary，基于同一个ProcBin，可追加的refc binary只能被一个ProcBin引用，这是因为可追加refc binary可能会在追加过程中重新分配空间，此时要更新ProcBin引用，而refc binary无法快速追踪到其所有ProcBin引用(只能遍历)，另外，多个ProcBin上的sub binary可能对refc binary覆写。

只有最后追加得到的sub binary才可执行快速追加(通过sub binary和对应ProBin flags来判定)，否则会拷贝并分配新的可追加refc binary。所有的sub binary都是指向ProcBin或heap binary的，不会指向sub binary本身。

![](/assets/image/201512/erlang_binary_append.png "")

#### binary降级

Erlang通过追加优化构造出的可追加refc binary通过空间换取了效率，并且这类refc binary只能被一个proc binary引用(多个proc binary上的sub binary会造成覆写，注意，前面的B1，B2是sub binary而不是ProBin)。比如在跨进程传输时，原本只需拷贝ProBin，但对可追加的refc binary来说，不能直接拷贝ProBin，这时需对binary降级，即将可追加refc binary降级为普通refc binary：

	bs_emasculate(Bin0) ->
    Bin1 = <<Bin0/binary, 1, 2, 3>>,
    NewP = spawn(fun() -> receive _ -> ok end end),
    io:format("Bin1 info: ~p~n", [erts_debug:get_internal_state({binary_info, Bin1})]),
    NewP ! Bin1,
    io:format("Bin1 info: ~p~n", [erts_debug:get_internal_state({binary_info, Bin1})]),
    Bin2 = <<Bin1/binary, 4, 5, 6>>, % Bin1被收缩 这一步会执行refc binary拷贝
    io:format("Bin2 info: ~p~n", [erts_debug:get_internal_state({binary_info, Bin2})]),
    Bin2.
    
    % 运行结果
    117> bs_emasculate(<<0>>).
	Bin1 info: {refc_binary,4,{binary,256},3}
	Bin1 info: {refc_binary,4,{binary,4},0}
	Bin2 info: {refc_binary,7,{binary,256},3}
	<<0,1,2,3,4,5,6>>

降级操作会重新创建一个普通的refc binary(原有可追加refc binary会被GC?)，同时，降级操作会将B1的flags置0，这保证基于B1的sub binary在执行追加时，会重新拷贝分配refc binary。

	// 降级函数($BEAM_SRC/erl_bits.c)
	void erts_emasculate_writable_binary(ProcBin* pb)
	{
	    Binary* binp;
	    Uint unused;
	
	    pb->flags = 0;
	    binp = pb->val;
	    ASSERT(binp->orig_size >= pb->size);
	    unused = binp->orig_size - pb->size;
	    /* Our allocators are 8 byte aligned, i.e., shrinking with
	       less than 8 bytes will have no real effect */
	    if (unused >= 8) {
	    // 根据ProBin中的有效字节数，重新创建一个不可追加的refc binary
		binp = erts_bin_realloc(binp, pb->size);
		pb->val = binp;
		pb->bytes = (byte *) binp->orig_bytes;
	    }
	}

>> Q: ProcBin B1的字段被更新了，那么Erlang上层如何维护变量不可变语义? 

>> A: 变量不可变指的是Erlang虚拟机上层通过底层屏蔽后所能看到的不变语义，而不是变量底层实现，诸如Pid打包，maps hash扩展等，通过底层差异化处理后，对上层体现的语义和接口都没变，因此我们将其理解为"变量不可变")。

另外，全局堆GC也可能会对可追加refc binary的预留空间进行收缩(shrink)，可参考`$BEAM_SRC/erl_gc.c sweep_off_heap`函数。

以上都是理论的实现，实际上Erlang虚拟机对二进制还做了一些基于上下文的优化，通过`bin_opt_info`编译选项可以打印出这些优化。关于binary优化的更多细节，参考[Constructing and Matching Binaries][]。

## 二. 复合类型

基于list和tuple之上，Erlang还提供了一些其它的数据结构，这里列举几个key/value相关的数据结构，在服务器中会经常用到。

### 1. record

这个类型无需过多介绍，它就是一个tuple，所谓record filed在预编译后实际上都是通过数值下标来索引，因此它访问field是O(1)复杂度的。
### 2. map

虽然record的语法糖让我们在使用tuple时便利了不少，但是比起真正的key/value结构仍然有许多限制，如key只能是原子，key不能动态添加或删除，record变动对热更的支持很差等。proplists能够一定程度地解决这种问题，但是它适合键值少的情况，通常用来做选项配置，并且不能保证key的唯一。

map是OTP 17引进的数据结构，是一个boxed对象，它支持任意类型的Key，模式匹配，动态增删Key等，并且最新的[mongodb-erlang][mongodb-erlang]直接支持map。

在[OTP17][erlang_otp_17_src]中，map的内存结构为：

```c
//位于 $OTP_SRC/erts/emulator/beam/erl_map.h
typedef struct map_s {
    Eterm thing_word;	// 	boxed对象header
    Uint  size;			// 	map 键值对个数
    Eterm keys;      	// 	keys的tuple
} map_t;
```

该结构体之后就是依次存放的Value，因此maps的get操作，需要先遍历keys tuple，找到key所在下标，然后在value中取出该下标偏移对应的值。因此是O(n)复杂度的。详见maps:get源码(`$BEAM_SRC/erl_map.c erts_maps_get`)。

如此的maps，只能作为record的替用，并不是真正的Key->Value映射，因此不能存放大量数据。而在OTP18中，maps加入了针对于big map的hash机制，当maps:size < `MAP_SMALL_MAP_LIMIT`时，使用flatmap结构，也就是上述OTP17中的结构，当maps:size >= `MAP_SMALL_MAP_LIMI`T时，将自动使用hashmap结构来高效存取数据。`MAP_SMALL_MAP_LIMIT`在erl_map.h中默认定义为32。

仍然要注意Erlang本身的变量不可变原则，每次执行更新maps，都会导致新开辟一个maps，并且拷贝原maps的keys和values，在这一点上，maps:update比maps:put更高效，因为前者keys数量不会变，因此无需开辟新的keys tuple，拷贝keys tuples ETerm即可。实际使用maps时：

1. 更新已有key值时，使用update(:=)而不是put(=>)，不仅可以检错，并且效率更高
2. 当key/value对太多时，对其进行层级划分，保证其拷贝效率

实际测试中，OTP18中的maps在存取大量数据时，效率还是比较高的，[这里][map_test]有一份maps和dict的简单测试函数，可通过OTP17和OTP18分别运行来查看效率区别。通常情况下，我们应当优先使用maps，比起dict，它在模式匹配，mongodb支持，可读性上都有很大优势。

### 3. array

Erlang有个叫array的结构，其名字容易给人误解，它有如下特性：

1. array下标从0开始
2. array有两种模式，一种固定大小，另一种按需自动增长大小，但不会自动收缩
3. 支持稀疏存储，执行array:set(100,value,array:new())，那么[0,99]都会被设置为默认值(undefined)，该默认值可修改。

在实现上，array最外层被包装为一个record:

```erlang
-record(array, {
	size :: non_neg_integer(),	%% number of defined entries
	max  :: non_neg_integer(),	%% maximum number of entries
	default,	%% the default value (usually 'undefined')
    elements :: elements(_)     %% the tuple tree
}).
```
	
elements是一个tuple tree，即用tuple包含tuple的方式组成的树，叶子节点就是元素值，元素默认以10个为一组，亦即完全展开的情况下，是一颗十叉树。但是对于没有赋值的节点，array用其叶子节点数量代替，并不展开：

```erlang
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
```

由于完全展开的tuple tree是一颗完全十叉树，因此实际上array的自动扩容也是以10为基数的。在根据Index查找元素时，通过div/rem逐级算出Index所属节点:

```erlang
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
```

更多细节可以参见源码，了解了这些之后，再来看看Erlang array和其它语言数组不一样的地方：

- 索引不是O(1)复杂度，而是O(log10n)
- array并不自动收缩
- array中的max和size字段，和array具体占用内存没多大关系(节点默认未展开)
- array中并没有subarray之类的操作，因为它根本不是线性存储的，而是树形的，因此如果用它来做递归倒序遍历之类的操作，复杂度不是O(n)，而是O(n*log10n)
- array中对于没有赋值的元素，给予默认值undefined，这个默认值可以在array:new()中更改，对使用者来说，明确赋值undefined和默认值undefined并无多大区别，但对array内部来说，可能会导致节点展开。

## 三. 参考

1. Erlang数据结构实现文章汇总: http://www.iroowe.com/erlang_eterm_implementation/
2. [zhengsyao] Erlang系列精品博客(文中大部分图片出处): http://www.cnblogs.com/zhengsyao/category/387871.html
3. [坚强2002] Erlang array: http://www.cnblogs.com/me-sa/archive/2012/06/14/erlang-array.html
4. Erlang Effciency Guide: http://erlang.org/doc/efficiency_guide/introduction.html


[mongodb-erlang]: https://github.com/comtihon/mongodb-erlang
[map_test]: https://github.com/wudaijun/Code/blob/master/erlang/map_test.erl
[erlang_otp_18_src]: https://github.com/erlang/otp/tree/maint-18
[erlang_otp_17_src]: https://github.com/erlang/otp/tree/maint-17
[Constructing and Matching Binaries]: http://erlang.org/doc/efficiency_guide/binaryhandling.html
