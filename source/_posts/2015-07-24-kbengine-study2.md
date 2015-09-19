---
title: kbengine 源码导读(二) 加载流程
layout: post
categories: gameserver
tags: kbengine
---

## 一. 登录流程

**注册**

	Unity3d:CreateAccount
	Loginapp:reqCreateAccount 
	-> dbmgr:reqCreateAccount 
	-> Loginapp:onReqCreateAccountResult 
	-> Client:onReqCreateAccountResult

<!--more-->

**登录 Step1**

	Unity3d:login
	Loginapp:login 
	-> dbmgr:onAccountLogin 	//检查登录 将登录结果返回给Loginapp
	-> Loginapp:onLoginAccountQueryResultFromDbmgr //转发给BaseappMgr分配Baseapp
	-> BaseappMgr:registerPendingAccountToBaseapp //将客户端分配到当前负载最低的Baseapp上 并返回该Baseapp的Ip Port
	-> onLoginAccountQueryBaseappAddrFromBaseappmgr //将Baseapp的Ip Port转发给客户端
	-> Client:onLoginSuccessfully

**登录 Step2**

	Unity3d:loginGateway  	//尝试在指定Baseapp上登录
	Baseapp:loginGateway	//检查登录 处理重复登录 向数据库查询账号详细信息
	dbmgr:queryAccount		//查询账号详细信息 返回给Baseapp
	Baseapp:onQueryAccountCBFromDbmgr	//创建账号的Proxy并传入客户端的mailbox(用于和客户端交互)，Demo中的Account.py即继承于KBEngine.Proxy。

**获角 选角 创角**

Unity3d的`reqAvatarList` `selectAvatarGame` `reqCreateAvatar` 都将直接转到Account.py中对应的相应函数上，KBEngine.Proxy已经封装了和客户端通讯的方法(通过Mailbox)。


## 二. 地图创建

1. Baseapp启动，会回调到Python脚本层的onBaseAppReady(base/kbengine.py)
2. 第一个Baseapp启动时，在本Baseapp上创建世界管理器spaces Entity(Baseapp:createBaseLocally) 定义于spaces.py
3. spaces读取配置文件data/d_spaces.py，为每一个Space Entity创建一个SpaceAlloc，通过定时器分批次调用SpaceAlloc.init创建Space Entity(一秒回调创建一个)
4. SpaceAlloc.init通过KBEngine.CreateSpaceAnyWhere()完成
5. Baseapp:CreateSpaceAnyWhere()会转发给BaseappMgr，最终落在当前负载最轻的Baseapp上，通过CreateEntity完成Space Entity创建
6. 创建完成后，回调到发起方Baseapp:CreateSpaceAnywhereCallback() 最终回调到Python层SpaceAlloc.py:onSpaceCreatedCB()
注意，上面提到的Space Entity并不是真正的Space，而是Baseapp用于操作Space的一个句柄，真正的Sapce需要挂在Cellapp上，在srcipts/base/Space.py中完成真正的Space创建：
7. Space.py:\__init__()中，通过Baseapp:CreateInNewSpace()创建真正的Space，之后读取该Space上需创建的所有 Entity(配置在scripts/data/d_spaces_spawns中)，等待其上面的Entity被创建
8. Baseapp:CreateInNewSpace()将请求转发给CellappMgr，后者会将请求分发到当前负载最轻的Cellapp上，Cellapp:onCreateInNewSpaceFromBaseapp()完成Space创建，回调Baseapp:OnEntityGetCell()
9. 注意，此时cell/Space.py:\__init__()被调用，开始加载真正的几何数据和寻路相关，回调到Baseapp:OnEntityGetCell()
10. Baseapp:OnEntityGetCell()判断该Entity是否是客户端，如果是则需要通知客户端(Baseapp::onClientEntityEnterWorld)，之后回调脚本Space.py:OnGetCell()

至此，地图创建完成。

## 三. 生成NPC/Monster

对于NPC/Monster，是先创建其出生点，再由出生点创建真正的NPC/Monster

1. 接上面Space的Cell和Base部分均创建完成后，base/Space.py:OnGetCell()中，注册一个定时器，开始创建该Space上面的所有NPC/Monster的SpawnPoint，每0.1秒创建一个
2. base/SpawnPoint.py中，创建其Cell部分
3. cell/SpawnPoint.py中，通过createEntity创建其对应的真正的NPC/Monster


## 四. Entity (实体)

Entity是服务器与客户端交互的一切实体的总称，包括：账号，角色，NCP，Monster，公会，等等。Entity通过 <Entity>.def 来定义自己的属性和方法，指定属性和方法的作用域，即(Base, Cell, Client)的访问权限。因此C/S之间的消息协议实际上只是针对于Entity的远程调用。所以KBEngine本身没有消息协议一说，所有业务逻辑都围绕着Entity展开，通过<Entity>.def来维护。

参见：

http://kbengine.org/cn/docs/programming/entitydef.html
http://kbengine.org/cn/docs/configuration/entities.html




