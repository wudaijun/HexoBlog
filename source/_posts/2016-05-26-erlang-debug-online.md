---
title:  Erlang实践(2) 线上调试
layout: post
tags: erlang
categories: erlang

---

## 接入远程节点的几种方法

1. JCL任务切换或remsh启动参数：

		erl -setcookie abc -name node_2@127.0.0.1 -remsh node_1@127.0.0.1
2. 通过[erl_call][]实现shell脚本与Erlang节点的简单交互:
	
		erl_call -s -a 'erlang memory ' -name node_1@127.0.0.1 -c abc

<!--more-->

3. 通过ssh服务连接Erlang节点：

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

## 状态监控

### 内存

通过`erlang:memory()`可以查看整个Erlang虚拟机的内存使用情况。

### CPU

Erlang的CPU使用情况是比较难衡量的，由于Erlang虚拟机内部复杂的调度机制，通过`top/htop`得到的系统进程级的CPU占用率参考性是有限的，即使一个空闲的Erlang虚拟机，调度线程的忙等也会占用一定的CPU。

因此Erlang内部提供了一些更有用的测量参考，通过`erlang:statistics(scheduler_wall_time)`可以获得调度器钟表时间：

	> erlang:system_flag(scheduler_wall_time, true).
	false
	> erlang:statistics(scheduler_wall_time).
	[{{1,166040393363,9269301338549},
	 {2,40587963468,9269301007667},
	 {3,725727980,9269301004304},
	 4,299688,9269301361357}] 

该函数返回`[{调度器ID, BusyTime, TotalTime}]`，BusyTime是调度器执行进程代码，BIF，NIF，GC等的时间，TotalTime是`cheduler_wall_time`打开统计以来的总调度器钟表时间，通常，直观地看BusyTime和TotalTIme的数值没有什么参考意义，有意义的是BusyTime/TotalTIme，该值越高，说明调度器利用率越高：

	> Ts0 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
	ok	
	> Ts1 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
	ok	
	> lists:map(fun({{I, A0, T0}, {I, A1, T1}}) -> 	
	{I, (A1 - A0)/(T1 - T0)} end, lists:zip(Ts0,Ts1)).	
	[{1,0.01723977154806915},	
	 {2,8.596423007719012e-5},	
	 {3,2.8416950342830393e-6},	
	 {4,1.3440177144802423e-6}
	}]

### 进程

通过`length(processes())`/`length(ports())`统计虚拟机当前进程和端口数量。

关于指定进程的详细信息，都可以通过`erlang:process_info(Pid, Key)`获得，其中比较有用的Key有：

- dictionary: 			进程字典中所有的数据项
- registerd_name: 	注册的名字
- status:				进程状态，包含: 
 	- waiting: 等待消息中
 	- running: 运行中
 	- runnable: 准备就绪，尚未被调度  
 	- exiting: 进程已结束，但未被完全清除
 	- garbage_collecting: GC中
 	- suspended: 挂起中
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


## 第三方工具

- 更多测量CPU和性能的工具和模块：[eprof][]，[fprof][]，[eflame][]。
- learnyousomeerlang作者写的一个库： [recon][]
- Erlang实践红宝书：[Erlang In Anger][]



[erl_call]: http://erlang.org/doc/man/erl_call.html
[eprof]: http://www.erlang.org/doc/man/eprof.html
[fprof]: http://www.erlang.org/doc/man/fprof.html
[eflame]: https://github.com/proger/eflame
[recon]: https://github.com/ferd/recon
[Erlang In Anger]: hhttp://pan.baidu.com/s/1gfCZBKf