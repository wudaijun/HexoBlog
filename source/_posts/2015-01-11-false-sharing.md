---
layout: post
title: false sharing
categories:
- GameServer
tags:
- multi-thread
---
在多核的CPU架构中，每一个核心core都会有自己的缓存行(cache line)，因此如果一个变量如果同时存在不同的核心的cache line时，就会出现伪共享（false sharing)的问题。此时如果一个核心修改了该变量，该修改需要同步到其它核心的缓存。

<!--more-->

![](/assets/cache-line.png "cache-line示意图")

上图说明了伪共享的问题。在核心1上运行的线程想更新变量X，同时核心2上的线程想要更新变量Y。不幸的是，这两个变量在同一个缓存行中。每个线程都要去竞争缓存行的所有权来更新变量。如果核心1获得了所有权，缓存子系统将会使核心2中对应的缓存行失效。当核心2获得了所有权然后执行更新操作，核心1就要使自己对应的缓存行失效。这会来来回回的经过L3缓存，大大影响了性能。如果互相竞争的核心位于不同的插槽，就要额外横跨插槽连接，问题可能更加严重。 

我们可以通过padding来确保两个共享变量不位于同一个cache-line中，这对于链表等传统结构的共享(首尾节点通常位于同一cache-line)有重大意义。如下面这个例子：

```

#include<thread>
#include <iostream>

using namespace std;

struct foo {
    int x;

/*
    int64_t pad1;
    int64_t pad2;
    int64_t pad3;
    int64_t pad4;
    int64_t pad5;
    int64_t pad6;
    int64_t pad7;
    int64_t pad8;
    int64_t pad9;
    int64_t pad10;
    int64_t pad11;
    int64_t pad12;
    int64_t pad13;
    int64_t pad14;
    int64_t pad15;
    int64_t pad16;
*/    

    int y;
};

static struct foo f;

void sum_a(void)
{
    clock_t start = clock();
    int s = 0;
    int i;
    for (i = 0; i < 1000000000; ++i)
        s += f.x;

    cout << "sum_a cost: "<< clock()-start << "ms"<< endl;
}

void inc_b(void)
{
    clock_t start = clock();
    int i;
    for (i = 0; i < 1000000000; ++i)
        ++f.y;

    cout << "inc_b cost: "<< clock()-start << "ms"<< endl;
}

int main()
{
    std::thread t1(sum_a);
    std::thread t2(inc_b);

    t1.join();
    t2.join();
    return 0;
}
```

未添加padding时，在我的机器上运行结果为：
	
	inc_b cost: 4692ms
	sum_a cost: 5722ms

添加padding后，运行结果为：

	inc_b cost: 2161ms
	sum_a cost: 2194ms
