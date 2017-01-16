---
title: web 初学笔记
layout: post
categories: web
tags:
- web
- python

---

一些简单的web学习笔记，用于在需要时快速搭建一个可用的网站。

### 基础知识

- HTML: 通过一套标记标签，定义网页的内容
- CSS:  通过选择器和层叠次序，定义网页的布局
- JavaScript: 通过可编程的文档对象模型(DOM)和事件响应，定义网页的行为

<!--more-->

### 后端框架

由于Python的原因，选用了[web.py][]这个非常轻量的框架，之前也看过Rails，用起来觉得很"神奇"，但约定和黑魔法太多，不合个人口味。

web.py是一个web framework，它也提供了http server的功能，但在线上环境，通常需要结合更高效专业的http server(如nginx)。这里有几种结合方案:

1. 用nginx做反向代理，将请求路由到后端web.py
2. 将web.py作为CGI/FastCGI程序，挂接到nginx/lighttpd/apache

第二种方式需要安装python flup库，它实现了CGI/FastCGI规范，并实现了这些规范的WSGI(定义flup这类服务与web.py这类framework的调用规范)接口。

#### CGI

通用网关接口(Common Gateway Interface)，是外部应用程序（CGI程序）与Web服务器之间的接口标准。CGI规范允许Web服务器执行外部程序，并将它们的输出发送给Web浏览器，CGI将Web的一组简单的静态超媒体文档变成一个完整的新的交互式媒体。

我们知道http server提供的内容通常分为静态内容和动态内容，前者通常集成于web server中。而动态内容，需要web server(如nginx)将请求传递给处理程序(如web.py)并获取返回结果。那么web server传递哪些请求内容，如何传递，处理程序如何返回生成的响应内容等细节，就需要一个通信规范，并且这个规范最好抽象于双方的具体实现，这就是CGI存在的意义，CGI程序可以用任何脚本或编程语言实现，只要这种语言具有标准输入输出和环境变量。

CGI规定每次有请求，都会启动一个CGI程序进程(对Shell script来说，就是sh或bash命令，对python等脚本语言来说，通常是对应解释器)，并且通过标准输入输出以及环境变量与CGI程序交互。CGI的缺点是反复进程启动/初始化/关闭比较消耗资源并且效率低下，难以扩展。目前CGI已经逐渐退出历史舞台。

#### web内置模块

针对CGI每次初始化进程(脚本解释器)的开销问题，一些web server(如apache)以插件的方式集成了CGI脚本的解释器(如mod\_php,mod\_perl等)，将这些解释器以模块的方式常驻，web服务器在启动时会启动这些模块，当新的动态请求到达，web服务器可利用解释器模块解析CGI脚本，避免进程fork。这种优化方式主要针对于脚本语言编写的CGI程序。

#### FastCGI
	
FastCGI在CGI进程常驻的前提下，通过进程池，进程管理器进一步提高了CGI的可伸缩性和容错性。web server将动态请求发给FastCGI进程管理器，后者会将请求分发给进程池中的某一个worker进程。

web server和FastCGI管理进程的通信方式有socks(相同主机)和tcp(不同主机)两种，这提高了FastCGI本身的可扩展性。目前FastCGI进程管理器除了web server自带的fastcgi模块之外，还有`spawn-fcgi`(分离于lighttpd)，`php-fpm`(仅用于PHP)等可替换的独立模块。

参考：

1. [什么是CGI、FASTCGI、PHP-CGI、PHP-FPM、SPAWN-FCGI?](http://hao.jser.com/archive/8184/)
2. [WSGI、flup、fastcgi、web.py的关系](https://www.douban.com/note/13508388/) 
3. [nginx[+spawn-fcgi]+flup+webpy服务搭建](http://blog.csdn.net/five3/article/details/7732832)
4. http://webpy.org/install.zh-cn
5. http://webpy.org/cookbook/index.zh-cn


### 模板引擎

模板引擎用于将用户界面和业务数据分离，使用模板语言，来根据业务数据动态生成HTML网页，简化HTML的书写。简单了解了一下Python的模板引擎，[Jinja2][]似乎是个不错的选择，速度块，语法易懂，文档全面。控制结构，模板继承都很好用。

### CSS框架

前端框架定义一系列可复用，可扩展的CSS样式，常用组件，和JS插件等。让用户在排版样式上少操点心，直接拿来用就行了。目前觉得[Bootstrap][]还不错，社区庞大，稳定，有多套可视化的布局系统。

### JS框架

[JQuery][]应该是目前最火的前端JS框架了，基于CSS选择器扩展的JQuery选择器，简化了JavaScript的书写，实现脚本与内容分离。

### 其它类库

除此之外，可能还需要用到一些第三方的类库，如Python的MongoDB库[pymongo][]，Json的解析和渲染库[pretty-json][]等。在开发过程中要善于搜索，提高开发效率。

### 综合使用

写了一个简单Demo, 很Low, 没用JS, 只是用来熟悉基本流程:

https://github.com/wudaijun/pyweb

[Bootstrap]: http://www.runoob.com/bootstrap/bootstrap-tutorial.html
[web.py]: http://webpy.org/docs/0.3/tutorial
[jinja2]: http://docs.jinkan.org/docs/jinja2/
[pretty-json]: https://github.com/warfares/pretty-json
[pymongo]: https://github.com/mongodb/mongo-python-driver
[JQuery]: http://www.runoob.com/jquery/jquery-tutorial.html
