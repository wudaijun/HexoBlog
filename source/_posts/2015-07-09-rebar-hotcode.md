---
title: rebar的热更
layout: post
tags: erlang
categories: erlang
---

由于项目开发中早早地用到了[rebar][rebar]，虽然rebar在很多方面都比自己构建原生OTP应用更方便，但是每一次修改，都需要重新编译，发布，启动，非常耗费时间，而rebar本身的[upgrade][rebar upgrade]又比较麻烦，是针对于版本发布的，不适合开发测试使用。

因此找到了一种基于.beam文件更新加载的方法，借鉴自[mochiweb reloader][mochiweb reloader]。

mochiweb reloader每隔一秒检查一次已加载的所有模块(`code:all_loaded()`)，遍历模块列表，检查其所在路径的变更状况，若模块在一秒内有变动，则通过`code:load_file(Module)`加载模块到运行时系统，执行热更。整个过程需要我们做的就是，将编译好的beam文件放到rebar rel对应的发布版本目录下，可通过`code:all_loaded()`查看各lib或app所在的发布路径，该发布路径是具有版本号的，但是由于我们在开发测试中暂时无需版本号控制，因此直接通过makefile将编译好的beam文件放到发布路径即可。

<!--more-->

mochiweb reloader在加载Module后，会执行Module:test函数(如果该函数已导出)，可通过导出该函数完成一些升级时的处理。


[mochiweb reloader]: https://github.com/mochi/mochiweb/blob/master/src/reloader.erl
[rebar]: https://github.com/basho/rebar
[rebar upgrade]: https://github.com/rebar/rebar/wiki/Upgrades
