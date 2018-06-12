---
title: Linux 作业管理
layout: post
categories: os
tags:
- os
- linux

---


### 进程组/会话

简要概念：

- 进程组：N(N>=1)个进程的集合，通常在同一作业中关联起来(通过管道)。进程组的ID(PGID)即为进程组组长的PID。进程必定且只能属于一个进程组，只有进程组中一个进程存在，进程组就存在，与组长进程终止与否无关。进程组的概念提出主要是为了进程管理与信号分发
- 会话：N(N>=1)个进程组的集合，创建会话的进程叫会话首进程。会话ID即为会话首进程PID
- 控制终端：如果会话有控制终端，建立与控制终端连接的会话首进程叫控制进程(通常就是Shell进程)，当前与终端交互的进程组为前台进程组，其余进程组成为后台进程组
- 无论合适输入终端的退出键，都会将退出信号发送到前台进程组的所有进程
- 如果控制终端断开连接，则将挂掉信号(SIGHUP)发送至控制进程(会话首进程)，SIGHUP信号默认将导致控制进程终止

<!--more-->

例如，打开Bash，输入：
          proc1 | proc2 &
          proc3 | proc4 | proc5
       
进程关系如下图所示：
 
![](/assets/image/201608/linux-session-process.png  "进程组，会话和控制终端")

### 作业控制信号

- SIGCHLD: 子进程终止
- SIGTTIN: 后台进程组成员读控制终端
- SIGTTOU: 后台进程组写控制终端
- SIGCONT:  如果进程已停止，则使其继续运行(fg & bg)
- SIGSTOP: 进程停止信号，不能被捕获或忽略
- SIGTSTP: 交互式停止信号(Ctrl+Z)
- SIGINT: 中断信号(Ctrl+C)
- SIGQUIT: 退出信号(Ctrl+\)

SIGCHILD信号在子进程终止或停止时向父进程发送，系统默认将忽略该信号，如果父进程希望知晓子进程状态变更，应捕获该信号。

对于SIGTTIN和SIGTTOU信号，在后台作业尝试读取控制终端时，终端驱动程序知道它是个后台作业，于是将向改进程发送SIGTTIN信号，该信号默认将导致进程被挂起(停止)：

	▶ /usr/local/opt/coreutils/libexec/gnubin/cat > file &                                                                                                                   
	[1] 44978
	[1]  + 44978 suspended (tty input)  /usr/local/opt/coreutils/libexec/gnubin/cat > file
	▶ fg                                                                                                                                                                     
	[1]  + 44978 continued  /usr/local/opt/coreutils/libexec/gnubin/cat > file
	Hello World! // 重新获得终端 读取输入
	[Ctrl+D] // 键入EOF
	  
当后台作业尝试写终端时，默认情况下，后台作业的输出将成功输出到控制终端，但我们可以通过stty命令禁止后台作业向控制终端写，此时终端驱动程序向进程发送SIGTTOU信号：

	▶ /usr/local/opt/coreutils/libexec/gnubin/cat file &
	[1] 46166
	Hello World!
	[1]  + 46166 done       /usr/local/opt/coreutils/libexec/gnubin/cat file
	▶ stty tostop  // 禁止后台作业向控制终端写
	▶ /usr/local/opt/coreutils/libexec/gnubin/cat file & 
	[1] 46290
	[1]  + 46290 suspended (tty output)  /usr/local/opt/coreutils/libexec/gnubin/cat file
	▶ fg
	[1]  + 46290 continued  /usr/local/opt/coreutils/libexec/gnubin/cat file
	Hello World!
	
注意，在MacOS X上，自带的cat程序有BUG，不是interrupt-safe的，在MacOS X上，尝试恢复cat程序的执行将得到`cat: stdin: Interrupted system call`错误，[这篇文章](http://factor-language.blogspot.com/2010/09/two-things-every-unix-developer-should.html)和APUE 9.8节均提到了这个问题，因此我使用的是brew安装的GNU版本cat命令，安装方案参见[这里](https://www.topbug.net/blog/2013/04/14/install-and-use-gnu-command-line-tools-in-mac-os-x/)。

关于SIGTSTP和SIGSTOP的区别，前者通常由键盘产生，可被捕获，当通过Ctrl+Z将前台作业放入后台时，前台作业收到该信号，意思是"从哪儿来到哪儿去"。而SIGSTOP通常由kill产生，不可被捕获或忽略，意思是"在那里待着别动"。两者均可由SIGCONT信号恢复运行。

对于键盘输入产生的信号，控制进程将信号发送至前台进程组的所有进程。

作业控制信号间有某些交互，当对一个进程产生四种停止信号(SIGTSTP,SIGSTOP,SIGTTIN,SIGTTOU)中的一种时，对该进程的任意未决SIGCONT信号将被丢弃，同样，当产生SIGCONT信号时，对同一进程的任意停止信号将被丢弃。

### 作业管理

- & 将作业放入后台执行，如果没有进行重定向，数据流仍然会输出到前台
- Ctrl+C 强制中断前台当前作业执行
- Ctrl+Z 将作业挂到后台
- jobs -l 查看所有作业，作业ID和其PID
- fg %作业ID 将后台作业拿到前台来处理
- bg %作业ID 将后台作业由挂起变为执行
- kill -signal %作业ID 向指定作业的所有进程发送信号

作业管理的后台不是系统后台，因此，上述的任务管理依旧与终端有关，当远程连接的终端断开连接时，SIGHUP信号默认将导致改会话上所有的任务都会被中断。

### 脱机管理

- nohup: nohup CMD & 将任务放在后台执行，并忽略SIGHUP挂掉信号，但是在人机交互上比较麻烦
- screen: 一个可以在多个进程之间多路复用一个物理终端的窗口管理器，在远端服务器上运行screen，开启一个新会话并执行任务，在终端断开后，任务继续执行，下次登录再attach上screen会话即可，Linux发行版自带
- tmux: 功能类似于screen，但在分屏切换，配置方面更强大，完全可作为本地终端使用



