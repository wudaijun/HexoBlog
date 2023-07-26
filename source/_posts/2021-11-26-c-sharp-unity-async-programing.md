---
title: C#/Unity中的异步编程
layout: post
categories: c#
tags:
- c#
- unity
- coroutine
- async programing
---

这段时间学习Unity，顺便系统性地了解了下C#和Unity异步编程的各种机制和实现细节。本文是这些学习资料和个人理解的汇总。会先介绍下C# yield，Task，async/await，同步上下文等机制。然后聊聊其在Unity上的一些变体和应用。

<!--more-->

### C# yield

`yield`是C#提供的快速创建枚举器的机制:

```C#
public static IEnumerable<int> TestYield(int a)
{
    yield return a+1;
    if (a % 2 == 0) {
        yield break;
    }
    else {
        yield return 1;
    }
    yield return 2;
}
static void Main(string[] args)
{
    IEnumerator<int> enumerator = TestYield(4).GetEnumerator();
    while (enumerator.MoveNext())
    {
        Console.WriteLine(enumerator.Current);
    }
}
// Output:
// 5
```

实现上来说，C#编译器会为TestYield函数生成一个状态机类，将函数执行体通过yield分为几个部分，内部通过一个state字段(通常是个整数)来标识当前迭代到哪一步了，并实现了IEnumerable、IEnumerator枚举器接口。因此可以将TestYield返回值作为一个可枚举对象。介绍关于yield语法糖实现机制的文章很多，这里就不赘述了。

C# 枚举器和JS Generator机制上非常类似，不过只具备单向传值的能力(yield->MoveNext)。我在[JS异步编程](http://wudaijun.com/2018/07/javascript-async-programing/)和[Lua协程](https://wudaijun.com/2015/01/lua-coroutine/)中有介绍关于协程和生成器的区别，在我的理解中，C#枚举器和JS生成器一样，都不能算作协程。

### Unity Coroutine

C#没有协程，而Unity C#中则经常看到协程的概念(Unity Coroutine)，本质上来说，Unity Coroutine是和JS Generator类似的通过生成器/枚举器实现异步的编程模型。Unity基于C# yield进行了进一步完善:

1. Unity协程通过Unity Engine提供的`StartCoroutine(myEnumerableFunc)`启动，Unity Engine会驱动枚举器的迭代，无需开发者关心
1. Unity协程基于yield返回的对象，只能是YieldInstruction的子类(它最重要的方法是bool IsDone()，用于判断异步操作是否已经完成)，如此Unity Engine会在YieldInstruction完成后，通过MoveNext迭代枚举器
3. Unity Engine预实现了部分YieldInstruction，如WaitForSeconds，WaitForEndOfFrame等，以实现常用的协程控制
4. Unity Engine完善了协程(枚举器)生命周期管理(Start/Stop)和嵌套机制(如一个协程yield另一个协程)，并将协程的生命周期与GameObject绑定

关于Unity Coroutine的更深入实现原理推荐[这篇博客](https://sunweizhe.cn/2020/05/08/%E6%B7%B1%E5%85%A5%E5%89%96%E6%9E%90Unity%E5%8D%8F%E7%A8%8B%E7%9A%84%E5%AE%9E%E7%8E%B0%E5%8E%9F%E7%90%86/)。如此，对于Unity开发者而言，使用yield就能完成简单的异步控制。当然，还达不到JS Generator异步那样的灵活度(如C# yield不能像JS yield一样双向传值)。我们可以从[JS 异步编程](http://wudaijun.com/2018/07/javascript-async-programing/)中提到的Generator异步编程的四要素，来对比看看Unity Coroutine是如何工作的:

- Generator: C#的yield相当于JS Generator的阉割版，支持执行权转移，单向传值
- Thunk: Thunk的本质目的是让Iterator能以一种标准化的方式挂接回调(如此才能回到yield语句)，而Unity YieldInstruction本身就是一种标准，Unity会在YieldInstruction完成(IsDone()==true)后，调用对应协程的的MoveNext回到yield语句，这也就相当于完成了Thunk的职责
- AsyncOp: Unity Engine和它的标准库提供了大量适配了YieldInstruction的异步操作，包括帧控制、定时、网络IO等，并且支持开发者扩展
- Iterator: Unity Engine统一管理所有通过StartCoroutine启动的协程，并基于帧驱动检查它们的状态，在YieldInstruction异步操作完成后继续驱动协程(MoveNext)，直至协程生命周期结束。

由于C# yield是单向传值，Unity协程自然也就不支持yield语句返回值。如此看来，Unity C#确实具备部分的异步编程能力，不过如前面所说，基于个人对狭义的协程概念的理解，我认为程JS、C#、Unity支持协程是不合适的。类似的还有Golang的抢占式轻量级线程goroutine也被翻译为协程。

### C# Task

C#中的Task本质上类似JS中的Promise，表示一个异步任务，通常运行在其他线程而非创建Task的当前线程中。Task在启动(Task.Start/Task.Run/TaskFactory.StartNew)和ContinueWith的时候，可以选择指定其对应的TaskScheduler(对于ContinueWith而言，指定的是执行异步回调的任务调度器)，默认的TaskScheduler只会将任务放到线程池中去执行。

```C#
static void Main(string[] args) {
    int a = 888;
    int b = 111;
    var task = new Task<int>(() =>
    {
        Console.WriteLine("add task, on thread{0}", Thread.CurrentThread.ManagedThreadId);
        return a + b;
    });
    Console.WriteLine("main thread{0}, task{1} init status: {2}", Thread.CurrentThread.ManagedThreadId, task.Id, task.Status);
    task.Start();
    task.ContinueWith((task, arg) =>
    {
        Console.WriteLine("continue with 1, got result: {0}, got arg: {1}, on thread{2}", task.Result, arg, Thread.CurrentThread.ManagedThreadId);
    }, "Arg1").
    ContinueWith((task) =>
    {
        Console.WriteLine("continue with 2, on thread{0}", Thread.CurrentThread.ManagedThreadId);
    }).Wait();
}

// Output:
// main thread1, task1 init status: Created
// add task, on thread3
// continue with 1, got result: 999, got arg: Arg1, on thread4
// continue with 2, on thread5
```

以上代码展示了Task的几个特性:

1. 任务内部有个简单的状态机，其他线程可通过`Task.Status`获取任务当前状态
2. `Task.ContinueWith`返回值是一个新的Task，可以像`JS promise.then`一样，以可读性较好的方式(相比回调地狱)书写异步调用链
3. `task.ContinueWith`中的回调可以取到到task的返回值，并且可以为其附加额外的参数
4. `task.Wait`可以让当前线程同步阻塞等待该任务完成，除此之外，还可以通过`Task.WaitAny`和`Task.WaitAll`来等待一个任务数组
5. 在任务执行完成后，通过`task.Result`可以取得异步任务的返回值，注意，如果此时任务未完成，将会同步阻塞等待任务完成
6. 如果没有指定TaskScheduler，默认的任务调度器只是在线程池中随机选一个线程来执行异步任务和对应回调

有时候我们在线程A中将某些耗时操作，如网络IO，磁盘IO等封装为Task放到线程B异步执行之后，希望Task的回调在A线程执行(最典型的如UI线程，因为通常UI框架的API都不是线程安全的)，以实现A->B->A的线程上下文切换效果。要实现这种效果，我们需要为Task显式指定TaskScheduler，TaskScheduler本质只是接口，它的派生类主要有两个:

- thread pool task scheduler: 基于线程池的任务调度器，即任务(及其continuewith产生的新任务)会被分配到线程池中的某个工作线程，这也是默认的调度器，通过`TaskScheduler.Default`获取默认线程池调度器
- synchronization context task scheduler: 同步上下文调度器，即任务会在指定的同步上下文上执行，比如在GUI框架中，通常会将控件操作全部放到GUI线程中执行。通过`TaskScheduler.FromCurrentSynchronizationContext`获取与当前同步上下文绑定的任务调度器

那么什么是同步上下文？SynchronizationContext代表代码的执行环境，提供在各种同步模型中传播同步上下文的功能，为各个框架的线程交互提供统一的抽象。它最重要的是以下两个方法。

```
// 获取当前线程的同步上下文
public static System.Threading.SynchronizationContext? Current { get; }
// 派发一个异步到消息到当前同步上下文
public virtual void Post (System.Threading.SendOrPostCallback d, object? state);
// 派发一个同步消息到当前同步上下文
public virtual void Send (System.Threading.SendOrPostCallback d, object? state);
```

SynchronizationContext提供了默认的实现，对Post而言，它只会通过QueueUserWorkItem将任务丢给ThreadPool，对于Send而言，它会立即在当前线程上同步执行委托。

各个框架可以重载SynchronizationContext实现自己的同步上下文行为，如Windows Froms实现了`WindowsFormsSynchronizationContext`，它的Post会通过`Control.BeginInvoke`实现，而WPF的`DispatcherSynchronizationContext`则通过框架的`Dispatcher.BeginInvoke`实现，它们都实现了将委托异步投递给UI线程执行。正因为不同的平台，不同的线程，有不同的消息泵和交互方式，因此才需要SynchronizationContext来封装抽象这些差异性，以增强代码的可移植性。

每个线程都有自己的SynchronizationContext(通过`SynchronizationContext.Current`获取，默认为null)，但SynchronizationContext与线程不一定是一一对应的，比如默认的`SynchronizationContext.Post`是通过线程池来执行任务。SynchronizationContext本质上想要封装的是一个执行环境以及与该环境进行任务交互的方式。

对Task，TaskScheduler，SynchronizationContext有一定了解后，我们将这些概念结合起来:

```C#
static void Main(string[] args) {
{
    // 创建并设置当前线程的SynchronizationContext
    // 否则TaskScheduler.FromCurrentSynchronizationContext()调用会触发System.InvalidOperationException异常
    var context = new SynchronizationContext();
    SynchronizationContext.SetSynchronizationContext(context);
    Console.WriteLine("main thread{0}", Thread.CurrentThread.ManagedThreadId);
    Task<int> task = new Task<int>(() =>
    {
        Console.WriteLine("task thread{0}", Thread.CurrentThread.ManagedThreadId);
        return 1;
    });
    task.Start();
    task.ContinueWith(t =>
    {
        Console.WriteLine("continuewith result: {0}, thread{1}", t.Result, Thread.CurrentThread.ManagedThreadId);

    }, TaskScheduler.FromCurrentSynchronizationContext()).Wait();
}

// Output:
// main thread1
// task thread3
// continuewith result: 1, thread4
```

上面代码中，使用`TaskScheduler.FromCurrentSynchronizationContext()`来指定`task.ContinueWith`任务的调度器(注意，我们并没有为`task.Start`指定调度器，因为我们希望task本身使用默认的线程池调度器，当执行完成之后，再回到主线程执行ContinueWith任务)，输出结果并不如我们预期，`task.ContinueWith`中的回调委托仍然在线程池中执行，而不是在主线程。

这个结果其实很容易解释，`task.ContinueWith(delegate, TaskScheduler.FromCurrentSynchronizationContext())`表示: 当task执行完成后，通过`SynchronizationContext.Post(delegate, task)`将任务异步投递到指定的同步上下文(在上例中，即为主线程创建的上下文)。但是一来我们创建的是默认的SynchronizationContext，它的Post本身就是投递到线程池的，二来我们并没有在主线程中集成消息泵(message pump)。

类比Actor模型，我们要实现 Actor A 向 Actor B 通信，我们需要: 

1. 定义一个消息通道: channel/mailbox
2. 集成channel/mailbox到B消息泵
3. 将channel/mailbox暴露给A

因此，上例中，我们即没有定义消息的传输方式，也没有定义消息的处理方式。SynchronizationContext本质只是提供了一层同步上下文切换交互抽象，传输方式，消息泵，甚至线程模型都需要我们自己实现。这里就不再展示SynchronizationContext的扩展细节，更多关于SynchronizationContext的文档:

1. [what is synchronizationcontext](https://hamidmosalla.com/2018/06/24/what-is-synchronizationcontext/)
2. [synchronizationcontext doc on MSDN](https://docs.microsoft.com/en-us/archive/msdn-magazine/2011/february/msdn-magazine-parallel-computing-it-s-all-about-the-synchronizationcontext)

### C# async/await

async/await是C# .NET4.5推出的更高级的异步编程模型:

```
public static async void AsyncTask()
{
    Console.WriteLine("before await, thread{0}", Thread.CurrentThread.ManagedThreadId);
    var a = await Task.Run(() =>
    {
        Thread.Sleep(500);
        Console.WriteLine("in task, thread{0}", Thread.CurrentThread.ManagedThreadId); 
        return 666;
    });
    Console.WriteLine("after await, got result: {0}, thread{1}", a, Thread.CurrentThread.ManagedThreadId);
}
static void Main(string[] args)
{
    Console.WriteLine("Main: before AsyncTask thread{0}", Thread.CurrentThread.ManagedThreadId);
    var r = AsyncTask().Result;
    Console.WriteLine("Main: after AsyncTask result: {0} thread{1}", r, Thread.CurrentThread.ManagedThreadId);
}
// Output:
AsyncTask: before await, thread1
AsyncTask: in task, thread3
AsyncTask: after await, got result: 666, thread3
Main: after AsyncTask result: 667 thread1
```

可以看到async/await进一步简化了异步编程的书写方式，达到更接近同步编程的可读性和易用性(这一点后面会再探讨下)。

#### 实现原理

在进一步了解它的用法之前，我们先大概了解下它的实现机制(可以看看[这篇文章](https://zhuanlan.zhihu.com/p/197335532)提到了不少实现细节)，async/await本质也是编译器的语法糖，编译器做了以下事情:

1. 为所有带async关键字的函数，生成一个状态机类，它满足IAsyncStateMachine接口，await关键字本质生成了状态机类中的一个状态，状态机会根据内部的state字段(通常-1表示开始，-2表示结束，其他状态依次为0,1,2...)，一步步执行异步委托。整个状态机由`IAsyncStateMachine.MoveNext`方法驱动，类似迭代器
2. 代码中的`await xxx`，xxx返回的对象都需要实现GetAwaiter方法，该方法返回一个Awaiter对象，编译器不关心这个对象Awaiter对象类型，它只关心这个Awaiter对象需要满足三个条件: a. 实现INotifyCompletion(只有一个`OnCompleted(Action continuation)`方法，用以异步框架挂载回调)，b. 实现IsCompleted属性，c. 实现GetResult方法，如此编译器就能知道如何与该异步操作进行交互，比如最常见的Task对象，就实现了GetAwaiter方法返回一个[TaskAwaiter](https://referencesource.microsoft.com/#mscorlib/system/threading/Tasks/Task.cs,2935)对象，但除了TaskAwaiter，任何满足以上三个条件的对象均可被await
3. 有了stateMachine和TaskAwaiter之后，还需要一个工具类将它们组合起来，以驱动状态机的推进，这个类就是`AsyncTaskMethodBuilder/AsyncTaskMethodBuilder<TResult>`，是Runtime预定义好的，每个async方法，都会创建一个Builder对象，然后通过[AsyncTaskMethodBuilder.Start](https://referencesource.microsoft.com/#mscorlib/system/runtime/compilerservices/AsyncMethodBuilder.cs,67)方法绑定对应的IAsyncStateMachine，并进行状态首次MoveNext驱动，MoveNext执行到await处(此时实际上await已经被编译器去掉了，只有TaskAwaiter)，会调用`TaskAwaiter.IsCompleted`判断任务是否已经立即完成(如`Task.FromResult(2)`)，如果已完成，则将结果设置到builder(此时仍然在当前线程上下文)，并之后跳转到之后的代码(直接goto，无需MoveNext)，否则，更新state状态，通过[AsyncTaskMethodBuilder.AwaitUnsafeOnCompleted](https://referencesource.microsoft.com/#mscorlib/system/runtime/compilerservices/AsyncMethodBuilder.cs,154)(最终调到`Awaiter.OnCompleted`)挂接(对`TaskAwaiter.OnCompleted`而言，是[挂接到Continuation](https://referencesource.microsoft.com/#mscorlib/system/runtime/compilerservices/TaskAwaiter.cs,339)上)异步回调(此回调包含整个状态机的后续驱动方式，通过[GetCompletionAction](https://referencesource.microsoft.com/#mscorlib/system/runtime/compilerservices/AsyncMethodBuilder.cs,ac92075576570beb)生成)并返回(此时当前函数堆栈已结束)，当taskAwaiter完成(不同的Awaiter完成方式也不同，对Task而言，即Task执行完成)后，buildier会通过GetCompletionAction生成的回调再次调用到`stateMachine.MoveNext`驱动状态机(此时可能已经不在当前线程，state状态也不一样了，可通过TaskAwaiter.GetResult拿到异步结果)，如此完成状态机的正常驱动。整个stateMachine只需要MoveNext一次，即可完全跑起来。
4. 除了驱动状态机外，AsyncTaskMethodBuilder的另一个作用是将整个async函数，封装为一个新的Task(wrapper task)，该Task可通过`AsyncTaskMethodBuilder.Task`属性获取。当stateMachine通过MoveNext走完每个状态后，会将最终结果，通过builder.SetResult写入到builder中的Task，如果中途出现异常，则通过builder.SetExpection保存，如此发起方可通过`try {await xxx;} catch (e Exception){...}`捕获异常，最终整个编译器改写后的async函数，返回的实际上就是这个`builder.Task`。

#### 基础用法

除了直接跟Task外，`.NET`和Windows运行时也封装了部分关于网络IO，文件，图像等，这些方法通常都以Async结尾，可直接用于await。以下代码说明了跟在await后面的常见的几种函数，以便进一步理解其中的差异和原理。

```C#
// 因为没有async标注，所以编译器不会为该函数生成状态机，但由于该函数返回的是Task，因此可以直接用于await
public static Task<int> F1Async()
{
    return Task.Run(() => { return 2; });
}

// 只要标记了async 就会生成对应状态机，但这里有几点需要注意:
// 1. 如果方法声明为 async，那么可以直接 return 异步操作返回的具体值，不再用创建Task，由编译器通过builder创建Task
// 2. 由于该函数体内没有使用await，整个状态机相当于直接builder.SetResult(2)，其中不涉及异步操作和线程切换(没有await异步切换点)，因此整个过程实际上都是在主线程同步进行的(虽然经过了一层builder.Task封装)
// 3. 编译器也会提示Warning CS1998: This async method lacks 'await' operators and will run synchronously.
public static async Task<int> F2Async()
{
    return 2;
}

// 该方法在Task上套了一层空格子Task，看起来好像和F1Async没区别
// 但实际上，编译器仍然会生成对应的builder和wrapper task，这个wrapper task在原task完成之后，只是做了简单的return操作
// 因此 await F3Async() 实际上可能导致两次线程上下文切换，如果是在UI线程上执行await，用法不当则可能触发"async/await 经典UI线程卡死"场景，因为await会默认捕获SynchronizationContext。这个后面说。
public static async Task<int> F3Async()
{
    return await Task.Run(() => { return 2; });
}
```

#### 线程切换

理解async/await基本原理后，不难发现，async/await本质上是不创建线程的，它只是一套状态机封装，以及通过回调驱动状态机的异步编程模型。await默认会捕获当前的执行上下文ExecuteContext，但是并不会捕获当前的同步上下文SynchronizationContext(关于ExcuteContext和SynchronizationContext的区别联系参考[executioncontext-vs-synchronizationcontext on MSDN](https://devblogs.microsoft.com/pfxteam/executioncontext-vs-synchronizationcontext/)，强烈建议阅读)，同步上下文的捕获是由TaskAwaiter实现(见[TaskAwaiter.OnCompleted](https://referencesource.microsoft.com/#mscorlib/system/runtime/compilerservices/TaskAwaiter.cs,93))，它会先获取`SynchronizationContext.Current`，如果没有或者是默认的，会再尝试获取Task对应的TaskScheduler上的SynchronizationContext。也就是说对TaskAwaiter而言，设置默认的SynchronizationContext和没有设置效果是一样的(为了少一次QueueWorkItem，对应源码在[这里](https://referencesource.microsoft.com/#mscorlib/system/threading/Tasks/Task.cs,2976)，我们可以结合前面的AsyncTask，以及下面的进一步测试来验证:

```C#
 class MySynchronizationContext : SynchronizationContext {
    public override void Post(SendOrPostCallback d, object state) {
        Console.WriteLine("MySynchronizationContext Post, thread{0}", Thread.CurrentThread.ManagedThreadId);
        base.Post(d, state);
    }
}
public static async void AsyncTask()
{
	 // 创建并使用自定义的SynchronizationContext
    var context = new MySynchronizationContext();
    SynchronizationContext.SetSynchronizationContext(context);
    Console.WriteLine("AsyncTask: before await, thread{0}", Thread.CurrentThread.ManagedThreadId);
    var a = await Task.Run(() =>
    {
        Thread.Sleep(500);
        Console.WriteLine("AsyncTask: in task, thread{0}", Thread.CurrentThread.ManagedThreadId);
        return 666;
    });
    Console.WriteLine("AsyncTask: after await, got result: {0}, thread{1}", a, Thread.CurrentThread.ManagedThreadId);
}
static void Main(string[] args)
{
    AsyncTask();
    Console.ReadKey();
}
// Output (使用自定义的SynchronizationContext):
// AsyncTask: before await, thread1
// AsyncTask: in task, thread3
// MySynchronizationContext Post, thread3
// AsyncTask: after await, got result: 666, thread4

// Output2 (使用默认的SynchronizationContext):
// AsyncTask: before await, thread1
// AsyncTask: in task, thread3
// AsyncTask: after await, got result: 666, thread3
```

这说明了如果当前线程没有或者设置的默认的SynchronizationContex，那么await之后的回调委托实际上是在await的Task所在的线程上执行的(这一点和ContinueWith的默认行为不大一样，后者总是会通过QueueWorkItem跑在一个新的线程中)。

如果设置了非默认的SynchronizationContex，那么回调委托将通过`SynchronizationContex.Post`方法封送(由于SynchronizationContex本质也只是接口，我们这里并不能草率地说，会回到Caller线程)。如对于WPF这类UI框架而言，它实现的`DispatcherSynchronizationContext`最终通过`Dispatcher.BeginInvoke`将委托封送到UI线程。而如果你是在UI线程发起await，其后又在UI线程上使用`task.Result`同步等待执行结果，就可能解锁前面F3Async中提到的[UI线程卡死场景](https://zhuanlan.zhihu.com/p/371362645)，这也是新手最常犯的问题。你可以通过`task.ConfigureAwait(bool continueOnCapturedContext)`指定false来关闭指定Task捕获SynchronizationContex的能力，如此委托回调的执行线程就和没有SynchronizationContex类似了。

总结下，async/await本身不创建线程，`aaa; await bbb; ccc;` 这三行代码，可能涉及到一个线程(比如没有await，或任务立即完成，甚至await线程自己的异步操作)，两个线程(比如没有自定义SynchronizationContex，或有自己实现消息泵的的SynchronizationContex)，三个线程(有其他线程实现消息泵的自定义SynchronizationContex)。但具体涉及几个线程，GetAwaiter(通常返回的是TaskAwaiter，但是你也可以自定义)，SynchronizationContex等外部代码和环境决定的。

#### 一些补充

##### await与yield的区别

yield和await都是语法糖，最后都会被生成一个状态机，每行yield/await都对应其中一个状态。

- 本质用途: yield用于快速构造枚举器，而await用于简化异步编程模型，两者都会生成状态机，但前对外表现为可枚举类，用于手动迭代，后者主要用于AsyncTaskMethodBuilder自动迭代(从调用async函数起，Builder就通过异步回调不断调用MoveNext，直至走完每个await状态)
- 线程切换: yield不涉及线程上下文的切换，而await通常涉及(前面说了，不是因为它会创建线程，而是依赖具体的异步操作，以及同步上下文)

##### C# async/await vs JS Generator异步

既然async/await也是异步编程模型，同样的，我们也将C# async/await用Generator异步编程四要素来分析下:

- Generator: C# yield是由编译器生成状态机类并实现IEnumerable，类似的，C# async/await也是编译器生成的可迭代状态机IAsyncStateMachine，不过它只有MoveNext()方法，看起来甚至不能单向传值。不过事实上，它的双向传值机制都封装在状态机类内部了
- Thunk: await也有Awaitable标准，它需要实现INotifyCompletion的`OnCompleted(Action continuation)`方法，这也就提供了统一的挂载回调标准。C# Task和JS Promise一样，都实现了异步执行和回调挂接分离
- AsyncOp: C#的Task原生适配了Awaitable，并且Awaitable也非常易于开发者扩展(后面讲UniTask还会详述)
- Iterator: 整个状态机的驱动，由前面提到的AsyncTaskMethodBuilder来完成，它负责将await之后的执行路径通过OnCompleted挂载到异步操作上

强行将C# async/await映射到四要素可能不是很合适，因为C# async/await的Generator和Iterator是一体生成的，严格上不涉及所谓的执行权转移。C# async/await 是在async function外部直接生成一个状态机Wrapper类，对函数执行入口、返回值等进行了"魔改"。而JS Generator异步，是通过自定义的run函数或第三方co库驱动迭代。因此C#的async/await可以进行任意函数层级嵌套，而无需像JS一样每一个Generator都要单独驱动，另外C# async/await 可能涉及到线程切换，而JS则通常都是在单线程。

##### async/await是Task+状态机的语法糖

这个要从两方面看，一方面，async函数在经过编译器处理后，最终返回给调用方的，是builder中的Task对象(这也是为何async方法的返回值只能是`void`, `Task`, `Task<TResult>`)。而另一方面，await本身不关注Task，它支持所有提供异步相关接口的对象(GetAwaiter)，这样的好处在于除了Task，它还可以集成更多来自框架(比如`.NET`已经提供的各种Async API)，甚至自定义的异步对象，已有的异步操作也可以通过适配GetAwaiter移植到新的async/await异步编程模型。

##### 出现await的地方，当前线程就会返回，或发生线程上下文切换

这个前面也解释过了，出现await的地方未必会涉及线程上下文切换，比如前面的`await F2Async()`，对它的整个调用都是同步的。异步编程和线程无关，线程切换取决于异步操作的实现细节，而await本身只关注与异步操作交互的接口。

### Unity async/await

Unity也引入了C# async/await机制，并对其进行了适配:

1. Unity本身也是UI框架，因此它实现了自己的同步上下文[UnitySynchronizationContext](https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Scripting/UnitySynchronizationContext.cs)以及主线程的消息泵，如此await的异步委托会默认会回到Unity主线程执行(可通过task.ConfigureAwait配置)
2. Unity社区提供了针对大部分常见YieldInstruction(如WaitForSeconds)，以及其他常用库(如UnityWebRequest、ResourceRequest)的GetAwaiter适配(如[Unity3dAsyncAwaitUtil](https://github.com/svermeulen/Unity3dAsyncAwaitUtil))

[Unity3dAsyncAwaitUtil](https://github.com/svermeulen/Unity3dAsyncAwaitUtil)这个库及其相关Blog: [Async-Await instead of coroutines in Unity 2017](http://www.stevevermeulen.com/index.php/2017/09/using-async-await-in-unity3d-2017/)，非常值得了解一下，以适配大家最熟悉的YieldInstruction WaitForSeconds(3)为例，来大概了解下如何通过将它适配为可以直接`await WaitForSeconds(3);`

```C#
// GetAwaiter
// 适配WaitForSeconds类的GetAwaiter方法，通过GetAwaiterReturnVoid返回其Awaiter对象
public static SimpleCoroutineAwaiter GetAwaiter(this WaitForSeconds instruction)
{
    return GetAwaiterReturnVoid(instruction);
}
// GetAwaiterReturnVoid
// 创建和返回Awaiter: SimpleCoroutineAwaiter
// 并在Unity主线程执行InstructionWrappers.ReturnVoid(awaiter, instruction)
static SimpleCoroutineAwaiter GetAwaiterReturnVoid(object instruction)
{
    var awaiter = new SimpleCoroutineAwaiter();
    RunOnUnityScheduler(() => AsyncCoroutineRunner.Instance.StartCoroutine(
        InstructionWrappers.ReturnVoid(awaiter, instruction)));
    return awaiter;
}
// InstructionWrappers.ReturnVoid
// 这里其实已经在Unity主线程，所以这里本质是将await最终换回了yield，由Unity来驱动WaitForSeconds的完成
// 只不过yield完成之后，通过awaiter.Complete回到Awaiter.OnCompleted流程去
public static IEnumerator ReturnVoid(
            SimpleCoroutineAwaiter awaiter, object instruction)
{
    // For simple instructions we assume that they don't throw exceptions
    yield return instruction;
    awaiter.Complete(null);
}

// 确保Action在Unity主线程上运行
// SyncContextUtil.UnitySynchronizationContext在插件Install的时候就初始化好了
// 如果发现当前已经在Unity主线程，就直接执行Action，无需自己Post自己
static void RunOnUnityScheduler(Action action)
{
    if (SynchronizationContext.Current == SyncContextUtil.UnitySynchronizationContext)
    {
        action();
    }
    else
    {
        SyncContextUtil.UnitySynchronizationContext.Post(_ => action(), null);
    }
}

// 真正的Awaiter，它是无返回值的，对应还有一个SimpleCoroutineAwaiter<T>版本
// 它的实现比较简单，就是适配接口，记录委托回调(_continuation)，并在Compele()任务完成时，通过RunOnUnityScheduler封送委托回调
public class SimpleCoroutineAwaiter : INotifyCompletion
{
    bool _isDone;
    Exception _exception;
    Action _continuation;

    public bool IsCompleted
    {
        get { return _isDone; }
    }

    public void GetResult()
    {
        Assert(_isDone);

        if (_exception != null)
        {
            ExceptionDispatchInfo.Capture(_exception).Throw();
        }
    }

    public void Complete(Exception e)
    {
        Assert(!_isDone);

        _isDone = true;
        _exception = e;

        // Always trigger the continuation on the unity thread when awaiting on unity yield
        // instructions
        if (_continuation != null)
        {
            RunOnUnityScheduler(_continuation);
        }
    }

    void INotifyCompletion.OnCompleted(Action continuation)
    {
        Assert(_continuation == null);
        Assert(!_isDone);

        _continuation = continuation;
    }
}
```

如此我们就可以直接使用`await WaitForSeconds(3);`了，深入细节可以发现，不管是WaitForSeconds本身，还是之后的回调委托，其实都是在Unity主线程中执行的，并且结合RunOnUnityScheduler的优化，整个过程既不会创建线程，也不会产生额外的消息投递，只是在yield上加了一层壳子而已。这也再次说明了，async/await本身只是异步编程模型，具体的线程切换情况，Awaiter，SynchronizationContext，ConfigureAwait等综合控制。

这个工具库还有一些有意思的小特性，比如Task到IEnumerator的转换(原理就是轮询Task完成状态)，通过`await new WaitForBackgroundThread();`切换到后台线程(原理其实就是对`task.ConfigureAwait(false)`的封装)，这些在理解整个async/await，Unity协程，SynchronizationContext等内容后，都应该不难理解了。

另外，这里有篇关于[Unity中async/await与coroutine的性能对比](https://www.linkedin.com/pulse/unity-async-vs-coroutine-jo%C3%A3o-borks)，可以看看。

### Unity UniTask

通过前面的了解，可以发现，在Unity中，Coroutine可以用来实现单线程内的异步操作，Task可用来实现多线程的并发、异步和协同操作。而async/await是一种比Coroutine和Task更抽象易用的异步编程模型，C#完成了Task和async/await的适配，Unity3dAsyncAwaitUtil完成了Coroutine和async/await的适配，但对Unity开发者而言，还是不够方便，开发者面临过多方案选择: yield Coroutine or await Coroutine or await Task，因此，Unity社区又有大神出手，出了一套新方案: [UniTask](https://github.com/Cysharp/UniTask)，它的目的是整合Coroutine的轻量、Task的并发、async/await的易用于一体，为开发者提供高性能、可并发、易使用的接口。

它的主要特性包括:

- 基于值类型的 UniTask<T> 和自定义的 AsyncMethodBuilder 来实现0GC
- 使所有 Unity 的 AsyncOperations 和 Coroutines 可等待 (类似Unity3dAsyncAwaitUtil的适配)
- 基于 PlayerLoop 的任务(UniTask.Yield, UniTask.Delay, UniTask.DelayFrame...)可以替代所有协程操作
- 对 MonoBehaviour 消息事件和 uGUI 事件进行 可等待/异步枚举 拓展
- 与C#原生 Task/ValueTask/IValueTaskSource 行为高度兼容
- ...

更详细UniTask功能介绍，推荐[这篇博客](https://www.lfzxb.top/unitask_reademe_cn/)，UniTask一方面保留和适配 Unity Coroutine的轻量单线程异步模型，另一方面，将Coroutine的惯用场景(如WaitForSeconds)全部移植到性能更优的UniTask上实现了一遍(受益于async/await异步模型的抽象性)，并且保持UniTask与Task语义兼容，保留大部分的Task并发和交互模型能力。

从实现上来说，以`UniTask.Delay`为例，它的功能类似于WaitForSeconds，它会返回一个`UniTask`对象，UniTask对象本身只是一层可await的壳子，真正起作用的对象是其持有的`DelayPromise`对象(`IUniTaskSource source`字段)，DelayPromise的有两个核心方法:

- `OnCompleted`: AsyncUniTaskMethodBuilder挂接异步回调会通过UniTask Awaiter调到这里，它只是简单转调用`core.OnCompleted`，`UniTaskCompletionSourceCore core`是UniTask Promise都有的字段，做一些核心代码复用
- `MoveNext() bool`: 它会检查时间是否到期，未到期返回true，到期则通过`core.TrySetResult(null)`设置完成状态，并返回true。注意，`core.TrySetResult`中，会调用并执行continuation

异步挂接和回调机制有了，谁来驱动`IUniTaskSource.MoveNext`，注意，这个MoveNext和C#中的`IAsyncStateMachine.MoveNext`是不同的:

- `IAsyncStateMachine.MoveNext`: 表示开始驱动整个状态机，Awaitable在异步任务完成时，会通过continuation(由AsyncTaskMethodBuilder生成并通过OnCompleted注入)调用到`stateMachine.MoveNext`跳转到下一个await语句。
- `IUniTaskSource.MoveNext`: 仅用于确定状态机的该异步任务是否已经完成，将continuation的调用放到了外部驱动器。比如对`UniTask.Delay`而言，它是不切换线程的，如Unity Coroutine一样，通常由额外的Ticker/Event/Poll这类机制，来检查状态变更(如Delay到期)，设置Awaiter Result，并回调continuation(通过`core.TrySetResult(null)`)。

驱动`IUniTaskSource.MoveNext`的工作是由[PlayerLoopRunner](https://github.com/Cysharp/UniTask/blob/master/src/UniTask/Assets/Plugins/UniTask/Runtime/Internal/PlayerLoopRunner.cs)来完成的，DelayPromise创建之后，就会被立即添加到PlayerLoop Action中，PlayerLoopRunner穿插在Unity的各个执行Timing，驱动/检查所有IPLayerLoopItem任务的MoveNext。

对于`UniTask.Yield(PlayerLoopTiming.FixedUpdate);`这类场景，UniTask的实现更为简单，直接在`YieldAwaitable.OnCompleted(continuation)`挂接异步回调时，将continuation挂在PlayerLoop上即可，PlayerLoop会在对应timing(如FixedUpdate)触发时，调用continuation。

另外，`UniTask.Run/RunOnThreadPool`不使用默认的UnitySynchronizationContext和ExecutionContext，而是自己做同步上下文切换，这一点可能会容易和原生Task行为混淆，虽然它也提供`UniTask.SwitchToMainThread`、`UniTask.SwitchToThreadPool`、`UniTask.ReturnToCurrentSynchronizationContext`等API进行精确的同步上下文控制。

UniTask将Unity单线程异步编程诸多实践与async/await异步编程模型有机整合，并对Unity Coroutine与C# Task的诸多痛点进行优化和升级，看起来确实有一统Unity异步编程模型的潜力，应该离整合进Unity官方包也不远了。

### 一点体会

首先我是个C#和Unity的门外汉，只是谈谈自己的体会，异步编程尤其是并发编程从来都不是一件简单的事，无论它看起来多么"简洁优雅"。学习各语言/框架的异步演进史，是一件非常有意思的事情:

- C#: Thread(关注实现) -> Task(关注任务) -> async/await(关注可读性和扩展性)
- Unity: Coroutine(Engine做大量支持，算半个异步编程模型) -> Unity3DAsyncAwaitUtil(将Coroutine适配到async/await) -> 到UniTask(整合Coroutine和Task，兼并性能更高、可读性更高、更适合Unity)
- JS: Callback(最原始) -> Generator+Thunk+AsyncOp+Iterator异步(初步四件套) -> Promise(统一规范异步操作) -> Generator+Promise+co(标准三件套) -> async/await+Promise(终极两件套)

异步编程模型一直在演进，看起来写越来越"简单"，可读性越来越"高"，代价是编译器和运行时做了更多的工作，并且这些工作和原理是作为开发者必须要了解的，以C# async/await为例，如果不能充分了解底层原理，就容易引发: 

- 异步回调闭包引用可变上下文的问题
- async "无栈编程"本身带来的理解负担和调试难度
- 代码的线程上下文难以分析，容易引发并发安全访问的问题
- 同一段代码在不同的线程执行可能具有完全不同的行为(SynchronizationContext和ExecuteContext不同)

等问题。语言和框架本身只提供选择，作为使用者的我们，在并发越来越"容易"的同时，保持对原理的理解，才能充分发挥工具的作用(享受上限高的好处，避免下限低的问题)。
