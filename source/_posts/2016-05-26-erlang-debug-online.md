---
title:  Erlang 状态监控
layout: post
tags: erlang
categories: erlang

---

## 一. 接入远程节点

### 1. JCL

	erl -sname n2 -setcookie 123
	(n2@T4F-MBP-11)1>		//^G
	User switch command
	 --> r 'n1@T4F-MBP-11'
	 --> c
	Eshell V8.1  (abort with ^G)
	(n1@T4F-MBP-11)1>


### 2. remsh

	erl -setcookie abc -name node_2@127.0.0.1 -remsh node_1@127.0.0.1
	
和第一种JCL方式是同一个原理，这也是rebar2 remote_console的实现方式。

### 3. [erl_call][]
	
		erl_call -s -a 'erlang memory ' -name node_1@127.0.0.1 -c abc

### 4. [run_erl][]
	
		run_erl -daemon tmp/ log/ "exec erl -eval 't:start_link().'"
	
`run_erl`是随OTP发布的命令，它通过管道来与Erlang节点交互，仅类Unix系统下可用。上面的命令启动Erlang节点，将tmp/目录设为节点管道目录，之后`run_erl`会在tmp下创建`erlang.pipe.1.r erlang.pipe.1.w`两个管道文件，外部系统可通过该管道文件向节点写入/读取数据。可用OTP提供的`to_erl`命令通过管道连接到节点:

		to_erl tmp/
		Attaching to tmp/erlang.pipe.1 (^D to exit)
		1> 

需要注意的当前你是直接通过Unix管道和节点交互的，并不存在中间代理节点(和remsh方式不同)，因此在这种情况下使用JCL `^G+q`会终止目标节点。如果要退出attach模式而不影响目标节点，使用`^D`。

`run_erl`另一个作用是输出重定向，上例中将所有输出(包括虚拟机和nif输出)重定向到log/erlang.log.*，这对多日志渠道(lager,io:format,c,lua等)的混合调试是有所帮助的。

rebar2便通过`run_erl`实现节点启动，并使用`to_erl`实现`attach`命令。

### 5. ssh

		---------- Server:  -----------
		$ mkdir /tmp/ssh
		$ ssh-keygen -t rsa -f /tmp/ssh/ssh_host_rsa_key
		$ ssh-keygen -t rsa1 -f /tmp/ssh/ssh_host_key
		$ ssh-keygen -t dsa -f /tmp/ssh/ssh_host_dsa_key
		$ erl
		1> application:ensure_all_started(ssh).
		{ok,[crypto,asn1,public_key,ssh]}
		2> ssh:daemon(8989, [{system_dir, "/tmp/ssh"},
		2> {user_dir, "/home/ferd/.ssh"}]).
		{ok,<0.52.0>}
		
		---------- Client -------------
		$ ssh -p 8989 ferd@127.0.0.1
		Eshell Vx.x.x (abort with ^G)
		1>


## 二. etop

etop是Erlang提供的类似于top命令，它的输出格式和功能都与top类似，提供了必要的节点信息和进程信息。常用用法：

	% 查看占用CPU最高的进程 每10秒输出一次
	> spawn(fun() -> etop:start([{interval,10}, {sort, runtime}]) end). 
	% 查看占用内存最高的进程 每10秒输出一次 输出进程数量为20
	> spawn(fun() -> etop:start([{interval,10}, {sort, memory}, {lines,20}]) end). 
	% 连接远程节点方式一
	> erl -name abcd@127.0.0.1 -hidden -s etop -output text -sort memory -lines 20 -node 'server_node@127.0.0.1' -setcookie galaxy_server
	% 连接远程节点方式二
	> erl -name abc@127.0.0.1 -hidden  -setcookie galaxy_server
	> etop:start([{node,'server_node@127.0.0.1'}, {output, text}, {lines, 20},  {sort, memory}]).
	% 连接远程节点方式三
	> erl -name abc@127.0.0.1 -setcookie galaxy_server
	>  rpc:call('server_node@127.0.0.1', etop, start, [[{output, text}, {lines, 20},  {sort, memory}]]).
	
输出样例(截断为前5条)：

	========================================================================================
	 'def@127.0.0.1'                                                           09:38:01
	 Load:  cpu         0               Memory:  total       14212    binary         40
	        procs      35                        processes    4398    code         4666
	        runq        0                        atom          198    ets           304
	
	Pid            Name or Initial Func    Time    Reds  Memory    MsgQ Current Function
	----------------------------------------------------------------------------------------
	<6858.7.0>     application_controll     '-'    7830  426552       0 gen_server:loop/6
	<6858.12.0>    code_server              '-'  125106  284656       0 code_server:loop/1
	<6858.33.0>    erlang:apply/2           '-'   10300  230552       0 shell:get_command1/5
	<6858.3.0>     erl_prim_loader          '-'  211750  122040       0 erl_prim_loader:loop
	<6858.0.0>     init                     '-'    3775   18600       0 init:loop/1
	========================================================================================

官方文档：http://erlang.org/doc/apps/observer/etop_ug.html

## 三. erlang API

### 1. 内存

通过`erlang:memory()`可以查看整个Erlang虚拟机的内存使用情况。

### 2. CPU

Erlang的CPU使用情况是比较难衡量的，由于Erlang虚拟机内部复杂的调度机制，通过`top/htop`得到的系统进程级的CPU占用率参考性是有限的，即使一个空闲的Erlang虚拟机，调度线程的忙等也会占用一定的CPU。

因此Erlang内部提供了一些更有用的测量参考，通过`erlang:statistics(scheduler_wall_time)`可以获得调度器钟表时间：

```
1> erlang:system_flag(scheduler_wall_time, true).
false
2> erlang:statistics(scheduler_wall_time).
[{{1,166040393363,9269301338549},
 {2,40587963468,9269301007667},
 {3,725727980,9269301004304},
 4,299688,9269301361357}]
```
	 

该函数返回`[{调度器ID, BusyTime, TotalTime}]`，BusyTime是调度器执行进程代码，BIF，NIF，GC等的时间，TotalTime是`cheduler_wall_time`打开统计以来的总调度器钟表时间，通常，直观地看BusyTime和TotalTIme的数值没有什么参考意义，有意义的是BusyTime/TotalTIme，该值越高，说明调度器利用率越高：

```
1> Ts0 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
ok	
2> Ts1 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
ok	
3> lists:map(fun({{I, A0, T0}, {I, A1, T1}}) -> 
	{I, (A1 - A0)/(T1 - T0)} end, lists:zip(Ts0,Ts1)).
[{1,0.01723977154806915},	
 {2,8.596423007719012e-5},	
 {3,2.8416950342830393e-6},	
 {4,1.3440177144802423e-6}
}]
```

### 3. 进程

通过`length(processes())`/`length(ports())`统计虚拟机当前进程和端口数量。

关于指定进程的详细信息，都可以通过`erlang:process_info(Pid, Key)`获得，其中比较有用的Key有：

- dictionary: 			进程字典中所有的数据项
- registerd_name: 	注册的名字
- status:				进程状态
- links: 				所有链接进程
- monitored_by:		所有监控当前进程的进程
- monitors:			所有被当前进程监控的进程
- trap_exit:			是否捕获exit信号
- current_function:	当前进程执行的函数，{M, F, A}
- current_location:	进程在模块中的位置，{M, F, A, [{file, FileName}, {line, Num}]}
- current_stacktrace:  以current_location的格式列出堆栈跟踪信息
- initial_call:			进程初始入口函数，如spawn时的入口函数，{M, F, A}
- memory:			进程占用的内存大小(包含所有堆，栈等)，以bytes为单位
- message_queue_len: 进程邮箱中的待处理消息个数
- messages:			返回进程邮箱中的所有消息，该调用之前务必通过message_queue_len确认消息条数，否则消息过多时，调用非常危险
- reductions:			进程[规约](http://www.cnblogs.com/zhengsyao/p/how_erlang_does_scheduling_translation.html)数

获取端口信息，可调用`erlang:port_info/2`。

关于OTP进程，Erlang提供了更为丰富的调试模块，如[sys](http://erlang.org/doc/man/sys.html)，其中部分常用函数：

- sys:log_to_file(Pid, FileName)：	将指定进程收到的所有事件信息打印到指定文件
- sys:get_state(Pid)：				获取OTP进程的State
- sys:statistics(Pid, Flag):			Flag: true/false/get 打开/关闭/获取进程信息统计
- sys:install/remove				可为指定进程动态挂载和卸载通用事件处理函数
- sys:suspend/resume:			挂起/恢复指定进程
- sys:terminate(Pid, Reason):		向指定进程发消息，终止该进程


## 四. recon

[recon][]是[learn you some erlang][]的作者写的一个非常强大好用的库，将erlang散布在各个模块的调试函数整合起来，以更易用和可读的方式提供给用户，包含了信息统计，健康状态分析，动态追踪调试等一整套解决方案。并且本身只是一系列的API，放入rebar deps即可attach上节点使用，强烈推荐。

下面是我常用的几个函数:

	% 找出当前节点Attr属性(如message_queue_len)最大的N个进程
	recon:proc_count(Attr, N).
	% 对节点进行GC，并返回进程GC前后持有的binary差异最大的N个进程
	recon:bin_leak(N).
	% process_info的安全增强版本
	recon:info/1-2-3-4
	% 返回M毫秒内的调度器占用
	recon:scheduler_usage(M)
	% 强大的动态追踪函数，可用于动态挂载钩子。
	% 1. 可挂载模块/函数调用(甚至可对参数匹配/过滤)
	% 2. 可对调用进程筛选(指定Pid，限制新建进程等)
	% 3. 可限制打印的追踪数量/速率
	% 4. 其它功能，如输出重定向，追踪调用结果等
	recon_trace:calls/2-3
	

详细用法参见：http://ferd.github.io/recon/

## 五. 更多资料

- Erlang实践红宝书：[Erlang In Anger][]



[erl_call]: http://erlang.org/doc/man/erl_call.html
[run_erl]: http://erlang.org/doc/man/run_erl.html
[recon]: https://github.com/ferd/recon
[Erlang In Anger]: http://pan.baidu.com/s/1gfCZBKf
[learn you some erlang]: http://learnyousomeerlang.com/
