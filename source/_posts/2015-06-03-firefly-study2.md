---
title: Firefly 学习(二)
layout: post
tags:
- firefly
- python
categories: gameserver
---

## 一. GlobalObject
 
每个节点(即一个FFServer)对应一个GlobalObject，存放该节点的节点信息和分布式信息。GlobalObject中包含多种组件，FFServer根据节点配置信息决定为节点创建哪些组件。这样分布式配置更为灵活，一个节点可以单一职责，也可以多种职责。GlobalObject包含的组件主要有：

- netfactory: 前端节点，对应netport字段，监听和管理客户端连接。
- root: 分布式根节点，对应字段rootport
- remote: 分布式子节点，对应字段remoteport
- db: 数据库节点

简单介绍一下netfactory, root, remote 这三个组件，已经远程调用的实现机制。

<!--more-->

### 1. 前端节点netfactory：

前端节点netfactory为LibrateFactory(netconnect/protoc.py)，firefly网络层使用twisted，LibrateFactory即为twisted的协议工厂，同时也是网络层到逻辑层的纽带。LibrateFactory有如下成员：

- connmanager: 
	- 功能: 管理所有Connection，建立ConnID(transport.sessionno)到Conn的映射。
	- 实现: ConnectionManager(netconnection/manager.py)
- dataprotocl: 
	- 功能: 消息编解码器，完成消息的编解码，提供pack/unpack/getHeadlength等接口。
	- 实现: DataPackProtoc(netconnection/datapack.py)
- protocol: 
	- 功能: 负责处理收到的字节数据，解决粘包半包问题等，通过DataPackProtoc拿到消息ID(command)和消息数据(request)，调用`factory.doDataReceived(self, command, requeset)`将消息传给netfactory统一处理。
	- 实现: LibrateProtocol(netconnection/protoc.py)
- service:
	- 功能: netfactory上挂载的Service，也就是从网络层到逻辑层的入口，逻辑层在这个Service通道中注册响应函数，netfactory会在收到消息(`doDataReceived`)时，通过`service.callTarget(commandID, conn, data)`将消息交由service处理。 
	- 实现: 目前的netfactory上挂载的是netservice，netservice默认为CommandService(utils/services.py)
	
值得一提的是，LibrateProtocol在处理收到的字节流时(`dataHandleCoroutine`)，利用yield机制非常简洁高效地完成消息解码工作，使解码函数看起来只是在一个`while True`循环中，无需多次调用，也自然无需保存状态。当外部数据到达时，通过`send(data)`即可将数据送入dataHandleCoroutine，后者yield返回即可拿到data继续工作了。

另外，LibrateProtocol解析完一条消息后，通过调用`factory.doDataReceived`将消息交给netfactory，也就是交给逻辑层，由于LibrateProtocol并不知道逻辑层何时返回，因此`factory.doDataReceived`是一个异步调用，它返回一个Deffer对象，LibrateProtocol注册callback为写回函数`safeToWriteData`，当逻辑层返回处理结果时，即可将数据线程安全地响应给客户端。这个Deffer对象可以是响应函数(如netservice:handle_100)返回的，如果响应函数没有返回Deffer而是直接返回的响应数据response，将由`service.callTarget`创建一个Deffer，并且回调deffer.callback(response)，如果响应函数返回None，那么表示这个请求消息没有响应，`service.callTarget`直接返回None，LibrateProtocol也无需再为其注册`safeToWriteData`函数了。

注意，整个过程都是在单线程中跑的(reactor)，firefly中的每个节点都使用一个reactor，netfactory在FFServer(server/server.py)中传给reactor（如果该节点配置了netport），在FFServer启动时会启动reactor。

### 2. 分布式根节点root

firefly使用twisted透明代理(Perspective Broker, 简称PB, 参见[twisted官方文档](1))，屏蔽了分布式节点之间的通信机制和细节。在FFServer中，firefly为每一个根节点(具备rootport字段)创建一个PBRoot对象，PBRoot代表分布式根节点，它包含两个构件:

- childmanager:
	- 功能: 管理该根节点下面的所有子节点对象(Child对象)，Child主要包含子节点名和子节点的远程调用对象的引用(通过它调用`callRemote(函数名，参数)`即可调用子节点函数，剩下的细节将由twisted透明代理来完成)。
	- 实现: ChildManager(distributed/manager.py)
	
- service:
	- 功能: 和netfactory一样，service用于挂载本节点提供的接口(用于其它节点调用)，firefly所有的节点都抽象出一个service用于管理本节点的接口，除了netfactory的netservice以外，其它节点的service均为Service对象，Service对象根据函数名而不是commandID来调用接口。
	- 实现: Service(utils/services.py) 

子节点在连接到根节点时，由子节点发起一个takeProxy的远程调用，参数为子节点名和其远程调用对象(继承自twisted.spread.pb.Referenceble)，触发PBRoot的remote_takeProxy，该函数记录该子节点和其远程调用对象)。之后根节点PBRoot可通过`callChild(子节点名，函数名，参数)`调用子节点函数。关键代码如下:

```
class PBRoot(pb.Root):
    
    def __init__(self,dnsmanager = ChildsManager()):
        self.service = None
        self.childsmanager = dnsmanager
    
    # 远程调用: 初始化子节点
    def remote_takeProxy(self,name,transport):
        log.msg('node [%s] takeProxy ready'%name)
        child = Child(name,name)
        self.childsmanager.addChild(child)
        child.setTransport(transport)
        self.doChildConnect(name, transport)
        
    # 远程调用: 调用本节点上实现的响应函数    
    def remote_callTarget(self,command,*args,**kw):
        data = self.service.callTarget(command,*args,**kw)
        return data
        
    # 调用子节点方法
    def callChild(self,key,*args,**kw):
        return self.childsmanager.callChild(key,*args,**kw)
        
```

#### 3. 分布式子节点remote

FFServer为每一个子节点(具备remoteport字段)创建N个RemoteObject对象(N为其根节点个数，即remoteport字段的元素个数)，globalobject.remote是一个map，通过remote[根节点名]可以得到连接到指定根节点的RemoteObject。为每一个根节点都创建一个RemoteObject的好处是：同样一个子节点，可以对不同的根节点提供不同的接口。

RemoteObject包含如下构件:

- \_reference:
	- 功能: 这就是前面提到的远程调用对象，继承自`twisted.spread.pb.Referenceble`，因此它支持远程调用，即callRemote方法。前提是要将该对象传给根节点。
	- 实现: ProxyReference(distributed/reference.py)
- \_factory: PBClientFactory实例，用于获取跟节点的远程调用对象(getRootOBject)
- \_name: 节点名字

在`RemoteObject.connect(self, addr)`中，子节点连接到根节点时，需要先远程调用根节点的takeProxy函数，并将_reference和_name传给该函数作为参数，如此根节点的childmanager会记下该子节点及其远程调用对象。关键代码如下:

```
class RemoteObject(object):
    '''远程调用对象'''
    
    def __init__(self,name):
        self._name = name
        self._factory = pb.PBClientFactory()
        self._reference = ProxyReference()
        self._addr = None
        
    def connect(self,addr):
        '''初始化远程调用对象'''
        self._addr = addr
        reactor.connectTCP(addr[0], addr[1], self._factory)
        self.takeProxy()
        
    def reconnect(self):
        '''重新连接'''
        self.connect(self._addr)
        
    def addServiceChannel(self,service):
        '''设置引用对象'''
        self._reference.addService(service)
        
    def takeProxy(self):
        '''向远程服务端发送代理通道对象
        '''
        deferedRemote = self._factory.getRootObject()
        deferedRemote.addCallback(callRemote,'takeProxy',self._name,self._reference)
    
    def callRemote(self,commandId,*args,**kw):
        '''远程调用'''
        deferedRemote = self._factory.getRootObject()
        return deferedRemote.addCallback(callRemote,'callTarget',commandId,*args,**kw)
```

## 二. Service装饰器 

至此，除了db和master节点之外，普通分布式节点已经能够正常通讯并且实现远程调用，由于netfactory, root, remote每个组件都抽离出了service用于挂载响应函数，因此firefly在server/globalobject.py中，实现了几个简单的装饰器：netserviceHandle remoteserviceHandle rootserviceHandle，分别用于挂载netfactory，root，remote的响应函数：

```
def netserviceHandle(target):
    GlobalObject().netfactory.service.mapTarget(target)
        
def rootserviceHandle(target):
    GlobalObject().root.service.mapTarget(target)

class remoteserviceHandle:
	''' remoteserviceHandle装饰器需要一个参数，指出该接口提供给哪一个根节点使用
    def __init__(self,remotename):
        self.remotename = remotename
        
   	def __call__(self,target):
       GlobalObject().remote[self.remotename]._reference._service.mapTarget(target)
```

这样客户端不用再知道关于globalobject的实现细节，用起来就像上一篇博客中的例子一样简单，暴露给用户globalobject组件只有root和remote，用于实现子节点和父节点之间的远程调用。


[1]: http://twistedmatrix.com/documents/current/core/howto/index.html
