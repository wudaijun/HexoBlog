---
title: web 笔记
layout: post
categories: web
tags:
- web
- python

---

一些简单的web学习笔记，用于在需要时快速搭建一个可用的网站。

#### 基础知识

1. HTML：常用标签，布局，脚本。
2. CSS: 了解各种选择器，以及各级(外部,内部,内联)样式表的定义方式和折叠规则。
3. JS: 语法比较简单，用到的时候再了解。

#### 后端框架

由于Python的原因，选用了[web.py][]这个非常轻量的框架，之前也看过Rails，用起来觉得很"神奇"，但约定和黑魔法太多，不合个人口味。

#### 模板引擎

模板引擎用于将用户界面和业务数据分离，使用模板语言，来根据业务数据动态生成HTML网页，简化HTML的书写。简单了解了一下Python的模板引擎，[Jinja2][]似乎是个不错的选择，速度块，语法易懂，文档全面。

#### 前端框架

前端框架定义一系列可复用，可扩展的CSS样式，常用组件，和JS插件等。让用户在排版样式上少操点心，直接拿来用就行了。目前觉得[Bootstrap][]还不错，社区庞大，稳定，有多套可视化的布局系统，虽然不是特别灵活，但可以用来熟悉各个组件，再把代码拿下来DIY一下。

#### 其它类库

除此之外，可能还需要用到一些第三方的类库，如Python的MongoDB库[pymongo]()，Json的解析和渲染库[pretty-json][]等。在开发过程中要善于搜索，提高开发效率。

#### 综合使用



[Bootstrap]: http://www.runoob.com/bootstrap/bootstrap-tutorial.html
[web.py]: http://webpy.org/docs/0.3/tutorial
[jinja2]: http://docs.jinkan.org/docs/jinja2/
[pretty-json]: "https://github.com/warfares/pretty-json"
[pymongo]: "https://github.com/mongodb/mongo-python-driver"




