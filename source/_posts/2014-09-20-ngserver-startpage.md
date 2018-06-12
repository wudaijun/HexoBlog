---
title: NGServer 简介
layout: post
tag:
- ngserver
categories: gameserver
---

NGServer是一个迷你型C++游戏服务器框架。Github地址：https://github.com/wudaijun/NGServer。
<!--more-->

### 主要特性：

- 框架用C++(11)和boost库实现。
- 基于单进程多线程。
- 框架屏蔽了多线程实现，上层体现为服务(Service)，服务之间通过消息进行通信。
- 有比较完善灵活的的消息回调和序列化机制，更方便地实现RPC。

### 设计原则：

- 尽量小巧灵活，减少第三方库依赖，尽可能使用C++11新特性。
- 降低模块之间的耦合性，增强灵活性。

### 目前缺点：

- 当并发很高时，消息分流和拥塞控制做得不是很好。
- 服务之间，只支持通过消息异步通信。

### 更多文档：
关于NGServer的更详细的系列介绍可以在我的博客找到：http://wudaijun.com/tags/#NGServer。博客上的文章仅代表NGServer的最初设想，可能与Github上的最新代码有差异。
