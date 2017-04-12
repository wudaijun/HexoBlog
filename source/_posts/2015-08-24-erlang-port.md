---
title: Erlang Ports
layout: post
categories: erlang
tags: erlang

---

### OverView

Erlang外部调用的几种方式：

外部接入(OS进程级)：

- [Ports][]: 用C实现的可执行程序，以Port的方式与Erlang交互。
- [C Nodes][]: 用C模拟Erlang Node行为实现的可执行程序。
- [Jinterface][]: Java和Erlang的通讯接口。
- Network: 通过自定义序列化格式与Erlang节点网络交互，如[bert-rpc][]

内部接入(和虚拟机在同一个OS进程内)：

- BIF: Erlang大部分BIF用C实现，如erlang:now，lists:reverse等
- [Port Driver][]: 以链接库方式将Port嵌入虚拟机，也叫Linkin Driver
- [NIF][]: 虚拟机直接调用C原生代码

下面主要理解常用的三种：Ports, Port Driver, NIF。

<!--more-->

### Ports

![](/assets/image/erlang/Erlang_Port.png "普通端口")

图一. Ports 通信模型

Port是连接外部程序进程和Erlang虚拟机的桥梁，外部进程通过标准输入输出与Erlang虚拟机交互，并运行于独立的地址空间。

从操作系统的角度看，外部程序和Erlang虚拟机都是独立允许的进程，只不过外部程序的标准输入输出与Erlang虚拟机对接在了一起而已。因此外部程序可以通过`read(0, req_buf, len)`来获取虚拟机发出的指令，也可通过`write(1, ack_buf, len)`来发出响应。当外部程序崩溃了，Erlang虚拟机可以检测到，可以选择重启等对应策略。由于两者在不同的地址空间，通过标准IO交互，因此外部程序的崩溃不会影响到Erlang虚拟机本身的正常运行。

每个Port都有一个owner进程，通常为创建Port的进程，当owner进程终止时，Port也将被自动关闭。Ports使用示例参考[Ports]。

Port的优势在于隔离性和安全性，因为外部程序的任何异常都不会导致虚拟机崩溃，并且Erlang层通过`receive`来实现同步调用等待外部程序响应时，是不会影响Erlang虚拟机调度的。至于Port的缺点，主要是效率低，由于传递的是字节流数据，因此需要对数据进行序列化反序列化，Erlang本身针对C和Java提供了对应的编解码库ei和Jinterface。


### Port Driver


![](/assets/image/erlang/Erlang_Port_Driver.png "端口驱动")

图二. Port Driver 通信模型

从Erlang层来看，端口驱动和普通端口所体现的行为模式一样，收发消息，注册名字，并且共用一套Port API。但是端口驱动本身是作为一个链接库运行于Erlang虚拟机中的，也就是和Erlang虚拟机共享一个操作系统进程。

Port Driver分为静态链接和动态链接两种，前者和虚拟机一起编译，在虚拟机启动时被加载，后者通过动态链接库的方式嵌入到虚拟机。出于灵活性和易用性的原因，通常使用后者。

虚拟机和Port Driver的交互方式与Port一样，Port和Port Driver在Erlang层表现的语义一致。

Port Driver通过一个[driver_entry][]结构体与虚拟机交互，该结构体注册了driver针对各种虚拟机事件的响应函数。[skynet挂接service][skynet_service]的思想大概也继承于此。driver_entry结构体主要成员如下：

	typedef struct erl_drv_entry {
	// 当链接库被加载(erl_ddll:load_driver/2)时调用，同一个链接库的多个driver实例来说，只调用一次
	int (*init)(void);
	
	// 当Erlang层调用erlang:open_port/2时调用，每个driver实例执行一次
	ErlDrvData (*start)(ErlDrvPort port, char *command);
	
	// 当Port Driver被关闭(erlang:port_close/1,owner进程终止,虚拟机停止等)时执行
	void (*stop)(ErlDrvData drv_data);
	
	// 收到Erlang进程发来的消息(Port ! {PortOwner, {command, Data}} or erlang:port_command(Port, Data))
	void (*output)(ErlDrvData drv_data, char *buf, ErlDrvSizeT len);

	// 用于基于事件的异步Driver 通过erl_driver:driver_select函数进行事件(socket,pipe,Event等)监听
	void (*ready_input)(ErlDrvData drv_data, ErlDrvEvent event);
	void (*ready_output)(ErlDrvData drv_data, ErlDrvEvent event);
	
	// Driver名字 用于open_port/2
	char *driver_name;
	
	// 当Driver被卸载时调用(erl_ddll:unload_driver/1)，和init对应。仅针对动态链接Driver
	void (*finish)(void);
	
	// 被erlang:port_control/3(类似ioctl)触发
	ErlDrvSSizeT (*control)(ErlDrvData drv_data, unsigned int command,
	                        char *buf, ErlDrvSizeT len,
			    char **rbuf, ErlDrvSizeT rlen);
	
	// Driver定义的超时回调，通过erl_driver:driver_set_timer设置
	void (*timeout)(ErlDrvData drv_data);
	
	// output的高级版本，通过ErlIOVec避免了数据拷贝，更高效
	void (*outputv)(ErlDrvData drv_data, ErlIOVec *ev);
	
	// 用于基于线程池的异步Driver(erl_driver:driver_async) 当线程池中的的任务执行完成时，由虚拟机调度线程回调该函数                       
	void (*ready_async)(ErlDrvData drv_data, ErlDrvThreadData thread_data);
	
	// 当Driver即将关闭时，在stop之前调用 用于清理Driver队列中的数据(?)
	void (*flush)(ErlDrvData drv_data);
	
	// 被erlang:port_call/3触发 和port_control类似，但使用ei库编码ETerm
	ErlDrvSSizeT (*call)(ErlDrvData drv_data, unsigned int command,
	                     char *buf, ErlDrvSizeT len,
			 char **rbuf, ErlDrvSizeT rlen, unsigned int *flags);
	
	// Driver 监听的进程退出信号(erl_driver:driver_monitor_process)
	void (*process_exit)(ErlDrvData drv_data, ErlDrvMonitor *monitor);
	} ErlDrvEntry;

该结构体比较复杂，主要原因是Erlang Port Driver支持多种运行方式：

1. 运行于虚拟机调度线程的基本模式
2. 基于select事件触发的异步Driver
3. 基于异步线程池的异步Driver

三种模式的示例参考[Port Driver][]，[How to Implement a Driver][]，Driver API接口文档：[erl_driver][]。Erlang虚拟机提供的异步线程池可通过`+A`选项设置。

端口驱动的主要优势是效率高，但是缺点是链入的动态链接库本身出现内测泄露或异常，将影响虚拟机的正常运行甚至导致虚拟机崩溃。将外部模块的问题带入了虚拟机本身。对于耗时较长或阻塞的任务，应该通过异步方式设计，避免影响虚拟机调度。


### NIF

NIF是Erlang调用C代码最简单高效的方案，对Erlang层来说，调用NIF就像调用普通函数一样，只不过这个函数是由C实现的。NIF是同步语义的，运行于调度线程中，无需上下文切换，因此效率很高。但也引出一个问题，对于执行时间长的NIF，在NIF返回之前，调度线程不能做别的事情，影响了虚拟机的公平调度，甚至会影响调度线程之间的协作。因此NIF是把双刃剑，在使用的时候要尤其小心。

Erlang建议的NIF执行时间不要超过1ms，针对于执行时间长的NIF，有如下几种方案：

1. 分割任务，将单次长时间调用切分为多次短时间调用，再合并结果。这种方案显然不通用
2. 让NIF参与调度。在NIF中恰当时机通过`enif_consume_timeslice`汇报消耗的时间片，让虚拟机确定是否放弃控制权并通过返回值通知NIF(做上下文保存等)
3. 使用脏调度器，让NIF在非调度线程中执行

Erlang默认并未启用脏调度器，通过`--enable-dirty-schedulers`选项重新编译虚拟机可打开脏调度器，目前脏调度器只能被NIF使用。

关于脏调度器，NIF测试与调优，参考：

1. [siyao blog][]
2. [nifwait][]
3. [bitwise][]([其中的PDF][bitwise pdf]质量很高)


Port Driver和NIF与虚拟机调度密切相关，想要在实践中用好它们，还是要加深对Erlang虚拟机调度的理解，如公平调度，进程规约，调度器协同等。再来理解异步线程池，脏调度器的存在的意义以及适用场景。另外，Port Driver和NIF还有一种用法是自己创建新的线程或线程池(Driver和NIF也提供了线程操作API)，我们项目组也这么用过，这基本是费力不讨好的一种方案，还极易出错。


[siyao blog]: http://www.cnblogs.com/zhengsyao/p/dirty_scheduler_otp_17rc1.html
[nifwait]: https://github.com/slfritchie/nifwait/tree/md5
[bitwise]: https://github.com/vinoski/bitwise/
[bitwise pdf]: https://github.com/vinoski/bitwise/blob/master/vinoski-opt-native-code.pdf
[ErlDrvEntry]: http://erlang.org/doc/man/driver_entry.html
[skynet_service]: http://wudaijun.com/2015/01/skynet-c-module/
[C Nodes]: http://erlang.org/doc/tutorial/cnode.html
[Jinterface]:http://erlang.org/doc/apps/jinterface/jinterface_users_guide.html
[bert-rpc]: http://bert-rpc.org/
[erl_driver]: http://erlang.org/doc/man/erl_driver.html
[Port Driver]: http://erlang.org/doc/tutorial/c_portdriver.html)
[driver_entry]: http://erlang.org/doc/man/driver_entry.html
[How to Implement a Driver]: (http://erlang.org/doc/apps/erts/driver.html)
[Ports]: http://erlang.org/doc/tutorial/c_port.html
[NIF]: http://www.erlang.org/doc/tutorial/nif.html
