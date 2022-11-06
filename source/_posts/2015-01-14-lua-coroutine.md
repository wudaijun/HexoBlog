---
layout: post
title: lua 协程
categories:
- lua
tags:
- lua
- coroutine
- async programing
---

### 协程基础

协程(协同式多线程)是一种用户级的非抢占式线程。"用户级"是指它的切换和调度由开发者控制，"非抢占"指一个协程只有在其挂起(yield)或者协程结束才会返回。协程和C线程一样，有自己的堆栈，自己的局部变量，自己的指令指针，并且和其它协程共享全局变量等信息。很多语言都有协程的概念，但在我看来，Python、JS、Lua这类语言的协程概念是类似的，C#有枚举器(迭代器)，但没有协程(我在[C#/Unity中的异步编程](https://wudaijun.com/2021/11/c-sharp-unity-async-programing/)中有聊这个话题)，Go语言中的goroutine也被翻译为协程，但实际上它是抢占式的轻量级线程，被称作协程("协"本身就有协作协同之意)是有歧义的。在我的理解中，协程的本质就是用户级的控制权(执行权)的让出和恢复机制(以及相关的上下文保存和值传递机制)，在理解这一点之后，其它如: 

- 协程是本质单线程的，协程可以实现单线程内的异步操作，并且无需考虑同步和加锁的问题
- 在单线程内，同一时刻只有一个协程在运行
- 协程可以以类似同步的方式来写异步代码
- 协程可以让函数返回多次

等说法，也就比较好理解了。本文主要简单介绍下Lua协程。

### Lua协程

Lua协程的相关函数封装在coroutine中，对应的 C API为`lua_newthread`，`lua_resume`等。Lua文档中的thread和coroutine是一个概念，但与操作系统的线程是两个东西。

C API通过`lua_State`维护一个协程的状态(以及Lua虚拟机状态的引用)，协程的状态主要指协程上下文(如交互栈)，Lua虚拟机状态是全局的，可被多个协程共享。以下描述摘自Lua5.3官方文档：

>> An opaque structure that points to a thread and indirectly (through the thread) to the whole state of a Lua interpreter. The Lua library is fully reentrant: it has no global variables. All information about a state is accessible through this structure.

>> A pointer to this structure must be passed as the first argument to every function in the library, except to lua_newstate, which creates a Lua state from scratch.

当调用`lua_newstate`时，实际上分为两步，1. 创建并初始化一个Lua虚拟机(`global_State`)；2.创建一个主协程运行于虚拟机中，并返回主协程的执行上下文(LuaState)。调用`lua_newthread`时，将在已有Lua虚拟机上，创建另一个协程执行环境，该协程与已有协程共享虚拟机状态(同一个Lua虚拟机中的不同协程共享`global_State`)，并返回新的执行上下文。因此将LuaState理解为协程执行上下文可能更合适，LuaState本身也是一个类型为thread的GCObject，无需手动释放(Lua也没有提供对应close或destroy接口)。

Lua协程的的核心API主要是三个，`coroutine.create`，`coroutine.yield`，`coroutine.resume`，分别对应创建(通常是基于函数)、让出执行权(但不知道让出给谁)，和恢复执行权(需要明确指定恢复哪个coroutine)三个操作。

### 两个例子

pil上关于协程有两个非常经典的例子。

在生产者消费者例子中，当消费者需要生产者的数据时(相当于一个异步回调)，切换到生产者协程(resume)，生产者开始运行，生产完成后，挂起自己(yield)并且传入生产的数据。此时调度回到消费者协程中，消费者从resume的返回值中得到数据，使用数据，在需要数据时再次唤醒生产者。这样我们像写同步代码一样(resume相当于函数调用，yield相当于函数返回)，完成了异步功能。而无需考虑传统生产者和消费者模型中的同步问题，因为这两者是在单线程内统一协同的。代码如下：

```
pfun = function()
	while true do
		local value = io.read()
		print("生产: ", value)
		coroutine.yield(value)
	end
end

cfun = function(p)
	while true do
		local _, value = coroutine.resume(p)
		print("消费: ", value)
	end
end

p = coroutine.create(pfun)
cfun(p) -- 消费者作为恢复方，需要持有让出方的coroutine引用，作为resume参数
```

这个例子本身很简单，甚至不大有必要强行用协程，但用协程的一大好处，就是有清晰生产者和消费者的边界，如果不使用协程，要么使用多线程，如此调度不受应用层控制，需要额外加队列缓冲和互斥机制，要么就在单线程内让生产者和消费者强耦合，如cfun中通过while循环去依次`io.read`，也就是将执行权的让出和恢复机制实现在一个function中(变成函数控制流跳转)，代价是降低可维护性(协程提供一种封装解耦的机制)。

另一个例子是关于模拟多线程下载文件的，每个协程下载一个文件，由我们控制各个协程的调度，当某个协程暂时没有数据可读时(非阻塞IO)，挂起(yield)自己，返回到调度器，开始调度(resume)下一个协程。这样总是能保证将时间片分给读取数据的协程上，而不是等待数据的协程上。不过这样有个小问题是，当所有协程都没有数据可读时，分配器将进入忙查询，这样会空转CPU，这可以通过select函数来优化，在所有协程都没有数据时，让出CPU。最终代码如下：

```
socket = require "socket"

-- 下载文件 在超时时挂起(返回: 连接c) 在接收完成时结束协程(返回: nil)
function download(host, file)
	local c, err = assert(socket.connect(host, 80))
	if err then print("-- connect host", file, "error: ", err) end
	local count = 0
	c:send("GET ".. file .. " HTTP/1.0\r\n\r\n")
	while true do
		local s, status = receive(c)	
		if status == "closed" then break end
		if s then 
			count = count + string.len(s) 
			break 
		end 
	end
	c:close()
	print("-- download ", file, " completed. file size: ", count)
end

function receive(conn)
	conn:settimeout(0) -- 设置非阻塞模式，协程想要在应用层让出执行权，当然需要非阻塞/异步操作的支持
	local s, status = conn:receive("*a")
	if status == "timeout" then -- 暂时无数据可读
		coroutine.yield(conn) -- 这里让出了执行权，执行权将直接跳转到resume方，也就是dispatcher
								  -- 待dispatcher觉得可能有数据可读，再恢复执行权到这里
	end
	return s, status
end

-- 保存所有协程
local threads = {}
-- 创建一个协程 对应下载一个文件
function get(host, file)
	local co = coroutine.create(function() 
		download(host, file)
	end)

	table.insert(threads, co)
end

-- 调度线程
function dispatcher()
	while true do
		local conns = {}
		local n = #threads
		if n == 0 then break end
		for i = 1,n do
			local status, c = coroutine.resume(threads[i])
			if not c then -- 接收数据完成 即download 函数正常返回
				table.remove(threads, i) -- 移除协程
				break -- 重新遍历
			else
				table.insert(conns, c)
			end
		end
		if #conns > 0 then
			socket.select(conns) -- 阻塞直到有socket读就绪，这里简单起见，未处理返回值，只是在select结束后，尝试resume所有的threads
		end
	end
end

get("www.baidu.com", "/index.html")
get("tieba.baidu.com", "/index.html")
get("news.baidu.com", "/index.html")

dispatcher()
```




