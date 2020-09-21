---
layout: post
title: c++ disruptor 无锁消息队列
categories:
- c/c++
---

前段时间关注到[disruptor][1]，一个高并发框架。能够在无锁(lock-free)的情况下处理多生产者消费者的并发问题。它可以看作一个消息队列，通过[CAS][2]而不是锁来处理并发。

因此实现了一个C++版本的disruptor，基于ring buffer，实现一个发送缓冲(多生产者，单消费者)。

### 写入缓冲

某个生产者要写入数据时，先申请所需空间(需要共享当前分配位置)，然后直接执行写入，最后提交写入结果(需要共享当前写入位置)。整个写入过程由两个关键共享变量: `atomic_ullong _alloc_count`和`atomic_ullong _write_count`。前者负责管理和同步当前分配的空间，后者负责同步当前已经写入的空间。也就是说，整个过程分为三步：申请，写入，提交。

比如，有两个生产者P1和P2。P1申请到大小为50的空间，假设此时\_alloc\_count=10，那么P1将得到可写入位置10，此时\_alloc\_count更新为60。P1此时可以执行写入(无需上锁)。这个时候P2开始申请大小为10的空间，它将得到写入位置60，\_alloc\_count更新为70。因此实际上P1和P2是可以并发写的。如果P2比P1先写完，它会尝试提交，此时由于P1还没有提交它的写入结果，因此P2会自旋等待(不断尝试CAS操作)。直到P1提交写入结果后，P2才能提交。通过CAS可以保证这种提交顺序。提交操作会更新\_write\_count变量，提交之后的数据便可以被消费者读取使用。

上面的描述并没有提到缓冲区不够的问题，为了判断缓冲区当前可写空间，还需要一个变量 `atomic_ullong _idle_count`用于记录当前缓冲区空闲大小。该变量在生产者申请空间后减小，在消费者使用数据后变大。初始等于整个ring buffer的大小。

<!--more-->

### 核心代码

```
SendBuffer::SendBuffer(size_t capacity /* = 65536 */)
{
    size_t fix_capacity = 16;
    while (fix_capacity < capacity)
        fix_capacity <<= 1;

    _capacity = fix_capacity;
    _capacity_mask = _capacity - 1;

    _buffer = new char[_capacity];

    _alloc_count = 0;
    _read_count = 0;
    _write_count = 0;
    _idle_count = _capacity;
}

SendBuffer::~SendBuffer()
{
    delete []_buffer;
}

bool SendBuffer::Push(const char* data, size_t len)
{
    if (nullptr == data || len == 0 || len > _capacity)
        return false;

    auto idle = _idle_count.fetch_sub(len);
    if (idle >= len)
    {
        // 1.申请写入空间
        auto alloc_start = _alloc_count.fetch_add(len);
        auto alloc_end = alloc_start + len;

        // 2.执行写入
        auto fix_start = alloc_start & _capacity_mask;
        auto fix_end = alloc_end & _capacity_mask;
        if (fix_start < fix_end)
        {
            memcpy(_buffer + fix_start, data, len);
        }
        else// 分两段写
        {
            auto first_len = _capacity - fix_start;
            memcpy(_buffer + fix_start, data, first_len);
            memcpy(_buffer, data + first_len, fix_end);
        }

        // 3.提交写入结果
        while (true)
        {
            auto tmp = alloc_start;
            if (_write_count.compare_exchange_weak(tmp, alloc_end))
                break;
        }
        return true;
    }
    else
    {
        _idle_count.fetch_add(len);
        return false;
    }
}

char* SendBuffer::Peek(size_t& len)
{
    if (_read_count < _write_count)
    {
        auto can_read = _write_count - _read_count;
        auto fix_start = _read_count & _capacity_mask;
        auto fix_end = (_read_count + can_read) & _capacity_mask;
        if (fix_start >= fix_end) 
        {
            // 只返回第一段
            can_read = _capacity - fix_start;
        }
        len = static_cast<size_t>(can_read);
        return _buffer + fix_start;
    }
    return nullptr;
}

bool SendBuffer::Pop(size_t len)
{
    if (_read_count + len <= _write_count)
    {
        _read_count += len;
        _idle_count.fetch_add(len);
        return true;
    }
    return false;
}
```

代码看起来不多，理解起来也不难。主要有以下三点：

#### 1. 对原子变量的访问

对原子变量的使用要特别小心，由于没有锁的保护，对原子变量的每一次访问都要考虑到它的值已经改变。比如在Push函数的申请空间操作中，你不能通过

```	
if(_idle_count > len)
{
	_idle_count.fetch_sub(len)
}
```

来判断空闲空间是否足够，因为在if中它可能大于len，但是当你执行`_idle_count.fetch_sub(len)`时，它的值可能就改变了，不再满足 > len。同理以下代码也是错的：

```
_idle_count.fetch_sub(len);
if(_idle_count > 0)
{
	//....
}
```

对原子变量的访问应该做到"原子性"，即每次逻辑上使用，都只访问一次。这也是和传统锁不一样的地方。而引进\_idle\_count这个原子变量而不是使用\_read\_count和\_alloc\_count来算出空闲空间(`_capacity-(_alloc_count-_read_count)`)也是基于这个原因，多个生产者依赖于这个表达式的值，并且会对表达式的值造成更改(修改\_alloc\_count)，就会导致P1读取表达式值后，判断空闲空间足够，在P1更改\_alloc\_count前，P2生产者更改\_alloc\_count分配了空间，使得空闲空间已经不足。这种读写分步的操作必须通过原子变量来保证访问的一致性。

而为什么我们在Peek中可以通过`_write_count - _read_count`来得到当前可读数据，是因为我们只有一个消费者依赖于`_write_count - _read_count`的值，并且其它生产者对\_write\_count做出的更改对消费者来说是"无害的"，即生产者只会使\_write\_count增加，让消费者读到更多的数据。

#### 2. 通过CAS保证顺序提交

在Push函数中的第三步提交中，生产者自旋等待，直到它前面(按照申请顺序)的所有生产者都已提交完毕，此时\_write\_count即为本生产者的写入位置alloc\_start，代表alloc\_start之前的缓冲区都已经提交完成，此时该你提交写入结果了。提交完成之后，更新\_write\_count，而消费者则根据\_write\_count来判断哪些内容是可读的。

#### 3. 单消费者无需原子变量

最后，由于只有一个消费者，因此\_read\_count不是原子变量。它只会在Peek和Pop中读取和修改。

源码地址：https://github.com/wudaijun/Code/tree/master/Demo/disruptor

[1]: http://ifeve.com/disruptor/ "disruptor"
[2]: http://coolshell.cn/articles/8239.html "compare and swap"
