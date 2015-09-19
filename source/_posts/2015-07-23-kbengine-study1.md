---
title: kbengine 源码导读(一) 网络底层
layout: post
categories: gameserver
tags: kbengine
---

## 一. network部分

**EndPoint:**

抽象一个Socket及其相关操作，隔离平台相关性。

**TcpPacket:**

代表一个TCP包，这个包只是recv收到的字节流，并不是上层协议中的消息(Message)。

**MsgHandlers:**

每个MessageHandler类对应一个消息的处理。MsgHanders维护MsgId -> MsgHandler的映射。

<!--more-->

**Channel:**

抽象一个Socket连接，每个EndPoint都有其对应的Channel，它代表和维护一个Socket连接，如缓冲Packet，统计连接状态等。
提供一个ProcessPackets(MsgHanders* handers)接口处理该Channel上所有待处理数据。

**EventPoller:**

用于注册和回调网络事件，具体的网络事件由其子类实现processPendingEvents产生，目前EventPoller有两个子类: EpollPoller和SelectorPoller，分别针对于Linux和Windows。
通过bool registerForRead(int fd, InputNotificationHandler * handler);注册套接字的可读事件，回调类需实现InputNotificationHandler接口。

**EventDispatcher:**

核心类，管理和分发所有事件，包括网络事件，定时器事件，任务队列，统计信息等等。
它包含 EventPoller Tasks  Timers64 三个组件，在每次处理时，依次在这三个组件中取出事件或任务进行处理。

**ListenerReceiver/PacketReceiver:**

继承自InputNotificationHandler，分别用于处理监听套接字和客户端套接字的可读事件，通过bool registerReadFileDescriptor(int fd, InputNotificationHandler * handler); 注册可读事件。

**NetworkInterface:**
	
维护管理监听套接字，创建监听套接字对应的ListenerReceiver，并且通过一个EndPoint -> Channel的Map管理所有已连接套接字，提供一个processChannels(MsgHandlers* handers)接口处理所有Channel上的待处理数据。这一点上，有点像NGServer:ServiceManager。


## 二. LoginApp 启动流程

**main:**

所有App都有一致的main函数，生成组件唯一ID，读取配置等，转到kbeMainT<LoginApp>

**kbeMainT:**

1. 生成公钥私钥，调试相关初始化
2. 创建单例EventDispatcher和NetworkInterface
3. 创建LoginApp，并传入EventDispatcher和NetworkInterface
4. 调用LoginApp:run()

**LoginApp:run():**

调用基类ServerApp:run()，后者调用 EventDispatcher:processUntilBreak() 开始处理各种事件

**LoginAppInterface:**

存放和注册LoginApp响应的所有消息的消息回调，参见loginapp_interface.h。
通过LoginAppInterface::messageHandlers即可导出消息处理类

**细节流程:**

1. NetworkInterface构造函数中，创建ListenSocket和ListenerReceiver，注册到EventDispatcher
2. 当有新连接到达时，EventDispatcher触发ListenerReceiver:handleInputNotification
3. handleInputNotification创建新套接字的Channel，并将Channel注册到NetworkInterface
4. 新Channel初始化时，创建新套接字对应的PacketReceiver，并注册到EventDispatcher
5. 在LoginApp::initializeEnd中，添加了一个TIMEOUT_CHECK_STATUS Timer 该Timer触发时，会最终调用networkInterface().processChannels() 处理各Channel的消息，目前该Timer是20mss
