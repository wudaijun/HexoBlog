---
layout: post
title: skynet socketserver
categories:
- gameserver
tags:
- lua
- skynet
---
### 1. 异步IO

skynet用C编写的sokcet模块使用异步回调机制，通过lualib-src/lua-socket.c导出为socketdriver模块。skynet socket C API使用的异步回调方式是：在启动socket时，记录当前服务handle，之后该socket上面的消息(底层使用epoll机制)通过skynet消息的方式发往该服务。这里的当前服务指的是socket启动时所在的服务，对于被请求方来说，为调用`socketdriver.start(id)`的服务，对于请求方来说，为调用`socketdriver.connect(addr,port)`的服务。skynet不使用套接字fd在上层传播，因为在某些系统上fd的复用会导致上层遇到麻烦，skynet socket C API为每个fd分配一个ID，是自增不重复的。

<!--more-->

socket C API 的核心是三个poll:

#### socket poll

位于skynet-src/socket_poll.h 底层异步IO，监听可读可写状态，对于linux系统，使用的是epoll模型。

#### socket_server_poll

位于skynet-src/socket_server.c 使用socket poll，处理所有套接字上的IO事件和控制事件。socket_server_poll处理这些事件，并返回处理结果(返回一个type代表事件类型，通过socket_message* result指针参数返回处理结果)。

IO事件主要包括可读，可写，新连接到达，连接成功。对于可读事件，socket_server_poll会读取对应套接字上的数据，如果读取成功，返回SOCKET_DATA类型，并且通过result参数返回读取的buffer。同样对于可写事件，会尝试发送缓冲区中的数据，并返回处理结果。

而控制事件指的是上层调用，由于skynet上层使用的是一个id而不是socket fd来代表一个套接字。skynet在该id上做的所有操作(如设置套接字属性，接受连接，关闭连接，发送数据等等)都会被写入特殊的ctrl套接字(recvctrl_fd sendctrl_fd)，这些ctrl fd位于socket_server结构中，是唯一的，因此写入ctrl的控制信息要包括被操作的套接字ID。这些控制信息统一通过socket poll来处理。再在socket_server_poll中，根据id提出对应的socket fd来完成操作。

#### skynet_socket_poll

通过socket poll 和 socket_server_poll，此时数据已就绪，新连接也已经被接受，需要通知上层处理这些数据，而skynet_socket_poll就是来完成这些工作的。它调用socket_server_poll，根据其返回的type和result来将这些套接字事件发送给套接字所属服务(服务handle已由socket_server_poll填充在result->opaque字段中)。skynet_socket_poll将socket_message* result 和 type 字段组装成skynet_socket_message，并且通过skynet_message消息发送给指定服务，消息类型为PTYPE_SOCKET。这样一次异步IO就完成了。

skynet_socket_poll通过一个单独的线程跑起来，线程入口为_socket函数，位于skynet-src/skynet_start.c。

### 2. lua层封装

skynet socket C API提供的是异步IO，为方便使用，在lua层提供了一个socket(lualib/socket.lua)模块来实现阻塞读写。该模块是对socketdriver的封装。它通过lua协程模拟阻塞读写。

和gateserver模块一样，socket模块对PTYPE_SOCKET类型的消息进行了注册处理，它使用socketdriver.unpack作为该类型消息的unpack函数。socketdriver.unpack并不进行实际的分包，它只解析出原始数据，socket模块会缓存套接字上收到的数据。缓存结构由socketdriver提供。当调用socket.readline时，将通过socketdriver.readline尝试从缓冲区中读取一行数据。如果缓冲区数据不足，则挂起自身，待数据足够时唤醒。虽然底层仍然是异步，但是由于协程的特性，对上层体现为同步。通过socket模块的API读到的数据可以看做原始数据。

### 3. 消息分包

大多数时候，在收到套接字数据时，要按照消息协议进行消息分包。skynet提供一个netpack库用于处理分包问题，netpack由C编写，位于lualib-src/lua-netpack.c。skynet范例使用的包格式是两个字节的消息长度(Big-Endian)加上消息数据。netpack根据包格式处理分包问题，netpack提供一个`netpack.filter(queue, msg, size)`接口，它返回一个type("data", "more", "error", "open", "close")代表具体IO事件，其后返回每个事件所需参数。

对于SOCKET_DATA事件，filter会进行数据分包，如果分包后刚好只有一条完整消息，filter返回的type为"data"，其后跟fd msg size。如果不止一条消息，那么消息将被依次压入queue参数中，并且仅返回一个type为"more"。queue是一个结构体指针，可以通过`netpack.pop`弹出queue中的一条消息。

其余type类型"open"，"error", "close"分别对应于socket_message中的SOCKET_ACCEPT SOCKET_ERROR SOCKET_CLOSE事件。netpack的使用者可以通过filter返回的type来进行事件处理。

netpack会尽可能多地分包，交给上层。并且通过一个哈希表保存每个套接字ID对应的粘包，在下次数据到达时，取出上次留下的粘包数据，重新分包。

[1]: https://github.com/cloudwu/skynet/wiki/Socket "skynet wiki: Socket"
