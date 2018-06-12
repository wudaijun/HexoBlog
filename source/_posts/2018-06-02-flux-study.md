---
title: Flux - Web应用的数据流管理
layout: post
categories: web
tags:
- react
- web
---

React实际上只是View层的一套解决方案，它将View层组件化，并约定组件如何交互，数据如何在组件内流通等，但实际的Web App除了View层外，还包括Model层，界面响应，服务器请求等，Flux则是Facebook为此给出一套非常简洁的方案，用于管理Web应用程序数据流。与其说Flux是一套框架，不如说其是一套设计模式，因为其核心代码只有几百行，它主要表述的是一种Web应用设计理念和模式。

<!--more-->

目前大部分的前端框架(Angular, Vue)都支持双向绑定(MVVM)技术，其中M(Model)指数据层，V(View)指视图层，所谓双向绑定是指Model层发生变化(比如服务器数据更新)，导致对应View层更新，View层产生用户交互，也会反映到Model层。这种机制看起来方便，但在实际应用中，一个Model更新可能导致多个View和Model连锁更新(Cascading Update)。Model可以更新Model，Model可以更新View，View可以更新Model，开发者很难完全掌控数据流，比如到了后期完全不知道View的变化是由那个局部变更导致的。整个关系图看起来像是这样:

![](/assets/image/201805/mvvm.png)

 Flux为此给出了单向数据流的解决方案，React的单向数据流指的是View层内部的自顶向下的数据流，这里指的整个Web App 的单向数据流，在Flux中，主要有四个部分:
 
 - View: 在Flux中，View层完全是Store层的展现。它订阅Store的变更(change event)，并反馈到界面上。Flux本身支持你使用任意的前端框架，但Flux的理念与React最为契合(毕竟都源自于Facebook)。
 - Store: 即应用数据，Store的数据只能由Action更新(对外只有get方法)，每个Store决定自己响应哪些Action，并更新自身，更新完成之后，抛出变更事件(change event)。
 - Action: 描述应用的内部接口，它代表任何能与应用交互的方式(比如界面交互，后台更新等)，在Flux中，Action被简单定义为Type+Data。
 - Dispatcher: 如其名，它负责接收所有的Action，并将其派发到注册到它的Store，每个Store都会收到所有的Action。所有的Action都会经由Dispatcher。
 
Flux通过加入Dispatcher和Action避免了Model对View的依赖，形成单向数据流:

![](/assets/image/201805/react-one-way-dataflow.png)

假设我们有个Todo应用，在Flux中，一个典型的交互流程如下:

1. View层(被挂载时)订阅TodoStore的内容变更
2. View层获取TodoStore中所有的TodoList并渲染
3. 用户在界面上输入一条新Todo内容
4. View捕捉到该输入事件，通过Dispatcher派发一个Action，Type为"add-todo"，Data为用户输入的内容
5. TodoStore收到这个Action，判断并响应该Action(这个过程叫Reduce)，添加todo内容更新自身，然后抛出更新事件(change event)
6. View层收到该change event，从TodoStore中获取最新数据，并刷新显示

整个流程看起来比双向绑定更麻烦，但实际数据流更清晰可控，这样做有如下好处:

1. View层职责很简单，只负责渲染Store变更和触发Action
2. 每个Store的变更可通过其响应的Action来判断和追踪
3. 所有的Action都必须经由全局Dispatcher，即"消息汞"

Flux官方的[todomvc](https://github.com/facebook/flux/tree/master/examples/flux-todomvc)是一个很好的入门例子

总结起来就是，Flux通过将职责细分，将模块变得更干净，然后通过必要的中间组件(如Dispatcher)，让所有的操作和状态都变得容易被追踪，调试。前面提过，Flux本身只是一种设计模式，并针对这种设计模式提供了一个简洁的实现，针对小型项目足以应付。但也有一些缺陷，，比如所有的Store都会收到所有Action，因此基于Flux单向数据流思想，衍生了一些其它第三方状态管理器(state container)，目前最火的是[Redux](https://cn.redux.js.org/)，它与Flux的主要区别是:

1. 整个应用只有一个Store
2. 将Store的State更新操作分离到Reducer中
3. Reducer用来处理Action对State树的更改，它是纯函数(替换而不是修改State)，这样每个Reducer维护State树的一部分
4. 由于只有一个Store，Flux中的Dispather变成了Store的一个函数

当然，框架这种东西，在思想确定后，根据项目选合适的就行了。并不是越复杂越好。