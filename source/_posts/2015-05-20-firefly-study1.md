---
title: Firefly 学习(一)
layout: post
tags:
- firefly
- python
categories: gameserver
---

## 一. 简介
	
firefly是一款python开发的开源游戏服务器框架，基于分布式，底层使用twisted。

<!--more-->

具体介绍可参见：

- [firefly on github](firefly_on_git)
- [firefly官网](firefly_9miao)
- [firefly官方Wiki](firefly_doc)
	
firefly采用多进程方案，节点之间通过网络通信(当然你也可以创建单节点，独立完成大部分功能)，具有很好的可扩展性。

## 二. 使用

作为一个Python初学者，下面只谈一些自己对firefly的一些肤浅认识。上面的途径可以获取到更完整和深入的资料。

下面的Demo的源代码可在[我的Github](demo_github)上下载。

### 1. 流程
总体上看，如果你要使用firefly，所需要做的事就是：

- 通过配置文件定义所有节点，节点配置，节点实现文件，以及节点和节点之间的联系(通过网络端口)
- 定义节点实现文件
- 启动主节点

firefly通过配置文件来设定你的分布式服务器，然后你只需创建和启动master节点，master服务器会启动配置文件中的各个子节点：

	if __name__=="__main__":
    	from firefly.master.master import Master
    	master = Master()
    	master.config('config.json','appmain.py')
    	master.start()

config.json定义你的分布式服务，appmain.py是你的子节点公共入口，master节点已在master.start()中启动。

### 2. 配置文件

下面是一份 config.json 实例，该配置文件配置了一个无盘节点，即没有使用数据库:

	{
	"master":{"rootport":9999,"webport":9998},
	"servers":{
		"gate":{"name":"gate", "rootport":10000, "app":"app.gateserver"},
		"net":{"name":"net", "netport":10001, "name":"net", "remoteport":[{"rootport":10000, "rootname":"gate"}], "app":"app.netserver"},
		"game1":{"name":"game1", "remoteport":[{"rootport":10000, "rootname":"gate"}], "app":"app.game1server"}
	}
	}

通过配置文件已经能够很清楚地看懂该服务器的整个分布式情况：

![](/assets/image/201505/firefly_nodes.png "firefly的分布式节点")

#### master节点

master节点管理所有的节点，它有两个端口rootport和webport，顾名思义，rootport用于和和服务器中其它节点通信，webport用于后台管理，如关闭和重启所有子节点。调用master.start()后，框架会自动创建master节点并监听rootport和webport端口，后者通过[Flask](flask)实现。

#### 分布式节点

如果将master节点称为整个服务器的根节点，那么servers中定义的节点即为分布式节点，样例config中定义了四个分布式节点，gate, dbfront, net, game1。每个节点都可以定义自己的父节点(通过remoteport，可有多个父节点)，并且关联节点的实现文件(位于config所在目录 app/*.py)。其中gate是net和game1的父节点，意味着如果有网络消息需要game1节点处理，那么消息将由net->gate->game1，同理消息响应途径为：game1->gate->net。

### 3. 公共入口

appmain是我们定义的节点公共入口，它会由firefly通过`python appmain.py 节点名 配置路径`调用，节点名即为gate, dbfront, net, game1之一，配置路径即为 config.json。该入口允许我们对各分布式节点做一些预先特殊处理，在Demo的appmain.py中，仅仅是读取必须配置，通过一个firefly导出的统一节点类来启动节点:

```
#coding:utf8
"""
本模块在启动master时作为参数传入
firefly会在每个Server(除了master)启动时都调用该模块:
    cmds = 'python %s %s %s'%(self.mainpath, sername, self.configpath) [位于master/master.py, 其中self.mainpath即为本模块] 
"""
import os
import json, sys
from firefly.server.server import FFServer

if __name__ == '__main__':
    args = sys.argv
    servername = None
    config = None
    if len(args) > 2:
        servername = servername = args[1]
        config = json.load(open(args[2], 'r'))
    else:
        raise ValueError

    dbconf = config.get('db', {})
    memconf = config.get('memcached', {})
    servsconf = config.get('servers', {})
    masterconf = config.get('master',{})
    serverconf = servsconf.get(servername)
    server = FFServer()
    server.config(serverconf, dbconfig=dbconf, memconfig=memconf, masterconf=masterconf)
    print servername, 'start'
    server.start()
    print servername, 'stop'
```
	    
appmain.py通过firefly的FFServer来启动节点，这里先不管FFServer如何区分各个节点。至此，我们的分布式服务器就算是启动了。

### 4. 节点实现

最后需要我们关心的，就是节点实现了，不用多说，FFServer会根据你传入的节点实现文件，来实现节点的功能。而实际上我们需要做的事情是很少的，因为启动服务器，监听端口，节点间通信，甚至网络消息编解码等等这些功能，FFServer都帮你做了，后面会提到它如何区分和实现这些功能。

而我们要做的，就是通过装饰器响应消息就OK了，并且节点之间的消息转发也很方便：

**netserver实现**

```
#coding:utf8

from firefly.server.globalobject import GlobalObject, netserviceHandle

"""
netservice 默认是 CommandService:
    netservice = services.CommandService("netservice")  [位于server/server.py]
    CommandService 的消息响应函数格式为: HandleName_CommandID(conn, data)
    CommandService 会通过'_'解析出CommandID并注册HandleName_CommandId为其消息响应函数
"""

@netserviceHandle
def netHandle_100(_conn, data):
    print "netHandle_100: ", data
    return "netHandle_100 completed"

@netserviceHandle
def netHandle_200(_conn, data):
    print "netHandle_200: ", data, "forward to gate"
    # 转发到 gateserver.gateHandle1
    # 通过 GlobalObject().remote[父节点名]来得到父节点的远程调用对象
    return GlobalObject().remote['gate'].callRemote('gateHandle1', data)

@netserviceHandle
def netHandle_300(_conn, data):
    print "netHandle_300: ", data, "forward to gate"
    return GlobalObject().remote['gate'].callRemote('gateHandle2', data)
```

**gateserver实现**

```
#coding:utf-8

from firefly.server.globalobject import GlobalObject, rootserviceHandle


@rootserviceHandle
def gateHandle1(data):
    print "gateHandle: ", data
    return "gateHandle Completed"

@rootserviceHandle
def gateHandle2(data):
    print "gateHandle2: ", data, "forward to game1: "
    # 转发到 game1.game1Handle
    # 通过 GlobalObject().root.callChild(节点名，节点函数，参数)远程调用孩子节点
    return GlobalObject().root.callChild("game1", "game1Handle", data)
```

**game1server实现**

```
from firefly.server.globalobject import GlobalObject, remoteserviceHandle

@remoteserviceHandle("gate")
def game1Handle(data):
    print "game1Handle: ", data
    return "game1Handle completed"
```

运行Demo，启动测试客户端，得到结果:

Server端: 

	[firefly.netconnect.protoc.LiberateFactory] Client 0 login in.[127.0.0.1,61752]
	[LiberateProtocol,0,127.0.0.1] call method netHandle_100 on service[single]
	[LiberateProtocol,0,127.0.0.1] netHandle_100:  msgdata
	[LiberateProtocol,0,127.0.0.1] call method netHandle_200 on service[single]
	[LiberateProtocol,0,127.0.0.1] netHandle_200:  msgdata forward to gate
	[BilateralBroker,0,127.0.0.1] call method gateHandle1 on service[single]
	[BilateralBroker,0,127.0.0.1] gateHandle:  msgdata
	[LiberateProtocol,0,127.0.0.1] call method netHandle_300 on service[single]
	[LiberateProtocol,0,127.0.0.1] netHandle_300:  msgdata forward to gate
	[BilateralBroker,0,127.0.0.1] call method gateHandle2 on service[single]
	[BilateralBroker,0,127.0.0.1] gateHandle2:  msgdata forward to game1:
	[Broker,client] call method game1Handle on service[single]
	[Broker,client] game1Handle:  msgdata
	[LiberateProtocol,0,127.0.0.1] Client 0 login out.
	
Client端:

	----------------
	send commandId: 100
	netHandle_100 completed
	----------------
	send commandId: 200
	gateHandle Completed
	----------------
	send commandId: 300
	game1Handle completed

### 6. 总结

看起来，使用firefly确实很简单，通过配置文件即可完成强大的分布式部署，节点之间的通信协议，节点间消息以及网络消息的编解码，甚至重连机制框架都已经帮你完成。你只需通过python装饰器，来实现自己的请求响应逻辑即可。

## 三. 实现原理

简单梳理一下firefly内部替我们完成的事。

### 1.master启动

在我们的app入口文件中，通过master.start()启动服务器，master.start()完成了:

- 创建一个PBRoot 在rootport监听其它节点连接
- 创建一个Flask  在webport 监听管理员命令
- 遍历配置中的servers 通过`python appmain.py 节点名 配置文件`启动各个分布式节点，appmain.py由使用者编写和提供


### 2.FFServer

在appmain.py中，通过FFServer来创建和启动一个节点，firefly FFServer抽象一个服务进程，前面曾提到过，由于所有非master节点都通过FFServer启动，那么FFServer如何区分各节点功能和通讯协议？ 答案很简单，FFServer检查节点各项配置，为各项配置创建对应的组件，其中比较重要的有:

- webport 代表该节点希望提供web服务，FFServer通过Flask启动一个简单的web server
- rootport 代表该节点是一个父节点，创建并启动PBRoot类(master也有一个PBRoot成员)来监听其它节点的连接 
- netport 代表该节点希望接收客户端网络数据，FFServer创建LiberateFactory并监听netport，LiberateFactory中包含对网络数据的解码
- db 若该配置为true，FFServer会根据config中的db配置连接到DB
- mem 若该配置为true，FFServer会根据config中的memcached配置连接到memchache
- remoteport, FFServer为每个父节点创建RemoteObject，并保存remote[name] -> RemoteObject 映射

这样，一个节点可以灵活分配一个或多个职责，并且每份职责通过独立的类来处理内部逻辑和通信协议等。除此之外，FFServer还做了两件事：

- import 节点关联的实现文件，该实现文件通过装饰器可以导入消息回调函数。
- 连接master节点

### 3. 待续


[firefly_on_git]: https://github.com/9miao/firefly
[firefly_9miao]: http://firefly.9miao.com/
[gfirefly_blog_csdn]: http://blog.csdn.net/yueguanghaidao/article/details/38500649
[gfirefly_blog_9miao]: http://www.9miao.com/forum.php?mod=viewthread&tid=49413&highlight=firefly
[flask]: http://docs.jinkan.org/docs/flask/
[firefly_doc]: http://firefly.9miao.com/down/Firefly_wiki.CHM
[demo_github]: https://github.com/wudaijun/firefly-example
