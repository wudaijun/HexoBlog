---
title: Erlang Ports
layout: post
categories: erlang
tags: erlang

---

Erlang虚拟机就像一个操作系统，操作系统可以通过Port与外界交互，完成IO操作。Port就像操作系统的套接字，在Erlang中其行为模式与进程无二，可以收发消息，注册名字等等，只不过它不具有代码执行能力，它是外部程序"伪装"的Erlang进程。Erlang Port可分为两种，一种是普通端口(Ports)，外部程序以操作系统进程的方式独立运行，它通过标准输入输出与Erlang虚拟机交互。另一种是端口驱动(Port Driver)，它以动态链接库的方式内联(linkin)到Erlang虚拟机，作为虚拟机的一部分，与Erlang虚拟机共享一个操作系统进程。除了端口以外，Erlang还可以通过NIF的方式调用外部程序，Erlang使用NIF就像调用普通Erlang函数一样，只不过这个函数是其它语言实现的。

<!--more-->

Erlang与外部程序交互的方式主要有三种：

1. 普通端口(Ports)
2. 端口驱动(Port Driver),也叫链入式驱动(Linkin Driver)
3. 原生实现函数(Native Implemented Functions, NIF)

### 一. Ports

#### 1.简介

![](/assets/image/erlang/Erlang_Port.png "普通端口")

图一. Ports 通信模型

普通端口是连接外部程序进程和Erlang虚拟机的桥梁，外部进程通过标准输入输出与Erlang虚拟机交互，并运行于独立的地址空间。

从操作系统的角度看，外部程序和Erlang虚拟机都是独立允许的进程，只不过外部程序的标准输入输出与Erlang虚拟机对接在了一起而已。因此外部程序可以通过`read(0, req_buf, len)`来获取虚拟机发出的指令，也可通过`write(1, ack_buf, len)`来发出响应。当外部程序崩溃了，Erlang虚拟机可以检测到，可以选择重启等对应策略。由于两者在不同的地址空间，只能通过标准IO交互，因此外部程序的崩溃不会影响到Erlang虚拟机本身的正常运行。

从Erlang的角度看，端口的行为模式表现为一个进程，但它本身无法执行代码，每个端口都有一个属主进程，一般是调用`open_port`的进程，端口将外界收到的数据发给属主。Erlang中其它进程也通过属主进程与端口交互。当属主进程终止时，端口也将被自动关闭。

#### 2.优缺点

普通端口的优势在于隔离性和安全性，因为外部程序的任何异常都不会导致虚拟机崩溃，并且Erlang层通过`receive`来实现同步调用等待外部程序响应时，是不会影响Erlang虚拟机调度的。至于普通端口的缺点，主要是效率低，由于传递的是字节流数据，因此需要对数据进行序列化反序列化，Erlang本身针对C和Java提供了对应的编解码库ei和Jinterface。

#### 3.使用

将外部C代码编译为可执行文件，通过`erlang:open_port/2`打开端口，Erlang层之后即可通过消息与Port交互。C程序从标准输入读取字节流，反序列化得到请求数据，处理完成之后，将序列化后的响应数据写入标准输出。Port收到数据后，会将数据以消息的方式发往属主进程。

参见：http://erlang.org/doc/tutorial/c_port.html

### 二. Port Driver

#### 1.简介

![](/assets/image/erlang/Erlang_Port_Driver.png "端口驱动")

图二. Port Driver 通信模型

从Erlang层来看，端口驱动和普通端口所体现的行为模式一样，收发消息，注册名字，并且共用一套Port API。但是端口驱动本身是作为一个动态链接库运行于Erlang虚拟机中的，也就是和Erlang虚拟机共享一个操作系统进程。

#### 2.优缺点

端口驱动的主要优势是效率高，但是缺点是链入的动态链接库本身出现内测泄露或异常，将影响虚拟机的正常运行甚至导致虚拟机崩溃。将外部模块的问题带入了虚拟机本身。并且Port Driver的调用是阻塞的，这将影响到虚拟机调度。因此Erlang Driver提供了一系列的异步接口。

#### 3.使用

Port Driver是符合[Erlang Driver][]规范的动态链接库，它向Erlang虚拟机提供一个[ErlDrvEntry][]结构体，其内主要包含由虚拟机回调Driver的各个接口。[skynet挂接service][skynet_service]的思想大概也继承于此，只不过Erlang Port Driver更为完善和复杂。

具体使用参见：http://erlang.org/doc/tutorial/c_portdriver.html

### 三. NIF

#### 1. 简介

Erlang挂接外部模块的第三种方式就是NIF，NIF是由C实现的函数，但是在Erlang层和调用BIF一样方便和快速。

#### 2. 优缺点

原生函数(NIF)是三种方式中效率最高的，但是也是风险最高的。它和Port Driver一样可能导致虚拟机异常和崩溃，NIF是在虚拟机线程上下文中调用的，NIF不将控制权交还给虚拟机，虚拟机就无法再次调度该线程。因此NIF只适用于安全，高速的原生实现。

#### 3. 使用

参见：http://www.erlang.org/doc/tutorial/nif.html

[Erlang Driver]: http://erlang.org/doc/man/erl_driver.html
[ErlDrvEntry]: http://erlang.org/doc/man/driver_entry.html
[skynet_service]: http://wudaijun.com/2015/01/skynet-c-module/
