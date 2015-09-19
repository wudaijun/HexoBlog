---
layout: post
title: skynet gateserver
categories:
- gameserver
tags:
- lua
- skynet
---

skynet提供一个gateserver用于处理网络事件，位于lualib/snax/gateserver.lua。云风在[skynet wiki][1]上介绍了gateserver的功能和使用范例。用户可以通过向gateserver提供一个自定义handle来向gateserver注册事件处理(玩家登录，断开，数据到达等)。

<!--more-->

gateserver模块使用C编写的[socketdriver和netpack模块][2]，gateserver被加载时，会注册对"socket"(PTYPE_SOCKET)类型消息的处理，并且通过netpack.filter对收到的数据进行分包。分包完成后调用传入的handler对应的处理函数进行处理。它替上层使用者，完成对PTYPE_SOCKET消息的注册分发，以及消息分包。这样在使用时，只需提供一个handler，然后调用gateserver.start(handler)即可。

在skynet中，如果你要自定义你的gate网关服务gate.lua，需要执行以下几步：

1. `gateserver = require snax.gateserver`
2. `gateserver.start(handler)`向gateserver注册网络事件处理。
3. `skynet.call(gate, "lua", "open", conf)`在外部向你定义的gate服务发送启动消息，并传入启动配置(端口，最大连接数等)来启动gate服务。

skynet中也提供了一个gate服务，位于skynet/service/gate.lua，作为使用gateserver的一个范例。gate服务由watchdog启动，gate服务维护外部连接状态，并且转发收到的数据包。skynet提供的gate服务使用**agent**模式，关于gate服务的工作模式，在[skynet 设计综述][3]中有段介绍：

**Gate 会接受外部连接，并把连接相关信息转发给另一个服务去处理。它自己不做数据处理是因为我们需要保持 gate 实现的简洁高效。C 语言足以胜任这项工作。而包处理工作则和业务逻辑精密相关，我们可以用 Lua 完成。**

**外部信息分两类，一类是连接本身的接入和断开消息，另一类是连接上的数据包。一开始，Gate 无条件转发这两类消息到同一个处理服务。但对于连接数据包，添加一个包头无疑有性能上的开销。所以 Gate 还接收另一种工作模式：把每个不同连接上的数据包转发给不同的独立服务上。每个独立服务处理单一连接上的数据包。**

**或者，我们也可以选择把不同连接上的数据包从控制信息包（建立/断开连接）中分离开，但不区分不同连接而转发给同一数据处理服务（对数据来源不敏感，只对数据内容敏感的场合）**

**这三种模式，我分别称为 watchdog 模式，由 gate 加上包头，同时处理控制信息和数据信息的所有数据；agent 模式，让每个 agent 处理独立连接；以及 broker 模式，由一个 broker 服务处理不同连接上的所有数据包。无论是哪种模式，控制信息都是交给 watchdog 去处理的，而数据包如果不发给 watchdog 而是发送给 agent 或 broker 的话，则不会有额外的数据头（也减少了数据拷贝）。识别这些包是从外部发送进来的方法是检查消息包的类型是否为 PTYPE_CLIENT 。当然，你也可以自己定制消息类型让 gate 通知你**

skynet中提供的gate服务使用的agent模式，意味着，一开始，gate将新连接的连接控制信息转发给watchdog，如收到用户连接消息后，watchdog可以完成一些登录验证等，验证完成之后，由watchdog创建并启动agent服务，agent服务启动之后，会立即向gate服务发送一条"foward"消息，表示"现在玩家已经登录完成，你收到的消息可以交给我了"。gate收到"forward"消息会记录agent地址，并将之后玩家的数据消息转发给agent而不是之前watchdog。gate将消息转发给agent时，会通过skynet.redirect将源地址改为玩家地址，方便业务处理。


[1]: https://github.com/cloudwu/skynet/wiki/GateServer "skynet wiki: GateServer"
[2]: http://wudaijun.com/2015/02/skynet-socketserver/
[3]: http://blog.codingnow.com/2012/09/the_design_of_skynet.html "skynet 设计综述"
