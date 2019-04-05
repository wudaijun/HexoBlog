---
title: Linux Perf 简单试用
layout: post
categories: linux
tags: linux
---

Perf(Performance Event)是Linux 2.6.31后内置的性能分析工具，它相较其它Prof工具最大的优势在于与Linux Kernel紧密结合，可以进行内核甚至硬件级的性能分析。我之前只零散地用一些`ptrace`,`strace`之类的小工具，与Perf比起来，确实小巫见大巫。也赶紧花了点时间简单了解和试用一下，添加到工具箱，以备不时之需。

<!--more-->

几乎所有的性能分析工具的基本原理都是对监测目标进行数据采样，Perf也不例外，Perf可以基于各种Event对目标进行测样。如基于时间点(tick)采样，可以得到程序运行时间的分布，即程序中哪些函数最耗时。基于cache miss采样，可以得到程序的cache miss分布，即cache失效经常发生在哪些代码中。通过`perf list`可以Perf支持的各种Event:

```
$ sudo perf list                                                                                                                                                             List of pre-defined events (to be used in -e):

 cpu-cycles OR cycles                       [Hardware event]
 instructions                               [Hardware event]
 cache-references                           [Hardware event]
 cache-misses                               [Hardware event]
 branch-instructions OR branches            [Hardware event]
 branch-misses                              [Hardware event]
 bus-cycles                                 [Hardware event]

 cpu-clock                                  [Software event]
 task-clock                                 [Software event]
 page-faults OR faults                      [Software event]
 minor-faults                               [Software event]
 major-faults                               [Software event]
 context-switches OR cs                     [Software event]
 cpu-migrations OR migrations               [Software event]
 alignment-faults                           [Software event]
 emulation-faults                           [Software event]

 [...]

 sched:sched_stat_runtime                   [Tracepoint event]
 sched:sched_pi_setprio                     [Tracepoint event]
 syscalls:sys_enter_socket                  [Tracepoint event]
 syscalls:sys_exit_socket                   [Tracepoint event]

 [...]
```

该列表非常长，以上是简化之后的输出结果，可以将Perf Event大致分为三类:

1. Hardware Event: 主要是由CPU或PMU硬件产生的事件，如cache-misses, cpu-cycle, instructions, branch-misses等。
2. Software Event: 由内核软件产生的事件，如 page-faults, context-switches, cpu-migrations等。
3. Tracepoints: 散布在内核源码中的各种静态的追踪点(Hook)，Perf可以通过挂载Hook来收集这些事件。如kmalloc, syscall, sched_switch等。

PMU(Performance Monitoring Unit) 是各CPU厂商随CPU提供的硬件，它允许软件针对某种CPU硬件事件(如cache miss, branch-misses, instructions)设置counter，并且统计该事件次数，当次数到达counter值后，产生中断。软件通过捕获这些中断来考察CPU使用情况。

### perf top

`perf top` 用于实时显示当前系统的性能统计信息，用于观察整个系统的当前状态。我们先写一个简单的死循环程序:

```c
void run_forever() {
        long int i = 0;
        while(1) {
                i++;
        }
}

int main() {
        run_forever();
        return 0;
}
```

编译并执行它: `gcc -o t1 -g t1.c && ./t1`，然后在另一个窗口执行`perf top`:

```
Samples: 249K of event 'cycles:ppp', Event count (approx.): 59571881744
Overhead  Shared Object             Symbol
  92.24%  t1                        [.] run_forever
   0.49%  [kernel]                  [k] menu_select
   0.44%  cadvisor                  [.] runtime.findObject
   0.36%  [kernel]                  [k] nmi
   0.29%  game                      [.] runtime.scanobject
   0.28%  cadvisor                  [.] runtime.scanobject
   0.25%  cadvisor                  [.] runtime.(*mspan).nextFreeIndex
   0.24%  [kernel]                  [k] vsnprintf
   0.21%  [kernel]                  [k] __switch_to
   ...
```

默认情况下，`perf top`命令将采样cpu-cycles Event，即每个时钟周期进行采样，对所有CPU正在执行的代码(Symbol)进行统计(包括内核代码)，并按照出现次数降序排列。因此`perf top`打印的是CPU运行时间分布，即哪些函数最耗时。上图清楚指明了目前该机器上最耗时的进程(Shared Object)为t1，以及其热点函数(Symbol)为`run_forever`。在`perf top`界面按[h]键可以呼叫帮助菜单，看到所有可用的功能何对应的快捷键。选中t1一行，按[a]键即可启用Annotate(注释)功能，它可以进一步查看当前符号:

```
run_forever  /home/docker/test/t1
Percent│
       │
       │
       │    Disassembly of section .text:
       │
       │    00000000000005fa <run_forever>:
       │    run_forever():
       │    void run_forever() {
       │      push   %rbp
       │      mov    %rsp,%rbp
       │            long int i = 0;
       │      movq   $0x0,-0x8(%rbp)
       │            while(1) {
       │                    i++;
 99.95 │ c:   addq   $0x1,-0x8(%rbp)
  0.05 │    ↑ jmp    c
```

可以看到该函数 99.94% 的时间都在执行 i++ 这一行。

当然，你也通过参数指定`perf top`采样其它Event(比如cache-misses)并设置其采样速率(比如改为每秒5000次，默认是4000):

```
$ perf top -e cache-misses -c 5000
```

`perf top` 适用于做系统的整体状态统计，然后初步定位到问题进程。当然，由于我们的示例代码太简单，通过`perf top`就足以分析出问题进程和问题代码。而当情况更复杂时，我们则需要其它perf工具的配合。

### perf stat

当你想要分析指定应用程序各方面性能时，可以用`perf stat`命令，我们仍然通过一段程序来说明:

```
static char array[10000][10000];
int main (void){
        int i, j;
        for (i = 0; i < 10000; i++)
            for (j = 0; j < 10000; j++)
                 array[i][j]=i;
                 return 0;
}
```

现在我们通过`perf stat`来对这个程序的一些事件进行采样:

```
$ gcc -o t2 t2.c
$ sudo perf stat -r 5 -e cache-misses,cache-references,instructions,cycles,L1-dcache-stores,L1-dcache-store-misses ./t

 Performance counter stats for './t2' (5 runs):

         3,340,700      cache-misses              #    2.631 % of all cache refs      ( +-  0.25% )
       126,973,736      cache-references                                              ( +-  0.02% )
     1,471,226,871      instructions              #    0.40  insn per cycle                                              ( +-  0.01% )
     3,643,287,243      cycles                                                        ( +-  0.59% )
       219,156,878      L1-dcache-stores                                              ( +-  0.01% )
       102,035,758      L1-dcache-store-misses                                        ( +-  0.01% )

       1.026604322 seconds time elapsed                                          ( +-  0.58% )                                        ( +-  0.26% )
```

`-r`指定重复执行次数，可以保证采样结果的可参考性。`-e`指定要采样的Event，如果指定了cache-misses/cache-reference,cycles/instructions这类成对的Event时，perf会自动计算相关比例值。另外，cache-references/misses指的是Last Level Cache(LLC) references/misses。

结果显示程序执行时间为1.02s,CPU每个时钟周期可以执行0.4条指令，看这些你可能无法直观地判断程序优劣，但是如果我们善用数据局部性，将`array[j][i] = i`改为`array[i][j] = i`，再来看看结果:

```
 Performance counter stats for './t2' (5 runs):

         1,693,216      cache-misses              #   96.113 % of all cache refs      ( +-  0.05% )
         1,761,695      cache-references                                              ( +-  0.13% )
     1,470,420,403      instructions              #    1.54  insn per cycle                                              ( +-  0.01% )
       955,043,789      cycles                                                        ( +-  0.03% )
       218,964,664      L1-dcache-stores                                              ( +-  0.01% )
         1,790,183      L1-dcache-store-misses                                        ( +-  0.03% )

       0.271631085 seconds time elapsed                                          ( +-  0.41% )                                       ( +-  0.27% )
```

cache-misses数量降了一倍，L1-dcache-store-misses更是降了几十倍，insn per cycle由0.52提升到了1.54，亦即CPU利用率更高了，程序整体运行速度快了接近5倍。但你可能会注意到，程序改动后，`cache-misses/cache-references`的比例从2.63%提升到96.113%，cache命中率降低了？花了很长时间Google后(perf对各种Event的文档太稀缺了，基本没有一份相对详细的Event文档)，[这篇问答](https://stackoverflow.com/questions/55035313/how-does-linux-perf-calculate-the-cache-references-and-cache-misses-events)中提到如果存取在L1-dcache-stores命中，则不会记入cache-references，因此当程序数据局部性提升后，在L1层就已经能取到了，也就导致cache-references急剧减少，相对也就导致`cache-misses/cache-references`比例反而上升了。

`perf stat`也可以通过`-p`附加到正在运行中的进程

```
# 附加到指定进程采样3秒
$ perf stat -p PID sleep 3
# 附加到指定进程，直到目标进程结束，或Ctrl+C终止
$ perf stat -p PID
```

### perf record/report

`perf record`可以将指定采样数据采样到文件，参数与`perf stat`类似，可以接可执行文件或附加到指定进程，只不过没有任何输出，而是将采样数据写入到perf.data文件中。与之相匹配的，`perf report`可以将文件中采样数据展示出来。我们仍然以t2.c为例:

```
sudo perf record -e cache-misses:u ./t2
sudo perf report
Samples: 1K of event 'cache-misses:u', Event count (approx.): 1627272
Overhead  Command  Shared Object     Symbol
  96.48%  t2       t2                [.] main
   3.27%  t2       [kernel]          [k] page_fault
   0.11%  t2       ld-2.27.so        [.] 0x000000000000d305
   0.11%  t2       ld-2.27.so        [.] 0x00000000000109b8
   0.03%  t2       ld-2.27.so        [.] 0x0000000000018d7d
   0.00%  t2       ld-2.27.so        [.] 0x0000000000002082
   0.00%  t2       ld-2.27.so        [.] 0x0000000000001ea0
```

96.48的 cache-misses Event都分布在main函数中，同样，可以通过上下键选中main函数Enter进入并选择"Annotate main"，可以看到汇编代码级的cache-misses分布(通过 `gcc -g -o t2 t2.c` 可以保留汇编到代码的符号映射):

```
Percent│    Disassembly of section .text:
       │
       │    00000000000005fa <main>:
       │    main():
       │    static char array[10000][10000];
       │    int main (void){
       │      push   %rbp
       │      mov    %rsp,%rbp
       │            int i, j;
       │            for (i = 0; i < 10000; i++)
       │      movl   $0x0,-0x8(%rbp)
       │    ↓ jmp    4d
       │                for (j = 0; j < 10000; j++)
       │ d:   movl   $0x0,-0x4(%rbp)
       │    ↓ jmp    40
       │                     array[j][i]=i;
  1.16 │16:   mov    -0x8(%rbp),%eax
       │      mov    %eax,%ecx
       │      mov    -0x8(%rbp),%eax
       │      cltq
  0.68 │      mov    -0x4(%rbp),%edx
  0.10 │      movslq %edx,%rdx
       │      imul   $0x2710,%rdx,%rdx
       │      add    %rax,%rdx
  1.06 │      lea    array,%rax
       │      add    %rdx,%rax
       │      mov    %cl,(%rax)
       │                for (j = 0; j < 10000; j++)
 76.54 │      addl   $0x1,-0x4(%rbp)
  0.48 │40:   cmpl   $0x270f,-0x4(%rbp)
 19.98 │    ↑ jle    16
       │            for (i = 0; i < 10000; i++)
       │      addl   $0x1,-0x8(%rbp)
       │4d:   cmpl   $0x270f,-0x8(%rbp)
       │    ↑ jle    d
       │                     return 0;
       │      mov    $0x0,%eax
       │    }
       │      pop    %rbp
       │    ← retq
```

而如果将代码改成局部友好，main函数将不会出现在`perf report`的列表中。`perf record/report`用法与现在的主流prof工具类似，这种方式最灵活，对环境的各种要求也低。

在学习过程中也发现Perf一些不足之处，首先就是文档很少，特别关于各种Event，因为它们很多与具体硬件实现相关。第二就是与Linux内核深度结合，是优点也是缺点，因为这也意味着它的跨平台性不是很好。因此它更像是Linux系统级的Prof工具，对于应用级的分析，Perf可能是有点过于底层和重量级了。

参考资料:

1. [Linux kernel profiling with perf](https://perf.wiki.kernel.org/index.php/Tutorial)
2. [Perf -- Linux下的系统性能调优工具，第 1 部分](https://www.ibm.com/developerworks/cn/linux/l-cn-perf1/index.html)
3. [ManPage of PERF\_EVENT\_OPEN](http://web.eece.maine.edu/~vweaver/projects/perf_events/perf_event_open.html)
