---
title: 【译】进程和错误
layout: post
tags: erlang
categories: erlang

---

[learn some erlang](http://learnyousomeerlang.com/content)上很喜欢的一个章节，主要阐述进程，链接，监视，信号捕获等。花了两天的时间才翻译完(- -)。第一次翻译文章，真心不是件容易的事。但也受益匪浅，平时一晃而过的地方，现在却要字字推敲。这是初稿，后续慢慢校正。原文地址：http://learnyousomeerlang.com/errors-and-processes

</br>
---
</br>

<!--more-->

### 链接

链接(link)是两个进程之间的一种特殊的关系。一旦这种关系建立，如果任意一端的进程发生异常，错误，或退出(参见[Errors and Exceptions](http://learnyousomeerlang.com/errors-and-exceptions))，链接的另一端进程将一并退出。

这是个很有用的概念，源自于Erlang的原则"鼓励崩溃"：如果发生错误的进程崩溃了而那些依赖它的进程不受影响，那么之后所有这些依赖进程都需要处理这种依赖缺失。让它们都退出再重启整组进程通常是一个可行的方案。链接正提供了这种方案所需。

要为两个进程设置链接，Erlang提供了基础函数`link/1`，它接收一个Pid作为参数。这个函数将在当前进程和Pid进程之前创建一个链接。要取消链接，可使用`ulink/1`。当链接的一个进程崩溃，将发送一个特殊的消息，该消息描述了哪个进程出于什么原因而发送故障。如果进程正常退出(如正常执行完其主函数)，这类消息将不会被发送。我将首先介绍这个新函数，它是[linkmon.erl](http://learnyousomeerlang.com/static/erlang/linkmon.erl)的一部分：

	myproc() ->
		timer:sleep(5000),
		exit(reason).
		
如果你尝试下面的调用(并且在两次spawn操作之间等待5秒钟)，你就能看到shell只有在两个进程之间设置了链接时，才会因`reason`而崩溃。

	1> c(linkmon).
	{ok,linkmon}
	2> spawn(fun linkmon:myproc/0).
	<0.52.0>
	3> link(spawn(fun linkmon:myproc/0)).
	true
	** exception error: reason	% 译注：此时Shell Process已经崩溃，只是立即被重启了。通过self()查看前后的Pid是不同的
	
或者，我们可以用图片来阐述：

![](/assets/image/erlang/process_link_exit.png "")

然后，这个`{'EXIT', B, Reason}`消息并不能被`try ... catch`捕获。我们需要通过其它机制来实现这点，我们将在后面看到。

值得注意的是，链接通常被用来建立一个需要一起退出的进程组：

	chain(0) ->
		receive
			_ -> ok
		after 2000 ->
			exit("chain dies here")
		end;
	chain(N) ->
		Pid = spawn(fun() -> chain(N-1) end),
		link(Pid),
		receive
			_ -> ok
		end.
		
`chain`函数接收一个整型参数N，创建N个依次相互链接的进程。为了能够将N-1参数传递给下一个`chain`进程(也就是`spawn/1`)，我将函数调用放在了一个匿名函数中，因此它不再需要参数。调用`spawn(?MODULE, chain, [N-1])`能达到同样的效果。

这里，我将有一条链式的进程组，并且随着它们的后继者退出而退出：

	4> c(linkmon).              
	{ok,linkmon}
	5> link(spawn(linkmon, chain, [3])).
	true
	** exception error: "chain dies here"
	
正如你所看到的，Shell将从其它进程收到死亡信号。这幅图阐述产生的进程依次链接：

	[shell] == [3] == [2] == [1] == [0]
	[shell] == [3] == [2] == [1] == *dead*
	[shell] == [3] == [2] == *dead*
	[shell] == [3] == *dead*
	[shell] == *dead*
	*dead, error message shown*
	[shell] <-- restarted
	
在执行`linkmon:chain(0)`的进程死掉之后，错误消息沿着链接链依次传播，直播Shell进程也因此崩溃。崩溃可能发生在任何已经链接的进程中，因为链接是双向的，你只需要令其中一个死亡，其它进程都会随之死亡。

	注意：如果你想要通过Shell杀掉其它进程，你可以使用`exit/2`函数，如：`exit(Pid, Reason)`。你可以试试。
	
	链接操作无法被累加，如果你在同样的一对进程上调用`link/1`15次，也只会实际存在一个链接，并且只需要一次`unlink/1`调用就可以解除链接。

注意，`link(spawn(Function))`或`link(spawn(M,F,A))`是通过多步实现的。在一些情况下，可能进程在被链接之前就死掉了，这样引发了未知行为。出于这个原因，Erlang添加了`spawn_link/1-3`函数，它和`spawn/1-3`接收同样的参数，创建一个进程并且相`link/1`一样建立链接，但是它是一个原子操作(这个操作混合了多个指令，它可能成功或失败，但不会有其它未期望行为)。着通常更安全，并且你也省去了一堆圆括号。

### 信号捕获

现在回到链接和进程故障。错误在进程之间向消息那样传递，这类特殊的消息叫做信号。退出信号是自动作用于进程的"秘密消息"，它会立即杀死进程。

我之前提到过很多次，为了高可靠性，应用程序需要能够很快的杀掉和重启进程。现在，链接很好地完成了杀死进程的任务，还差进程重启。

为了重启一个进程，我们首先需要一种方式来知道有进程挂了。这可以通过在链接之上封装一层叫系统进程的概念来完成。系统进程其实就是普通进程，只不过他们可以将退出信号转换为普通消息。在一个运行进程上执行`precess_floag(trap_exit, true)`可以
将其转换为系统进程。没什么比例子更具有说服力了，我们来试试。我首先在一个系统进程上将重演chain例子：

	1> process_flag(trap_exit, true).
	true
	2> spawn_link(fun() -> linkmon:chain(3) end).
	<0.49.0>
	3> receive X -> X end.
	{'EXIT',<0.49.0>,"chain dies here"}
	
现在事情变得有趣了，回到我们的图例中，现在发生的是这样：

	[shell] == [3] == [2] == [1] == [0]
	[shell] == [3] == [2] == [1] == *dead*
	[shell] == [3] == [2] == *dead*
	[shell] == [3] == *dead*
	[shell] <-- {'EXIT,Pid,"chain dies here"} -- *dead*
	[shell] <-- still alive!
	
这就是让我们可以快速重启进程的机制。通过在程序中使用系统进程，创建一个只负责检查进程崩溃并且在任意时间都能重启故障进程的进程变得很简单。我将在下一章真正用到了这项技术时，更详细地阐述这点。

现在，我想回到我们在[exceptions](http://learnyousomeerlang.com/errors-and-exceptions)这一章看到的异常函数，并且展示它在设置了`trap exit`的进程上有何种行为。我们首先试验没有系统进程的情况。我连续地在相邻的进程上展示了未被捕获的异常，错误，和退出所造成的结果：

	Exception source:	spawn_link(fun() -> ok end)
	Untrapped Result:	- nothing - 
	Trapped	  Result:	{'EXIT', <0.61.0>, normal}
	注：进程正常退出，没有任何故障。这有点像`catch exit(normal)`的结果，除了在tuple中添加了Pid以知晓是哪个进程退出了。
	
	Exception source:	spawn_link(fun() -> exit(reason) end)
	Untrapped Result:	** exception exit: reason
	Trapped   Result:	{'EXIT', <0.55.0>, reason}
	注：进程由于客观原因而终止，在这种情况下，如果没有捕获退出信号(trap exit)，当前进程被终止，否则你将收到以上消息。
	
	Exception source：	spawn_link(fun() -> exit(normal) end)
	Untrapped Result:	- nothing -
	Trapped   Result:	{'EXIT', <0.58.0>, normal}
	注：这相当于模仿进程正常终止。在一些情况下，你可能希望像正常流程一样杀掉进程，不需要任何异常流出。
	
	Exception source:	spawn_link(fun() -> 1/0 end)
	Untrapped Result:	Error in process <0.44.0> with exit value: {badarith, [{erlang, '/', [1,0]}]}
	Trapped   Result:	{'EXIT', <0.52.0>, {badarith, [{erlang, '/', [1,0]}]}}
	注：{badarith, Reason}不会被try ... catch捕获，继而转换为'EXIT'消息。这一点上来看，它的行为很像exit(reason)，但是有调用堆栈，可以了解到更多的信息。
	
	Exception source:	spawn_link(fun() -> erlang:error(reason) end)
	Untrapped Result:	Error in process <0.47.0> with exit value: {reason, [{erlang, apply, 2}]}
	Trapped   Result:	{'EXIT', <0.74.0>, {reason, [{erlang, apply, 2}]}}
	注：和1/0的情况很像，这是正常的，erlang:error/1 就是为了让你可以做到这一点。
	
	Exception source:	spawn_link(fun() -> throw(rocks) end)
	Untrapped Result:	Error in process <0.51.0> with exit value: {{nocatch, rocks}, [{erlang, apply, 2}]}
	Trapped   Result:	{'EXIT', <0.79.0>, {{nocatch, rocks}, [{erlang, apply, 2}]}}
	注：由于抛出的异常没有被try ... catch捕获，它向上转换为一个nocatch错误，然后再转换为`EXIT`消息。如果没有捕获退出信号，当前进程当终止，否则工作正常。
	
这些都是一般异常。通常情况下：一切都工作得很好。当异常发生：进程死亡，不同的信号被发送出去。

然后来介绍`exit/2`，它在Erlang进程中就相当于一把枪。它可以让一个进程杀掉远端另一个进程。以下是一些可能的调用情况：

	Exception source: 	exit(self(), normal)
	Untrapped Result: 	** exception exit: normal
	Trapped   Result: 	{'EXIT', <0.31.0>, normal}	注：当没有捕获退出信号时，exit(self(), normal)和exit(normal)作用一样。否则你将收到一条和链接进程挂掉一样格式的消息。(译注：如果忽略了{'EXIT', self(), normal}，将不能通过exit(self(), normal)的方式杀掉自己。而exit(normal)则可以在任何情况结束自己。)
	
	Exception source: 	exit(spawn_link(fun() -> timer:sleep(50000) end), normal)
	Untrapped Result: 	- nothing -
	Trapped   Result: 	- nothing -
	注：这基本上等于调用exit(Pid, normal)。这条命令基本没有做任何有用的事情，因为进程不能以normal的方式来杀掉远端进程。(译注：通过normal的方式kill远端进程是无效的)。
	
	Exception source: 	exit(spawn_link(fun() -> timer:sleep(50000) end), reason)
	Untrapped Result: 	** exception exit: reason
	Trapped   Result: 	{'EXIT', <0.52.0>, reason}
	注：外部进程通过reason终止，看起来效果和在外部进程本身执行exit(reason)一样。
	
	Exception source: 	exit(spawn_link(fun() -> timer:sleep(50000) end), kill)
	Untrapped Result: 	** exception exit: killed
	Trapped   Result: 	{'EXIT', <0.58.0>, killed}
	注：出乎意料地，消息在从终止进程传向根源进程(译注：调用spawn的进程)时，发生了变化。根源进程收到killed而不是kill。这是因为kill是一个特殊的信号，更多的细节将在后面提到。
	
	Exception source: 	exit(self(), kill)
	Untrapped Result: 	** exception exit: killed
	Trapped   Result: 	** exception exit: killed
	注：看起来这种情况不能够被正确地捕捉到，让我们来检查一下。
	
	Exception source: 	spawn_link(fun() -> exit(kill) end)
	Untrapped Result: 	** exception exit: killed
	Trapped   Result: 	{'EXIT', <0.67.0>, kill}
	注：现在看起来更加困惑了。当其它进程通过exit(kill)杀掉自己，并且我们不捕获退出信号，我们自己的进程退出原因为killed。然而，当我们捕获退出信号，却不再是killed。
	
你可以捕获大部分的退出原因，在有些情况下，你可能想要残忍地谋杀进程：也许它捕获了退出信号，但是陷入了死循环，不能再读取任何消息。kill是一种不能被捕获的特殊信号。这一点确保了任何你想要杀掉的进程都将被终止。通常，当所有其它办法都试尽之后，kill是最后的杀手锏。

由于kill退出原因不能够捕获，因此当其它进程收到该消息时，需要转换为killed。如果不以这种方式作出改变，所有其它链接到被kill进程的进程都将相继以相同的kill原因被终止，并且继续扩散到与它们链接的进程。随之而来的是一场死亡的雪崩效应。

这也解释了为什么`exit(kill)`在被其它链接进程收到时转换成了killed(信号被修改了，这样才不会发生雪崩效应)，但是在本地捕获时(译注：这里我也没搞清楚，本地是指被kill的进程，还是指发出kill命令的进程)，仍然是kill。

如果你对这一切感到困惑，不用担心，很多程序员都为此困惑。退出信号是一头有趣的野兽。幸运的是，上面已经提及几乎所有特殊情况。一旦你明白了这些，你就可以轻松明白大多数的Erlang并发错误管理机制。

### 监视器

那么，也许谋杀掉一个进程并不是你想要的，也许你并不想将你死亡的消息通告四周，也许你应该更像一个追踪者。在这种情况下，监视器就是你想要的。

严格意义上说，监视器是一种特殊类型的链接。它与链接有两处不同：

- 监视器是单向的
- 监视可以被叠加

监视器可以让一个进程知道另一个进程上发生了什么，但是它们对彼此来说都不是必不可少的。

另一点，像上面所列出的一样，监视引用是可以被叠加的。乍一看这并没什么用，但是这对写需要统计其它进程情况的库很有帮助。

正如你所了解的，链接更像是一种组织结构。当你在架构你的应用程序时，你需要决定每个进程做什么，依赖于什么。一些进程将被用来监督其它进程，一些进程不能没有其兄弟进程而独立存在，等等。这种结构通常是固定的，并且事先决定好的。链接对于这种情况是非常适用的，但除此之外，一般并没有使用它的必要。

但是当你在使用两三个不同的库，而它们都需要知道其它进程存活与否，这种情况会发送什么？如果你尝试使用链接，那么当你尝试解除链接的时候，就会很快遇到问题。因为链接是不可叠加的，一旦取消了其中一个，你就取消了所有(译注：调用库时，仍然是在当前进程)在此之上的链接，也就破坏了其它库的所有假设。这很糟糕。因此你需要可叠加的链接，监视器就是你的解决方案。它们可以被单独地移除。另外，单向特性在库中也是很有用的，因为其它进程不应该关心上述库。

那么监视器看起来是什么样子？很简单，让我们来设置一个。相关函数是`erlang:monitor/2`，第一个参数是原子`process`，第二个参数是进程Pid：

	1> erlang:monitor(process, spawn(fun() -> timer:sleep(500) end)).
	#Ref<0.0.0.77>
	2> flush().
	Shell got {'DOWN',#Ref<0.0.0.77>,process,<0.63.0>,normal}
	ok
	
每当你监视的进程挂掉时，你都会收到类似消息。消息格式为`{'DOWN', MonitorReference, process, Pid, Reason}`。引用被用来取消监视，记住，监视是可以叠加的，所以可能不止一个。引用允许你以独特的方式追踪它们。还要注意，和链接一样，有一个原子函数可以在创建进程的同时监控它，`spawn_monitor/3`：

	3> {Pid, Ref} = spawn_monitor(fun() -> receive _ -> exit(boom) end end).
	{<0.73.0>,#Ref<0.0.0.100>}
	4> erlang:demonitor(Ref).
	true
	5> Pid ! die.
	die
	6> flush().
	ok
	
在这个例子中，我们在进程崩溃之前取消了监视，因此我们没有追踪到它的死亡。函数`demonitor/2`也存在，并且给出了更多信息，第二个参数是一个选项列表。目前只有两个选项，`info`和`flush`：

	7> f().
	ok
	8> {Pid, Ref} = spawn_monitor(fun() -> receive _ -> exit(boom) end end).
	{<0.35.0>,#Ref<0.0.0.35>}
	9> Pid ! die.
	die
	10> erlang:demonitor(Ref, [flush, info]).
	false
	11> flush().
	ok
	
`info`选项将告诉你在你取消监视的时候监视是否存在，因此第10行返回false。使用`flush`选项将移除信箱中的`DOWN`消息(译注：其它消息不受影响)，导致`flush()`操作没有在当前进程信箱中取得任何消息。

### 命名的进程

理解了链接和监视之后，还有一个问题需要解决。我们使用[linkmon.erl](http://learnyousomeerlang.com/static/erlang/linkmon.erl)模块的以下函数：

	start_critic() ->
		spawn(?MODULE, critic, []).
	 
	judge(Pid, Band, Album) ->
		Pid ! {self(), {Band, Album}},
		receive
			{Pid, Criticism} -> Criticism
		after 2000 ->
			timeout
		end.
	 
	critic() ->
		receive
			{From, {"Rage Against the Turing Machine", "Unit Testify"}} ->
				From ! {self(), "They are great!"};
			{From, {"System of a Downtime", "Memoize"}} ->
				From ! {self(), "They're not Johnny Crash but they're good."};
			{From, {"Johnny Crash", "The Token Ring of Fire"}} ->
				From ! {self(), "Simply incredible."};
			{From, {_Band, _Album}} ->
				From ! {self(), "They are terrible!"}
		end,
		critic().
		
现在假设我们在商店购买唱片。这里有一些听起来很有趣的专辑，但是我们不是很确定。你决定打电话给你的朋友`ctritic`(译注：后文称"鉴定家")。

	1> c(linkmon).                        
		{ok,linkmon}
	2> Critic = linkmon:start_critic().
		<0.47.0>
	3> linkmon:judge(Critic, "Genesis", "The Lambda Lies Down on Broadway").
		"They are terrible!"
		
烦人的是，我们不久后就不能再得到唱片的评论了。为了保持鉴定家一直存活，我们将写一个基本的监督者进程，它的唯一职责就是在鉴定家挂掉之后重启它。

	start_critic2() ->
		spawn(?MODULE, restarter, []).
 
	restarter() ->
		process_flag(trap_exit, true),
		Pid = spawn_link(?MODULE, critic, []),
		receive
			{'EXIT', Pid, normal} -> % not a crash
				ok;
			{'EXIT', Pid, shutdown} -> % manual termination, not a crash
				ok;
			{'EXIT', Pid, _} ->
				restarter()
		end.
		
这里，重启者就是它自己持有的进程。它会轮流启动鉴定家进程，并且一旦它异常退出，`restarter/0`将循环创建新的鉴定家。注意我添加了`{'EXIT', Pid, shudown}`条目，这是为了让我们在必要时，可以手动杀掉鉴定家进程。

我们这个方法的问题是，我们没有办法获得鉴定家进程的Pid，因此我们不能调用它并获得它的评论。Erlang解决这种问题的一个解决方案是为进程取一个名字。

为进程取名字的作用是允许你用一个原子代替不可预测的Pid。之后这个原子可以像Pid一样用来发送消息。`erlang:register/2`被用来为进程取名。如果进程死亡，它会自动失去它的名字，你也可以使用`unregister/1`手动取消名字。你可以通过`register/0`获得一个所有注册了名字的进程列表，或者通过shell命令`reg()`获得更为详尽的信息。现在我们可以像下面这样重写`restarter/0`函数：

	restarter() ->
		process_flag(trap_exit, true),
		Pid = spawn_link(?MODULE, critic, []),
		register(critic, Pid),
		receive
			{'EXIT', Pid, normal} -> % not a crash
				ok;
			{'EXIT', Pid, shutdown} -> % manual termination, not a crash
				ok;
			{'EXIT', Pid, _} ->
				restarter()
		end.
		
正如你所看到的，不管鉴定家进程的Pid是什么，`register/2`将总是为其取名为`critic`。我们还需要做的是从抽象函数中替换需要传递Pid的地方。让我们试试：

	judge2(Band, Album) ->
		critic ! {self(), {Band, Album}},
		Pid = whereis(critic),
		receive
			{Pid, Criticism} -> Criticism
		after 2000 ->
			timeout
		end.
	
这里，为了能在`receive`语句中进行模式匹配，`Pid = whereis(critic)`被用来查找鉴定家进程的Pid。我们需要这个Pid来确定我们能匹配到正确的消息(在我们说话的时候，它的信箱可能有500条消息！)。这可能是问题的来源。上面的代码假设了鉴定家进程在函数的前两行将保持一致。然而，下面的情况是完全有可能发生的：

	1. critic ! Message
			                       	2. critic receives
			                       	3. critic replies
			                       	4. critic dies
	5. whereis fails
									6. critic is restarted
	7. code crashes
	
	当然，还有一种情况可能发生：
		
	1. critic ! Message
				                   	2. critic receives
				                   	3. critic replies
				                  	4. critic dies
				              	    5. critic is restarted
	6. whereis picks up
	   wrong pid
	7. message never matches
	
如果我们不处理好的话，在一个进程中出错将可能导致另一个进程错误。在这种情况下，原子`critic`代表的值可能被多个进程看到。这就说所谓的共享状态。这里的问题是，`critic`的值可以在几乎同一时间被多个进程获取和修改，导致不一致的信息和软件错误。这类情况的通用术语为**竞态**。竞态是特别危险的，因为其依赖于事件时序。在几乎所有的并发和并行语言中，这种时序依赖于很多不可预测的因素，比如处理器有多忙，进程执行到哪了，以及你的程序在处理哪些数据。

	别麻醉了自己
	
	你可能听说过Erlang通常是没有竞态或死锁的，这令并行代码更安全。这在很多情况下都是对的，但是永远不要认为你的代码真的那样安全。命名进程只是并行代码可能出错的多种情况之一。
	
	其它例子还包括计算机访问文件(并修改它们)，多个不同的进程更新相同的数据库记录，等等。

对我们来说幸运的是，如果我们不假设命名进程保持不变的话，修复上面的代码是比较容易的。取而代之地，我们将使用引用(通过`make_ref()`创建)作为一个唯一的值来标识消息。我们需要重写`critic/0`为`critic/2`，`judge/3`为`judge2/2`：

	judge2(Band, Album) ->
		Ref = make_ref(),
	critic ! {self(), Ref, {Band, Album}},
		receive
			{Ref, Criticism} -> Criticism
		after 2000 ->
			timeout
		end.
 
	critic2() ->
		receive
			{From, Ref, {"Rage Against the Turing Machine", "Unit Testify"}} ->
				From ! {Ref, "They are great!"};
			{From, Ref, {"System of a Downtime", "Memoize"}} ->
				From ! {Ref, "They're not Johnny Crash but they're good."};
			{From, Ref, {"Johnny Crash", "The Token Ring of Fire"}} ->
				From ! {Ref, "Simply incredible."};
			{From, Ref, {_Band, _Album}} ->
				From ! {Ref, "They are terrible!"}
		end,
		critic2().
	 
并且随之改变`restarter/0`，让它通过`critic2/0`而不是`critic/0`来产生新进程。其它函数应该能保持正常工作。用户并不能察觉到变化。好吧，他们能察觉到，因为我们改变了函数名和函数参数个数，但是他们并不知道实现细节的改变和为什么这些改变如此重要。他们能看到的是他们的代码更简单了，并且不在需要Pid来调用函数了：

	6> c(linkmon).
	{ok,linkmon}
	7> linkmon:start_critic2().
	<0.55.0>
	8> linkmon:judge2("The Doors", "Light my Firewall").
	"They are terrible!"
	9> exit(whereis(critic), kill).
	true
	10> linkmon:judge2("Rage Against the Turing Machine", "Unit Testify").    
	"They are great!"
	
现在，即使我们杀掉了critic，马上会有一个新的回来解决我们的问题。这就是命名进程的作用。如果你试图通过没有注册的进程调用`linkmon:judge2/2`，一个`bad argument`错误将会被函数内的`!`操作符抛出，确保依赖于命名进程的进程，将不能在没有命名进程的情况下而运行。

	注意：如果你还记得之前的文章，原子可用的数量有限(尽管很高)。你不应该动态地创建原子。这意味着命名进程应该保留给一些虚拟机上唯一的伴随整个应用程序周期的重要的服务。
	
	如果你需要为进程命名，但是它们不是常驻进程或者它们都不是虚拟机上唯一的，那可能意味着它们需要表示为一组，链接它们，并在它们崩溃后重启可能是一个理智的选择，而不是尝试为他们动态命名。