---
title: Erlang 热更新
layout: post
tags: erlang
categories: erlang
---

erlang 热更是指在erlang系统不停止运行的情况下，对模块代码进行更新的特性，这也是erlang最神奇的特性之一。特别适用于游戏服务器，做活动更新，漏洞修复等。

## 一. 简单示例

```
%% 示例一 
-module(test).

-export([start/0, run/0]).

f() ->
	io:format("this is old code~n").

run() ->
	f(),
	timer:sleep(5000),
	?MODULE:run().

start() ->
	spawn(fun() -> run() end).
```

<!--more-->

1. 在erl shell中运行test:

		Eshell V6.3.1  (abort with ^G)
		1> c(test).
		{ok,test}
		2> test:start().
		this is old code
		<0.39.0>
		this is old code
		this is old code

2. 修改test.erl代码，将f()输出改为 `io:format("this is new code~n").`。
3. 在erl shell中，**重新编译并加载**test模块。

	可通过`erlc test.erl`完成模块编译，然后在erl shell中通过`l(test).`完成加载。也可直接在erl shell 中通过`c(test).`单步完成编译和加载。
	
		3> c(test).
		{ok,test}
	
4. 观察完整`test:run()`运行结果：

		1> c(test).
		{ok,test}
		2> test:run().
		this is old code
		<0.39.0>
		this is old code
		this is old code
		3> c(test).
		{ok,test}
		this is new code
		this is new code
		...

## 二. 热更原理

### 2.1 两个条件

Erlang代码热更需要两个基本条件：

- 将修改后的代码重新编译并加载
- 只有外部调用(完全限定方式调用)才会使用新版本的代码


第一个条件在上面示例中已经做过，要注意的是，使用erlc命令行工具编译.erl源文件后，需要在erl shell中加载模块，才能将新模块代码更新到erlang虚拟机中。而我们平时通过erlc编译，然后直接进入erl shell使用模块，事实上是Erlang虚拟机自动在系统路径中查找并加载了对应模块。

第二个条件所谓的外部调用(external calls)，即 `Mod:Func(Arg)` 形式的调用。而对应的本地调用是指 `Func(Arg)`。本地调用的函数比外部调用更快，并且调用的函数无需导出。erlang热更新只会对外部调用应用最新的模块代码，而对于本地调用则会一直使用旧版本的代码。

在上面的例子中，我们在尾递归中使用`?MODULE:run()`实现了外部调用，因此每一次都会检查并应用最新的模块代码。而如果将该调用其改为run()。则将一直使用当前版本的代码，始终输出`this is old code`。

需要注意的是，**erlang更新虽然以模块为单位，但却执行"部分更新"，即对于某外部调用f()，运行时系统仅更新f()函数所引用的代码，即f()函数和其依赖的函数(无论何种调用形式)的代码。**比如示例一中，对run函数的外部调用，完成了对f()函数的代码更新，因为run()函数依赖f()函数。

而反过来，对f()的外部调用，不会更新run()的代码：

```
%% 示例二
-module(test2).
-export([start/0, f/0]).

f() ->
    io:format("this is old code~n").

run() ->
    ?MODULE:f(),
    timer:sleep(5000),
    run().

start() ->
    spawn(fun() -> run() end).
 
```

编译并运行，再修改test2.erl:

```
%% 示例二 新版本代码
-module(test2).
-export([start/0, f/0]).

f() ->
	io:format("this is new code~n").

run() ->
	io:format("say hello~n"),
	?MODULE:f(),
	timer:sleep(5000),
	run().

start() ->
	spawn(fun() -> run() end).
```

编译并加载新模块代码，得到的输出将和示例一类似，而不会打印出"say hello"。


### 2.2 新旧更迭

当模块有新版本的代码被载入时，之后对该模块执行的外部调用将依次加载模块最新代码，其它没有更新模块代码的进程仍然可以使用模块的当前版本(现在已经是旧版本)代码。erlang系统中同一模块最多可以存在两个版本的代码同时运行。

如果有进程一直在执行旧版本代码，没有更新，也没有结束，那么当模块代码需要再次更新时，erlang将kill掉仍在执行旧版本代码的进程，然后再执行本次更新。

### 2.3 更新策略

erlang中的热更是通过code\_server模块来实现的，code\_server模块是kernel的一部分，它的职责是将已经编译好的模块加载到运行时环境。code\_server有两种启动策略，embedded和interactive(默认)两种模式：

- embeded模式：指模块加载顺序需要预先定义好，code\_server会严格按照加载顺序来加载模块
- interactive模式：模块只有在被引用到时才会被加载

## 三. 控制更新

如果要在模块代码中实现对更新机制的控制，比如代码希望处理完某个逻辑流程之后，检查并应用更新。可以如下这样：

```
%% 示例三
-module(hotfix).
-export([server/1, upgrade/1, start/0]).
 
-record(state, {version, data}).

server(State) ->
	receive
		update ->
			NewState = ?MODULE:upgrade(State),
			io:format("Upgrade Completed. Now verson: ~p~n", [NewState#state.version]),
			?MODULE:server(NewState);  %% loop in the new version of the module
		_SomeMessage ->
			%% do something here
			io:format("Stay Old~n"),
			server(State)  %% stay in the same version no matter what.
	end.

upgrade(State) ->
	%% transform and return the state here.
	io:format("Upgrading Code~n"),
	NewState = State#state{version=2.0},
	NewState.


start() ->
	spawn(fun() -> server(#state{version=1.0}) end).
```

示例三中，main loop 只有在收到update消息后，才会执行更新，否则通过本地调用，始终执行当前版本的代码。而发送update消息的时机可以由程序灵活控制。

在执行更新时，代码通过`?MODULE:upgrade(State)`来预热代码，对数据结构进行更新处理，upgrade函数由本次代码更新者提供，因此能够非常安全地进行版本过渡。之后再调用`?MODULE:server(NewState)`来进行主循环代码的更新。

测试一下(这里并没真正修改代码)：

	Eshell V6.3.1  (abort with ^G)
	1> c(hotfix).
	{ok,hotfix}
	2> Pid = hotfix:start().
	<0.39.0>
	3> Pid ! hello.
	Stay Old
	hello
	4> Pid ! update.
	Upgrading Code
	Upgrade Completed. Now verson: 2.0
	update

## 四. 参考

- http://learnyousomeerlang.com/designing-a-concurrent-application#hot-code-loving
- http://www.erlang.org/doc/reference_manual/code_loading.html#id86381
