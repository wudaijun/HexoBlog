Go的GC分为如下几个阶段:

![](/assets/image/go/go-gc-phases.png "")

### 写屏障(write barrier)

在Go1.8之前，Go使用Dijkstra-style insertion write barrier [Dijkstra ‘78]来完成在Mark过程中，用户程序对指针的赋值和覆盖追踪，该方案的优点是无需读屏障(read barrier)，但保守地将有变更的栈标记为灰色，这样在第一遍Mark之后，还需要re-scan所有灰色的栈，re-scan是Stop the world的(否则这个过程还会有栈变更)，这个过程在有大量goroutine的情况下会耗时10ms-100ms。

Go1.8及之后采用另一种混合屏障(hybrid write barrier that combines a Yuasa-style deletion write barrier [Yuasa '90] and a Dijkstra-style insertion write barrier [Dijkstra '78]. )，以消除re-scan过程，详细参考[17503-eliminate-rescan](https://github.com/golang/proposal/blob/master/design/17503-eliminate-rescan.md)。

GC Mark 1:

- 准备阶段: 包括为每个调度器(P)开启write barrier，将所有全局对象和栈对象(root object)push到灰对象队列(work queue)，整个过程是Stop the world的
- Start the world, 由mark workers在后台递归完成对灰对象的解析(scan)，在这个过程中，用户程序新创建的对象被标记为黑色
- 扫描所有堆栈，全局变量，每扫描一个堆栈，都会停止对应goroutine，收集其上所有对象，然后恢复goroutine。
- 处理灰色对象队列，对每个灰色对象，扫描其所有引用并加入灰色队列，将自身置为黑色，重复该过程。直到灰色队列为空。这个过程称为GC drains(排水)。

在整个Mark 1过程中，调度器允许有自己的缓存对象队列(work buffer)，这样避免了对全局队列的竞争。

GC Mark 2:

当全局队列中的灰色对象处理完了后，还需要处理各调度器内部的work buffer，guan'bi
- 



当Mark开始后，新分配的对象将为黑色。
并发sweep，因此off阶段包含了sweep。







## 参考

1. [http://www.cnblogs.com/zkweb/p/7880099.html]()
2. [http://legendtkl.com/2017/04/28/golang-gc/]()
3. [https://en.wikipedia.org/wiki/Tracing_garbage_collection]()
4. [https://golang.org/ref/mem]()
5. [https://github.com/golang/proposal/blob/master/design/17503-eliminate-rescan.md]()
6. [http://0xffffff.org/2017/02/21/40-atomic-variable-mutex-and-memory-barrier/]()
 