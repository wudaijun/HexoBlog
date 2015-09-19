---
layout: post
title: NGServer Session设计
categories:
- gameserver
tags:
- NGServer
---

在网络编程模型中，一个Session代表一次会话，主要维护网络数据的发送和接收。对外提供发送数据和处理数据的接口。一个高效的Session主要通过缓冲和异步来提高IO效率。NGServer的Session运用双缓冲和boost::asio的异步机制，很好地做到了这一点。

<!--more-->

## 一. 双缓冲
在网络IO中，读写线程的互斥访问一直都是一个关乎性能的大问题。为了减少互斥锁的使用，环形缓冲和双缓冲是常见的策略。NGServer使用后者作为消息和数据缓冲。
在NGServer MessageQueue.h中，定义了两种双缓冲：基于消息的MessageQueue和基于数据的ByteBuff。下面简要介绍ByteBuff类：

ByteBuff类的基本思想是通过两个缓冲区\_buff\_read和\_buff\_write来使读写分离。通过`size_t Push(const char* data, size_t len)`来写入数据：

```
// 压入字节流数据 压入成功 则返回当前缓冲区长度 否则返回0
size_t Push(const char* data, size_t len)
{
	if(data != nullptr && len > 0)
	{
		AutoLocker aLock(&_lock);
		if(_size+len <=  _capacity)
		{
			memcpy(_buff_write+_size, data, len);
			return _size += len;
		}
	}
	return 0;
}
```

Push方法是线程安全的，它通过AutoLocker来保证对\_buff\_write的互斥访问。
  
`char* PopAll(size_t& len)`用于读取数据:

```
// 返回当前缓冲区指针 长度由len返回 若当前缓冲区无消息 返回nullptr
char* PopAll(size_t& len)
{
	if(_size > 0)
	{
		AutoLocker aLock(&_lock);
		if(_size > 0)
		{
			swap(_buff_read, _buff_write);
			len = _size;
			_size = 0;
			return _buff_read;
		}
	}
    len = 0;
	return nullptr;
}
```
	
它返回当前\_buff\_write的指针，并且交换\_buff\_write和\_buff\_read的指针，这样下次再Push数据时，实际上写到了之前的\_read\_buff中，如此交替，完成读写分离。

需要注意到，Push接口是线程安全的，而对于PopAll：
由于PopAll直接返回缓冲区指针(避免内存拷贝)，因此同一时刻双缓冲中，必有一读一写，故同一时刻只能有一个线程读取和处理数据(处理数据时,\_buff\_read仍然是被占用的)。读取线程需要将上次PopAll的数据处理完成之后再次调用PopAll。因为调用PopAll时，之前的读缓冲已变成写缓冲，并且写缓冲将从头开始写。

基于消息的MessageQueue原理与ByteBuff一样，只不过\_buff\_read和\_buff\_write均为vector<MsgT\*>\* 类型。MsgT是用户定义的消息类。由于使用的MsgT*，提高效率的同时，需要注意消息的释放问题。这在使用到MessageQueue时再提。

## 二. Session类的设计

Session类利用boost::asio异步读写提高IO性能，它使用线性缓冲作为接收缓冲，使用ByteBuff作为发送缓冲，提高发送性能。由于ByteBuff同一时刻只能由一个线程读取和处理，Session需要使用一个锁来保证同一时刻只有一个线程来读取ByteBuff并发送其中的数据：

```
// 发送数据
bool Session::SendAsync(const char* data, size_t len)
{
	if (!_run)
	return false;

	if (_send_buf.Push(data, len))
	{
		if (_sending_lock.TryLock())
		{
			size_t sendlen;
			const char* data = _send_buf.PopAll(sendlen);
			// 异步发送数据 同一时刻仅有一个线程调用该函数
			SendData(data, sendlen);
			return true;
		}
	}
	else
		assert(0); // 发送缓冲区满
}

void Session::SendComplete(const boost::system::error_code& err, size_t bytes_to_transfer, size_t bytes_transferred)
{
	if (err)
	return;

	assert(bytes_to_transfer == bytes_transferred);

	_send_total += bytes_transferred;

	size_t len;
	const char* data = _send_buf.PopAll(len);
	if (data) // 如果还有数据  继续发送
	{
		SendAsync(data, len);
	}
	else
	{
		_sending_lock.UnLock();
	 	}
}
```
    
当网络空闲时，在SendAsync中，消息通过Push压入缓冲区后，将即时发送。当网络IO繁忙时，调用SendAsync中，可能已有数据正在发送，在将新数据压入缓冲区后，_sending_lock.TryLock()将返回false，此时数据被放在缓冲区中。待已有数据发送完成后，_sending_lock解锁。那么下次调用SendAsync发送的数据将和缓冲区中已有的数据立即发送。而ByteBuff双缓冲最大程度避免了这个过程中的内存拷贝。

Session将收到的数据放在线性缓冲区中，如此方便解包。在每次接收数据完成后，都尝试解包，并校正缓冲区新的偏移。
