---
layout: post
title: lua协程
categories:
- lua
tags:
- lua
---

协程是一种用户级的非抢占式线程。用户级是指它的切换和调度由用户控制，非抢占指一个协程只有在其挂起(yield)或者协程结束才会返回。协程和C线程一样，有自己的堆栈，自己的局部变量，自己的指令指针，并且和其它协程共享全局变量等信息。用户可以实现自己调度协程，这主要得益于yield函数可以自动保存协程当前上下文，这样当挂起的协程被唤醒(resume)时，会从yield处继续向下执行，看起来就像是一个"可以返回多次的函数"。协程还有一个强大的功能就是可通过resume/yield来交换数据，这样使得它可以用于异步回调：当执行异步代码时，切换协程，执行完成后，再切换回来(附带异步执行结果)。由于切换都是用户控制的，在同一时刻只有一个协同程序在运行(这也是和传统线程最大的区别之一)，因此无需考虑同步和加锁的问题。

<!--more-->

### 两个例子

pil上关于协程有两个很好的例子。

在生产者消费者例子中，当消费者需要生产者的数据时(相当于一个异步回调)，切换到生产者协程(resume)，生产者开始运行，生产完成后，挂起自己(yield)并且传入生产的数据。此时调度回到消费者协程中，消费者从resume的返回值中得到数据，使用数据，在需要数据时再次唤醒生产者。这样我们像写同步代码一样(resume相当于函数调用，yield相当于函数返回)，完成了异步功能。而无需考虑传统生产者和消费者模型中的同步问题，因为执行顺序都由我们严格控制的。代码如下：

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
cfun(p)
```

还有个例子是关于模拟多线程下载文件的，每个协程下载一个文件，由我们控制各个协程的调度，当某个协程暂时没有数据可读时(异步读取)，挂起(yield)自己，返回到调度器，开始调度(resume)下一个协程。这样总是能保证将时间片分给读取数据的协程上，而不是等待数据的协程上。当所有协程都没有数据可读时，分配器将进入忙查询，这样会空转CPU，可以通过select函数来优化，在所有协程都没有数据时，让出CPU。最终代码如下：

```
socket = require "socket"

-- 下载文件 在超时时挂起(返回: 连接c) 在接收完成时结束协程(返回: nil)
function download(host, file)
	local c = assert(socket.connect(host, 80))
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
	conn:settimeout(0)
	local s, status = conn:receive("*a")
	if status == "timeout" then
		coroutine.yield(conn)
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
		if #conns == n then
			socket.select(conns)
		end
	end
end

get("www.baidu.com", "/index.html")
get("wudaijun.com", "/2014/12/shared_ptr-reference/")
get("wudaijun.com", "/2014/11/cpp-constructor/")

local start = os.time()
dispatcher()
local cost = os.time()-start
print("-- cost time: ", cost)
```



