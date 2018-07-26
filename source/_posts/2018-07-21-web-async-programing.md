---
title: Web 中的异步编程
layout: post
tags:
- programing
- js
categories:
- gameserver
---


#### Callback / Event

Callback 在 JS 中无处不在，Ajax，XMLHttpRequest 等很多前端技术都围绕回调展开，比如创建一个 Button: `<button onclick="myFunction()">Click me</button>`。回调的优点是简单易于理解和实现，缺点一是调层数过深时，代码会变得非常难维护(所谓回调地狱，Callback Hell)，二是任务和回调之间紧耦合，并且只能指定一个回调函数。

<!--more-->

Event 比 Callback 灵活一些，不管是 Event 还是 Handler 都可以动态添加，实现了发布者和订阅者的解耦，并且支持挂载多个 Handler。

Callback/Event只是一种异步编程模式，要想通过异步获得更好的执行效率，本质上都需要第三方异步框架的支持，毕竟 js 是单线程的，要提高效率，要么借助其它的线程，要么使用 IO 复用这类技术。在协程与轻量级线程出现之前，这是异步编程的通用方案。

#### Coroutine

讲到协程，可能大家都有一些自己理解：

1. 可以通过 yield 中断返回多次的函数
2. 可以用同步的方式实现异步
3. 用户控制协程的切换，在切换的时候可以传值
4. 从外部来看，可以协程本身看做一个枚举器或者迭代器

但在我看来，本质上说，协程只做了两件事: 当前代码的上下文保存/恢复，以及切换上下文时的通信机制，以上的几点不过是基于这些的应用场景。很多语言都提供了协程机制，比如 Python, Lua, JS, C#等，以 JS 为例，协程在 JS 中的应用被称作 Generator: 

```
function *numberGenerator(){
    let a = yield 1; // a = 4
    let b = yield 3; // b = 6
    return 5;
}

const iterator = numberGenerator()
const iter1 = iterator.next(2)   // iter1 = {value: 1, done: false}
const iter2 = iterator.next(4)   // iter2 = {value: 3, done: false}
const iter3 = iterator.next(6)   // iter3 = {value: 5, done: true}
```


协程是用户控制上下文切换，因此可以应用与一些简单的异步编程模型，比如我在[Lua协程](http://wudaijun.com/2015/01/lua-coroutine/)里面提到的一些简单应用。总的来说，单纯依靠协程来实现异步编程对开发者的要求是比较高的。

#### Promise

Promise 是 JS 异步编程的一种解决方案，用于提供比回调函数和事件更好的异步方案。简单来说，Promise 是一个对象，保存着某个异步操作的状态(进行中 pending, 已成功 fulfilled，已失败 rejected)以及回调函数信息(成功回调，错误回调)，Promise旨在以统一，灵活，更易于维护的方式来处理所有的异步操作:

```
let myFirstPromise = new Promise(function(resolve, reject){
    // resolve 和 reject 由JS引擎提供，用于(也只有它们能)更改 Promise 对象状态
    //当异步代码执行成功时，我们才会调用resolve(...), 当异步代码失败时就会调用reject(...)
    //在本例中，我们使用setTimeout(...)来模拟异步代码，实际编码时可能是XHR请求或是HTML5的一些API方法.
    setTimeout(function(){
        resolve("成功!"); //代码正常执行！
    }, 250);
});

// then()函数第一个参数是异步操作成功(通过resolve返回)时的回调
// 第二个参数(可选)是异步操作失败(通过reject返回)时的回调
myFirstPromise.then(function(successMessage){
    //successMessage的值是上面调用resolve(...)方法传入的值.
    console.log("Yay! " + successMessage);
}, function(errMessage){
    console.log("Ops! " + errMessage);
});
```

Promise详细介绍可以参考[ES6教程](http://es6.ruanyifeng.com/#docs/promise)。简单归纳，Promise 对象有如下特性:

1. Promise 对象中的状态只受异步操作结果影响，并且状态只会变化一次(pending->fulfilled 或 pending->rejected)
2. 允许延迟挂接回调函数，即在Promise 状态变更之后挂上去的回调函数，也会立即执行(当然得状态匹配)
3. 更优雅地解决嵌套回调(又名: 回调地狱)问题
4. 尝试用统一的语义和接口来使用异步回调，甚至可以用到同步函数上

比如异步回调广为诟病的回调地狱问题:

```
// 传统回调方式
doSomething(function(result) {
  doSomethingElse(result, function(newResult) {
    doThirdThing(newResult, function(finalResult) {
      console.log('Got the final result: ' + finalResult);
    }, failureCallback);
  }, failureCallback);
}, failureCallback);

// Promise 方式
doSomething().then(function(result) {
  return doSomethingElse(result);
})
.then(function(newResult) {
  return doThirdThing(newResult);
})
.then(function(finalResult) {
  console.log('Got the final result: ' + finalResult);
})
.catch(failureCallback);
```

Promise 的出现对异步编程的意义是比较重大的，它尝试封装异步调用结果，将异步调用和回调解耦，让异步代码的书写简洁易读，甚至像可以像同步代码一样，比如我们写的同步代码是按照代码顺序执行的，而异步代码则可以通过`Promise.then(f1).then(f2)...`来将异步操作串联起来，

#### async/await

async/await 可以理解为基于 generator 和 promise 之上构建的更高级的异步编程方案，代码看起来像是这样:

```javascript
// 返回一个 Promise 对象，用于模拟一个异步操作
function someAsyncOp() {
    // 简单起见，这个对象会在2s后resolve
    return new Promise(function(resolve, reject){
        setTimeout(function(){
            resolve("haha")
        }, 2000)
    })
}

async function test(){
    const s = await someAsyncOp();
    return  (s + " received");
}
```

短短几行代码，实现了用同步的方式来写异步代码！其实，async/await 并不是新技术，而是基于 Generator 和 Promise 的语法糖，我们可以手动实现一个类似的功能:

```javascript
function* generator() {
    const s = yield someAsyncOp();
    return (s + " received")
}

const iterator = generator();
// iteration: {value: Promise{}, done: false}
const iteration = iterator.next();

iteration.value.then(
    resolvedValue => {
        // nextIteraction: {value: 'haha received', done: true}
        const nextIteraction = iterator.next(resolvedValue);
    }
)
```

可以看到，async/await 只不过将 Generator 的*函数声明换成了 async，将 yield 换成了 await，然后帮你执行了后面的两次迭代，其中第一次迭代是 `someAsyncOp()`函数返回，iterator 得到 Promise 对象，第二次迭代时 Promise resolve 时，将 resolve 的结果又传回给 yield 返回处(也就是 await 表达式返回值)。当然，await 实现上要比这个复杂得多，但本质就是通过协程完成了一次resolve值的交接(Promise -> 迭代器 -> await语句返回值)。

使用 async/await 有几点需要注意:

1. 声明了 async 的 function 总是返回一个 Promise 对象，因为其会在 await 处中断等待，因此 test() 函数的调用者只能得到一个 Promise，其 resolve 的值即为 return 的值
2. await 只能顺序等待 Promise 完成操作，而不是并发的，如果需要并发，可以使用 `Promise.all`将多个异步操作混合在一起

除了 JS 外，Python3.5, .NET4.5 也引入了 asyc/await 特性，不出意外，这会成为 Web 中的主流异步开发模型。比如 Python twisted 框架示例:

``` python
import json
from twisted.internet.defer import ensureDeferred
from twisted.logger import Logger
log = Logger()

async def getUsers():
    try:
        return json.loads(await makeRequest("GET", "/users"))
    except ConnectionError:
        log.failure("makeRequest failed due to connection error")
        return []

def do():
    d = ensureDeferred(getUsers())
    d.addCallback(print)
    return d
```

这里的 async/await 关键字的意义与 JS 中的类似，[Defer 对象](https://twistedmatrix.com/documents/current/core/howto/defer-intro.html)则是类似 JS Promise 的东西，用于保存异步执行结果，挂载回调。


总结，Web 前端通常是单线程(比如 JS 执行环境)，主要通过协程在异步库等方式来进行异步编程，由于通常都是在线程内或者线程间交互，因此重度依赖回调机制，在设计层面也更多地考虑如何让回调更简洁易读。Promise 的出现简化了异步调用状态的管理，异步调用可以返回一个 Promise，承诺或在未来某个时刻返回，这样普通函数和异步函数都可由`Promise.then()`执行链串联起来，就像同步代码的书写顺序一样，统一了同步代码和异步代码的书写方式(当然，是按照异步调用的规范写)。async/await 出现后，进一步地简化了异步编程，不需要通过`Promise.then()`而是直接在函数返回处等待返回值。