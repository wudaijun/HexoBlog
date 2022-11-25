---
title: Javascript 中的异步编程
layout: post
tags:
- js
- coroutine
- async programing
categories:
- js
---

简单聊聊Web前端(主要是JS)中的几种异步编程机制和范式，由于JS是单线程的(事实上，几乎所有的前端或GUI框架都是单线程的，如Unity，WPF等)，因此要提高效率，要么新建线程(如Web Worker)，要么就只能异步。由于UI框架的大部分数据都不是线程安全的，如JS中的DOM对象便不支持并发访问，因此新建线程能分担的事情比较有限(如CPU密集运算或IO)，因此单线程异步编程模型成为了JS中的核心编程模型。下面来聊聊JS中异步编程模型演进史。

#### Callback

Callback 在 JS 中无处不在，Ajax，XMLHttpRequest 等很多前端技术都围绕回调展开，比如创建一个 Button: `<button onclick="myFunction()">Click me</button>`。回调的优点是简单易于理解和实现，其最大的缺点是调层数过深时，代码会变得非常难维护(所谓回调地狱，Callback Hell):

```javascript
// 为了便于测试，通过setTimeout模拟  fs.readFile(file, cb) 读取文件操作
function MyReadFile(file, cb) {
  return setTimeout(()=>{
          cb(null, "filecontent: "+file) // 将err设为null，模拟读取到文件内容为 filecontent + filename
          }, 100) // 模拟读取文件需要100ms
}

MyReadFile("abc.txt", (err1, filedata1) => {
  console.log(filedata1);
  MyReadFile("xyz.txt", (err2, filedata2) => {
    console.log(filedata2)
    // MyReadFile( ... )
  })
})
```

使用Callback需要注意的一个问题是闭包引用可变上下文的问题: 当执行异步回调(闭包)时，闭包引用的外部局部变量可能已经失效了(典型地，比如对应的对象在容器中已经被删除了)，此时闭包会读写无效的数据，产生非预期的结果，且较难调试:

<!--more-->

```javascript
var objs = {123: {name: "abc"}};

function test() {
  	var obj = objs[123];
	setTimeout(()=>{
      obj["name"] = "xyz";	// 这个时候obj已经从objs中移除了，对它的读写没有意义，并且可能导致非预期后果
    }, 1000);
  	delete objs[123];
  	console.log(objs);
}

test();
```

闭包引用可变上下文的问题对JS而言，不是很明显，毕竟前端的业务和数据模型相对简单，造成的后果也通常只是显示层的。但对后端而言，由于涉及到数据存储和强状态性，对这类问题需要更谨慎细致，比如尽可能只在回调上下文中使用值语义对象(如上例中的ObjID 123)，在回调中重新获取引用对象，确保操作结果如预期。

Callback是一种非常简单直观的异步编程模型，不过要在JS中充分发挥作用，还需要JS框架底层的支持，如对Timer、Network、File这种重CPU或IO的模块的封装和集成(到主线程消息泵)。Callback到目前仍然是异步编程模型最主流的方案。

#### Generator + Thunk 异步

在JS中，通过迭代器(Iterator)和(Generator)可以实现类似协程的执行权转移和值交换逻辑:

```javascript
// Generator 生成器
function *numberGenerator(){
    let a = yield 1; // a = 4
    let b = yield 3; // b = 6
    return 5;
}

// Iterator 迭代器
const g = numberGenerator() // Generator创建之后默认是暂停的，需要手动调用next让其开始执行
const iter1 = g.next(2)   // iter1 = {value: 1, done: false}
const iter2 = g.next(4)   // iter2 = {value: 3, done: false}
const iter3 = g.next(6)   // iter3 = {value: 5, done: true}
```


我在[Lua协程](https://wudaijun.com/2015/01/lua-coroutine/)中简单介绍了协程的基本概念和Lua中的协程，JS的Generator和Lua协程的概念看起来类似，其JS yield对应Lua yield，JS `g.next()`对应Lua `resume(g)`，且都具备双向传值的能力。但通过Generator+Iterator方式实现的协程，与Lua这种支持运行时堆栈保存的协程，还是有一定的区别的，典型地，Lua协程可以跨越函数堆栈，从yield方直接返回到resume方(yield可以在函数嵌套很深的地方)，而JS中，yield只代表当前函数立即返回，即只能返回到持有当前函数的迭代器方(每一层Generator调用都需要单独处理迭代)。因此，个人认为，JS还不能称为支持协程，只能说支持Generator或生成器，以和Lua这种运行时支持的协程做区分。

在JS中，Generator通常和异步联系在一起，而前面说了，Generator还不能算作完全体协程，它是怎么与异步联系在一起的呢，先看个例子:

```javascript
// 为了便于测试，通过setTimeout模拟  fs.readFile(file, cb) 读取文件操作
function MyReadFile(file, cb) {
  return setTimeout(()=>{
          cb(null, "filecontent: "+file) // 将err设为null，模拟读取到文件内容为 filecontent + filename
          }, 100) // 模拟读取文件需要100ms
}

// Thunk
function MyReadFileThunk(file) {
  return (cb) => {
    MyReadFile(file, cb);
  }
}

const gen = function* () {
    const fileData1 = yield MyReadFileThunk("abc.txt");
    console.log(fileData1);
    const fileData2 = yield MyReadFileThunk("xyz.txt");
    console.log(fileData2);
}

// --- 手动单步迭代
// function run(g) {
//   g.next().value((err1, filedata1)=>{
//    g.next(filedata1).value((err2, filedata2)=>{
//        g.next(filedata2);
//      });
//   })
// } 

// 循环自动迭代，与前面手动单步迭代得到的结果一样
// 但自动迭代，依赖于每个yield后的异步回调格式是一样的，在本例中，异步结果都是(err, string)=>{...}
function run(g) {
  const next = (err, filedata) => {   // 这里暂不考虑err错误处理
    let iter = g.next(filedata); // 首次调用: 启动Generator 非首次调用: 异步文件读取完成，将执行权和filedata交还给yield
    if (iter.done) return;       // 如果generator迭代完成，即gen()函数执行完所有的yield语句，则终止流程，这里首次调用时为false
    iter.value(next);            // 这里iter.value本身是MyReadFileThunk函数返回的MyReadFile单回调参数版本(filename参数已经被偏特化了)，本例中，类似于MyReadFile_abc，MyReadFile_xyz，将next作为异步文件读取的callback传给MyReadFile_abc，开始真正的异步文件读取操作
  }
  next();
}

run(gen());

// 输出结果:
// "filecontent: abc.txt"
// "filecontent: xyz.txt"
```

如此对于gen函数而言，异步操作的结果会作为yield的返回值传回，yield之后的语句可以直接使用它，而无需再写回调函数(避免了回调地狱)，达成了**像写同步代码一样写异步代码**的目的。从实现的角度来说，这套方案依赖于四个要素:

1. Generator: 支持多段式函数返回，并具备双向传值能力
2. AsyncOp: 底层的异步操作支持 (如上面的setTimeout，JS会保证超时时间到了后，回调会在主线程触发)
3. Thunk: Thunk的本质是偏函数，它将注入回调的职责从原本的异步操作中剥离出来，作为yield的返回值传给迭代器方
4. Iterator: 也就是本例中的run函数，它为Thunk后的函数注入回调函数并执行真正的异步操作，在异步操作完成后，将异步结果传回yield

其中Generator和AsyncOp由JS框架提供，Thunk可以使用[thunkify](https://www.npmjs.com/package/thunkify)，Iterator可以使用[co](https://www.npmjs.com/package/co)，都有现成的轮子，使用thunkify和co之后的MyReadFile如下:

```
var co = require('co');
var thunkify = require('thunkify');

// 使用thunkify库替换掉上例手写的Thunk函数
// 注: thunkify要求MyReadFile的最后一个参数为callback
var MyReadFileThunk = thunkify(MyReadFile);

// ... MyReadFile + gen 定义

// 使用co库替换掉上例手写的run函数，一键执行
// 注: co库规范要求异步操作Callback的第一个参数为err，这也是上例中保留 callback(err, fileData) 中的 err 的原因
co(gen);

```
thunkify和co的实现和上例手写的Thunk和Iterator类似，它们进一步提升了基于JS Generator的异步编程能力。

#### Promise

Promise 是 JS 异步编程中，比回调函数更高级的解决方案。简单来说，Promise 是一个对象，保存着某个异步操作的状态(进行中 pending, 已成功 fulfilled，已失败 rejected)以及回调函数信息(成功回调，错误回调)，Promise旨在以统一，灵活，更易于维护的方式来处理所有的异步操作。仍然以MyReadFile为例，我们可以将Thunk版本的gen函数，用Promise的方式重写:

```
function MyReadFilePromise(file) {
  return new Promise(function(resolve, reject){
    // resolve 和 reject 由JS引擎提供，用于(也只有它们能)更改 Promise 对象状态
    //当异步代码执行成功时，我们才会调用resolve(...), 当异步代码失败时就会调用reject(...)
    //在本例中，我们使用setTimeout(...)来模拟异步代码，实际编码时可能是XHR请求或是HTML5的一些API方法.
    MyReadFile(file, (err, data)=>{
      if (err != null) {reject(err)};
      resolve(data)
    })
  })
}

// then()函数第一个参数是异步操作成功(通过resolve返回)时的回调
// 第二个参数(可选)是异步操作失败(通过reject返回)时的回调
MyReadFilePromise("abc.txt").then((filedata1)=>{
  console.log(filedata1)
  return MyReadFilePromise("xyz.txt");
}).then((filedata2)=>{
  console.log(filedata2)
})
```

Promise详细介绍可以参考[ES6教程](http://es6.ruanyifeng.com/#docs/promise)。简单归纳，Promise 对象有如下特性:

1. Promise 对象中的状态只受异步操作结果影响，并且状态只会变化一次(pending->fulfilled 或 pending->rejected)
2. 允许延迟挂接回调函数，即在Promise 状态变更之后挂上去的回调函数，也会立即执行(当然得状态匹配)
3. 能将嵌套回调(又名: 回调地狱)优化为链式回调
4. 尝试用统一的语义和接口来使用异步回调，甚至可以用到同步函数上

Promise 的出现对JS异步编程的重要性不言而喻，它在之前单一的Callback模式上，尝试对异步操作进行更高层次的抽象(如异步状态管理、错误处理规范、将异步调用和挂载回调解耦等，让异步代码的书写简洁易读。Promise将回调嵌套升级为回调链(`a.then(xxx).then(yyy)`)之后，虽然可读性提高了，但你可能还是觉得好像没有上一节Thunk+yield+co来得直接，没关系，Promise也可以yield+co配套:

```javascript
var co = require('co');

function* gen() {
  filedata1 = yield MyReadFilePromise("abc.txt");
  console.log(filedata1);
  filedata2 = yield MyReadFilePromise("xyz.txt");
  console.log(filedata2);
}

// 手写模拟co(gen)流程，仍然忽略错误处理
// function run(g) {
//   const next = (err, filedata) => {  
//     let iter = g.next(filedata); 
//     if (iter.done) return;      
//     iter.value.then((data)=>{ // 主要的区别: 这里的iter.value是Promise，通过.then挂载回调，而再是Thunk版本的iter.value(next)
//       next(null, data);
//     }); 
//   }
//   next();
// }
// run(gen());

co(gen);
```

在这个例子中，co扮演Iterator，Promise同时作为AsyncOp和Thunk，这也是Promise作为异步操作统一规范的好处。

#### async/await

前面提到的Generator异步编程四要素: Generator、Thunk、AsyncOp、Iterator，其中前三个都被JS Generator + Promise原生支持了，虽然Iterator也有co这种简单又好用的库，但终究还不够完美，因此async/await诞生了，它被称为JS异步编程的终极方案:

```javascript
// async 声明异步函数 (类似前面的gen函数)
// 声明 async 的函数才可以使用 await，并且async函数会隐式返回一个Promise(因为await本质是yield，会让出所有权，所以调用方只能异步等待async函数执行结束)，因此async函数本身也可以被await
async function test(){
	// 使用 await 替代 yield
    const filedata = await MyReadFilePromise('abc.txt');
    console.log(filedata);
    return 'OK'; // /本质返回的是: Promise {<resolved>: 'OK'}
}

// 无需再单独手写或者使用co库作为Iterator，当调用test()方法时，整个Iterator将由JS框架托管执行。
```

在理解前面的`Generator+Thunk+AsyncOp+Iterator`以及`Generator+Promise+Iterator`异步编程方案之后，其实你应该能想到，async/await 并不算是新技术，而是基于`Generator+Promise+Iterator`方案的语法糖，其中async对应Generator的*函数声明，await对应yield，然后在框架底层帮你实现了Iterator(当然要比我们前面手写的版本复杂一些，比如错误处理机制)。如此Generator异步四要素，都在框架原生支持了。


#### 小结

总结，本文从初学者角度对JS中异步编程模型演变史进行了大致梳理，按照个人的理解，大概可以分为以下四个阶段:

- Callback + AsyncOp
- Generator + Thunk + AsyncOp + Iterator
- Generator + Promise(=Thunk+AsyncOp) + Iterator
- async/await(=Generator+Iterator) + Promise(=Thunk+AsyncOp)

在理解和学习异步的时候，将异步和并发两个概念区分开是尤其重要的，异步并不一定意味着并发(如JS setTimeout)，反之亦然。如Web前端、Unity、WPF这类前框框架基本都是单线程的(UI层的东西，想要并发太难)，因此通过异步提升单线程的性能是框架和开发者首选解决方案，而让异步编程模型更易用易读，也是前端框架演变的一个方向。

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

这里的 async/await 关键字的意义与 JS 中的类似，[Defer 对象](https://twistedmatrix.com/documents/current/core/howto/defer-intro.html)则是类似 JS Promise 的东西，用于保存异步执行结果，挂载回调。同样，C#的也有类似JS Promise的概念，叫Task。语言和框架总是有很多共性，识别和理解这类共性(通常也叫做模型/范式)，是一个非常好的提升技术认知，构建知识体系的机会。
