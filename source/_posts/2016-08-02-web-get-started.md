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
