---
title: 博客开始使用Hexo
layout: post
tags: tool
categories: tool
---

最近又开始想在博客上实现自己一直想要的摘要功能，然后倒腾jekyll，本来也没有前端基础，就博客系统而言，对我来说，简单就好，能专注写东西。但是发现jekyll偏离了这个宗旨，缺乏成熟的主题机制，可定制性太强，学习成本高。然后发现了这个[Hexo主题](https://github.com/pengloo53/Hexo-theme-light_cn)，觉得就是自己想要的功能。最终抛弃了jekyll，投向Hexo。

<!--more-->

关于Hexo的安装和使用说明，参看[官方中文文档](https://hexo.io/zh-cn/docs/index.html)。

Hexo由node.js编写，不像jekyll被Github原生支持，因此它需要本地生成html文件后，再上传到Github。不像jekyll，你的md文件，生成的html，jekyll配置，都在一个仓库中，用起来省心。Hexo在Git上存放的只是生成好的页面，像我经常切换电脑写博客，因此还需要维护：

1. Hexo主题：Hexo的主题像vim一样，都是插件式的，因此独立出来维护完善
2. source目录：原始的md文件和资源文件，以便随时随地都可以编辑文档
3. 其它文件: 如我将资源文件都放在assets目录下，因此需要生成时通过脚本将assets拷贝到public下

现在我是直接把整个Hexo放在Git上，只能说懒人有懒办法了。
