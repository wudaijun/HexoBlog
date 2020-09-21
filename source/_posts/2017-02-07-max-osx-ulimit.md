---
title: Mac OS X下的资源限制
layout: post
tags:
- system
- macosx
categories: system

---

系统的资源是有限的(如CPU，内存，内核所能打开的最大文件数等)，资源限制对针对进程能使用的系统资源设定上限。防止恶意进程无限制地占用系统资源。

资源限制分为两种，硬限制(Hard Limit)和软限制(Soft Limit)，软限制作用于实际进程并且可以修改，但不能超过硬限制，硬限制只有Root权限才能修改。

## 相关命令

在Mac OS X下，有如下三个命令与系统资源有关。

### launchctl

launchctl管理OS X的启动脚本，控制启动计算机时需要开启的服务(通过后台进程launchd)。也可以设置定时执行特定任务的脚本，类似Linux cron。

例如，开机时自动启动Apache服务器：

	$ sudo launchctl load -w /System/Library/LaunchDaemons/org.apache.httpd.plist

<!--more-->

关于launchctl的plist格式和用法参考:

1. [launchctl man page](https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man1/launchctl.1.html)
2. [launchd plist man page](https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man5/launchd.plist.5.html)
3. [mac-os-x-launchd-is-cool](http://paul.annesley.cc/2012/09/mac-os-x-launchd-is-cool/)
4. [creating launchd jobs](https://developer.apple.com/library/content/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

简单来说，plist文件用类似XML格式定义了一个命令(及启动参数)和该命令的执行方式(定时执行，系统启动执行，用户登录执行等)。我们这里不着重讨论，我们关心launchctl中如何查看/更改系统资源限制。

	# Usage: launchctl limit [<limit-name> [<both-limits> | <soft-limit> <hard-limit>]
	# 查看文件描述符限制
	launchctl limit maxfiles
	maxfiles    256            unlimited 

	# 修改软限制为512 系统重启失效
	sudo launchctl limit maxfiles 512 unlimited
	
	# 可将launchctl子命令写入/etc/launchd.conf中
	# 在launchd启动时 会执行该文件中的命令
	limit maxfiles 512 unlimited
	
通过将更改命令写入plist文件，并在启动时执行，也可永久更改资源限制：

1. 新建Library/LaunchDaemons/limit.maxfiles.plist文件，写入

		<?xml version="1.0" encoding="UTF-8"?>  
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"  
		        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">  
		  <dict>
		    <key>Label</key>
		    <string>limit.maxfiles</string>
		    <key>ProgramArguments</key>
		    <array>
		      <string>launchctl</string>
		      <string>limit</string>
		      <string>maxfiles</string>
		      <string>64000</string>
		      <string>524288</string>
		    </array>
		    <key>RunAtLoad</key>
		    <true/>
		    <key>ServiceIPC</key>
		    <false/>
		  </dict>
		</plist>
2. 修改文件权限
	
		sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist
		sudo chmod 644 /Library/LaunchDaemons/limit.maxfiles.plist
	
3. 加载plist文件(或重启系统后生效 launchd在启动时会自动加载该目录的plist)

		sudo launchctl load -w /Library/LaunchDaemons/limit.maxfiles.plist
4. 确认更改后的限制

		launchctl limit maxfiles
		
### sysctl

大多数类Unix系统都通过(Linux/*BSD/OS X)都提供该命令来更改资源限制和内核配置：

	# 查看当前内核和进程能打开的文件描述符限制
	$ sysctl -A | grep kern.maxfiles
	kern.maxfiles: 12288 			# 系统级的限制
	kern.maxfilesperproc: 10240	# 内核级的限制
	
	# 通过sysctl命令热更改 系统重启后失效
	$ sysctl -w kern.maxfilesperproc=20480
	
	# 通过配置文件永久更改 重启生效
	# 在/etc/sysctl.conf中写入
	kern.maxfiles=20480 kern.maxfilesperproc=24576
	
### ulimit

ulimit是shell的内置命令，用于查看/更改当前shell及其创建的子进程的资源限制。使用比较简单：

	# 查看当前shell(及其子进程)的所有限制
	ulimit -a
	# 改变进程能打开的最大文件描述符数软限制 当shell关闭后失效
	# 将其写入对应shell的startup文件(如~/.bashrc, ~/.zshrc)，可保留更改
	ulimit -S -n 1024

## 区别联系

这三个命令的关系在Mac OS X各版本中尤其混乱，先说说本人的一些试验(Mac OS X 10.10.3)：

- 在默认配置下(不配置plist和sysctl.conf)，launchctl的maxfiles默认值为(256, unlimited)，sysctl的maxfiles默认值为(12288, 10240)，而ulimit -n得到的值为4864。
- 当不定义plist而定义sysctl.conf，那么重启后launchctl和ulimit看到的上限仍为默认值，sysctl看到的上限与sysctl.conf定义的一致。
- 当同时在`/etc/sysctl.conf`和`/Library/LaunchDaemons/limit.maxfiles.plist`中定义maxfiles时，plist文件中的配置会覆盖sysctl.conf中的配置。如果通过系统重启应用plist，三个命令看到的上限均为plist配置。如果通过launchctl load加载plist，则会同步影响sysctl看到的上限，而不会影响shell下的ulimit上限。
- 如果通过launchctl配置的软上限和硬上限分别为S和H(非unlimited)，那么通过launchctl应用配置后最终得到软上限和硬上限都为S。如果设定的上限为S和unlimited，实际上应用的参数为S和10240(sysctl中kern.maxfilesperproc默认值)，当S>10240时，会设置失败，S<10240时，会得到(S, 10240)
- `ulimit -H -n 1000` 降低硬上限无需Root权限，升高则需要

趁着头大，还可以看看这几篇文章:

1. [open files limit does not work as before in osx yosemite](http://superuser.com/questions/827984/open-files-limit-does-not-work-as-before-in-osx-yosemite)
2. [maximum files in mac os x](http://krypted.com/mac-os-x/maximum-files-in-mac-os-x/)
3. [how to persist ulimit settings in osx mavericks](http://unix.stackexchange.com/questions/108174/how-to-persist-ulimit-settings-in-osx-mavericks)
4. [open files limit in max os x](https://docs.basho.com/riak/kv/2.2.0/using/performance/open-files-limit/#mac-os-x)
5. [increase the maximum number of open file descriptors in snow leopard](http://superuser.com/questions/302754/increase-the-maximum-number-of-open-file-descriptors-in-snow-leopard)

网上对Mac OS X各版本的解决方案各不相同，并且对这三个命令(特别是launchctl和sysctl)在资源限制上的联系与区别也没有清晰的解释。

按照我的理解和折腾出来的经验：

1. ulimit只影响当前Shell下的进程，并且受限于kern.maxfilesperproc
2. 如果配置了plist，那么重启后，ulimit和sysctl均会继承plist中的值
3. 热修改sysctl上限值不会影响launchctl，而反之，launchctl会影响sysctl上限值

综上，在Mac OS X 10.10(我的版本，没试过之前的)之后，使用plist是最合理的方案(但launchctl貌似只能设定一样的软限制和硬限制，如果将硬限制设为ulimited，则会使用kern.maxfilesperproc值)。在系统重启后，kern.maxfilesperproc和ulimit -n都会继承plist maxfiles的值。

