---
layout: post
title: NGServer Service框架
categories:
- gameserver
tags:
- ngserver
---

NGServer的核心概念便是服务(Service)，它对逻辑层表现为一个线程，处理各种特定的相关业务。如日志服务(LogService)，数据库服务(DBService)，登录服务(LoginService)。服务之间通过消息进行交互。Service实际上并不是一个独立线程，Service与线程是一种"多对多"的关系。即所有的Service通过ServiceManager来管理，后者维护一个线程池，并将线程池与"服务池"以某种调度方式关联，让线程充分被利用。

<!--more-->

下面由下至上对Service框架和运行机制简单阐述：

##Message定义
NGServer中的消息定义于Message.h中，主要定义了如下几种消息，它们的继承体系如下：

 ![](/assets/image/NGServer_Message_Hierarchy.png "Message继承体系")

Message实现对消息的最高抽象，并不包含任何数据，只提供 GetType纯虚函数接口。用于标识消息类型。

UserMessage是用户发来的消息，内部包含 char* data , size_t len数据成员。

UserMessageT是更具体的用户消息，它是一个模板类，多了一个成员字段 T* user。在本服务器中 T 就是 Player 这样每条消息和包含一个用户指针。这在Service处理以及函数回调的时候非常重要：

```

// 客户端的消息
class UserMessage : public Message
{
public:
    UserMessage(const char* data, size_t len)
    {
        if (data != nullptr)
        {
            _data = new char[len];
            memcpy(_data, data, len);
            _len = len;
        }
        else
        {
            _data = nullptr;
            _len = 0;
        }
    }
    MessageType GetType()  const override
    {
        return MessageType::kUserMessage;
    }

public:
    char* _data;
    size_t _len;
};

// 附加一个成员T的客户端消息
template< typename T >
class UserMessageT : public UserMessage
{
public:
    UserMessageT(const char* data, size_t len, T user) :
        UserMessage(data, len), _user(user){}

    inline T GetClient() const { return _user;  }
public:
    T _user;
};

```

对于其他消息放到后面介绍。纵观Message，通过继承完成对多类消息的分类处理，通过模板和继承完成对消息类的扩展，而模板参数则为消息结构(对于InsideMessageT)或其它附加成员(对UserMessageT)。

##Service 服务

整个NGServer核心概念便是Service,Service完成传统游戏服务器一个线程的任务，但它不完全是线程。目前先把它看作是一个线程。在NGServer中，包含如下Service：

LoginService(登录服务) MapService(地图服务)  DBService(数据库服务) LogService(日志服务)

它们的继承体系如下：

![](/assets/image/NGServer_Service_Hierarchy.png "Service继承体系")

下面简要介绍一下Service每一层实现的一些接口，以及意义：

服务基类Service：

抽象服务的公共接口，如压入消息，处理消息，发送消息等，以及提供一些服务会用到的公共组件，比如定时器，当前时间，处理情况等。
下面是一些重要接口：

![](/assets/image/NGServer_Service_ClassInterface.png "Service类接口")

###Service
Service包含一个消息队列MessageQueue,保存待处理的消息。MessageQueue和ByteBuff类似，使用双缓冲。每个Service都包含一个_sid用于唯一标识自己。以下是一些主要接口：

```

// 消息投递
Service::PushMsg(Message* msg) // 向该Service推送消息，即将消息压入消息队列

// 消息处理
Service::Receive() // 处理消息队列中的消息 取出消息队列中的消息并调用ReceiveMsg(msg)处理
Service::ReceiveMsg(Message* msg) // 处理单条消息 它取出消息类型，还原消息为本身指针，最后分发到ProcessMsg
Service::ProcessMsg( ... ) // 虚函数接口，通过重载处理各类消息

// 消息转发
Service::SendMsg( ... ) // 创建InsideMessage 并将消息通过Service::Send()转发到其它服务
Service::Send( int32_t sid, Message* msg ) // 静态函数 将msg转发到sid对应的Service

```

###GameService
GameService是游戏业务逻辑处理服务的基类，它主要在Service的基础上加入服务器的具体业务，主要扩展了：

- 关联PlayerManager

PlayerManager管理了所有玩家的连接，当GameService::ProcessMsg(UserMessage*)收到客户端断开的消息时，需要通过PlayerManager管理所有连接的玩家。并且在游戏逻辑处理中，有时需要通过用户的连接ID获取用户(此时用户还没有对于服务器的ID，比如还在登录状态)。

- 回调和消息处理机制:

消息的注册于回调机制：提供RegistMsg RegistPlayer RegistInside等注册消息回调函数的方法。这些函数的具体处理和实现到后面再解析，这里只需明白可以通过它实现对消息的注册与回调。
GameService重写了ProcessMsg(InsideMsg* ) 和 ProcessMsg(UserMessage* )，在其中完成对消息回调的处理。这样只要调用Service::Receive()，将发生如下流程：

```

Service::Receive() -> Service::ReceiveMsg(msg) -> GameService::ProcessMsg(msg) -> 消息回调机制 -> 对应回调函数

```

- 关联数据库和日志服务：

添加LogService，DBService 和 HeroManager成员，并且提供设置它们的接口。方便游戏服务更加专心方便地处理业务逻辑。

- 消息发送和转发：

定义SendToDB SendToLog函数，与日志或数据库通信，它们将调用Service::SendMsg将消息推送到日志服务或数据库服务的消息队列。

添加SendToClient 将消息群发给所有管理的用户，将消息体编码成数据流，最后调用Send(data ,len)来发送数据。

Send(char* data, int len)是纯虚函数接口，用于服务具体定义如何将消息发送到所管理的所有用户(群发)。

###DBService LogService
相对于GameService，LogService和DBService则要简单许多，它们负责接收GameService发来的消息，并且将记录写入日志或数据库。因此它们只处理InsideMsg消息。并不处理具体的玩家业务逻辑(UserMessage)，它们与数据库和日志系统打交道。但是由于直接派生于Service，因此对比于GameService，它们也需要消息注册与回调机制。另外，由于Service在运行时是单线程的(后面ServiceManager中解释)，因此它的处理是串行的，所以它可以通过记录_last_recv_service_id 来对源Service进行响应。比如响应数据库操作结果等。这样就实现了纯异步的交互。

###LoginService MapService
得益于GameService的再次封装，具体业务处理服务就真的只需要关心业务逻辑了，让我们以用户登录为例，看看LoginService需要做些什么：

1. 通过RegistPlayer注册用户登录消息响应函数OnPlayerLogin(Player& player, C2S\_Login& msg) 并注册数据库响应消息 OnDBHeroLogin(Player& player, D2S\_Login& msg) 
2. 在OnPlayerLogin中处理用户登录，通过SendToDB SendToLog与数据库交互
3. 在OnDBPlayerLogin中处理数据发来的处理结果

Done

注：消息回调机制会自动将UserMessageT中的client提取出来，并且将对应消息体解包，传入回调函数，因此OnDBHeroLogin可以获取到Player的引用，而UserMessageT中的client初始化是在消息构造时传入的，这中消息编解码中详解。对于其他类型消息处理，比如CycleMessage  LoginService需要自己重写ProcessMsg(CycleMessage*)

##ServiceManager
ServiceManager是整个NGServer的消息集散中心，负责管理所有Service和Message。它将Service和它的_sid对应起来。事实上Service::Send就是通过ServiceManager::Send来转发消息的。

前面提到，Service对于业务逻辑层来说，可以看作一个线程。而它实际上并不是个线程，ServiceManager中提供一个线程池，由它们来将所有的Service"跑起来"，此时的Service相当于一个特殊的"消息队列"，只不过它提供了处理这些消息的接口，也就是Receive():

```

// 取出消息队列中的消息  调用ReceiveMsg处理消息
// 如果处理完之后 队列中还有剩余消息 则返回true 否则返回false
bool Service::Receive()
{
#ifdef _DEBUG
    if (!_recvcheck.TryLock())
    {
        std::cerr << " # service Receive is not runing in single thread ! " << std::endl;
        assert(0);
    }
#endif
    std::vector<Message*>* msgs = _msgqueue.PopAll();
    for(auto msg : *msgs)
	{
        std::unique_ptr<Message> autodel(msg);
        if (!ReceiveMsg(msg))
        {
            autodel.release();
        }
    }
    msgs->clear();

    if (_msgqueue.Size())
        return true;

#ifdef _DEBUG
    _recvcheck.UnLock();
#endif

    _readylock.UnLock();
    return false;
}

```

该接口确保单线程运行(Service内部MessageQueue双缓冲只能单线程处理数据)，取出消息队列中的消息，调用ReceiveMsg进行处理，后者通过Message::GetType()还原消息类型，调用ProcessMsg重载，然后GameService::ProcessMsg中完成对消息的回调.....

然而Receive()仅处理Service消息队列中已有的消息，并没有让Service一直"run"起来，这也是Service比直接用线程更为高效的地方：充分利用线程。只有当Service中有消息时，Service::Receive才会被调用，处理完成之后，线程就"离开"，去跑别的Service。而要做到这点，有两个要点：

1. 保证Service::Receive()同一时刻只被一个线程运行
2. 捕捉Service中MessageQueue的状态变化，在MessageQueue中有消息时，在1的前提下，能够第一时间让Service分配到线程。

为了做到以上两点，ServiceManager中维护一个Service队列ServiceQueue \_ready\_services，该队列线程安全。它保存那些消息队列不为空的Service，也就是"就绪"的Service。\_ready\_services可以看作一个特殊的"消息队列"：它们维护一组消息，并提供这些消息的处理接口。而ServiceManager中的线程池，则在处理这个特殊的"消息队列"(通过调用Service::Receive())。一个Service是否"就绪"，可以用一个锁\_readylock来实现，\_readylock锁定表示该Service消息队列不为空，已经就绪，否则表示该Service处于"空闲"状态。\_readylock可能会在两个地方改变状态：

1. Service::PushMsg()中，可能使消息队列由空变为不空。这可以通过 _readlock.TryLock()来检测并改变该状态。
2. Service::Receive()中，处理完消息队列中的消息后，如果消息队列为空(由于双缓冲机制，在处理读缓冲的数据时，可能有新的数据到达写缓冲)，则释放\_readylock：\_readylock.UnLock();否则_readylock仍然为Lock状态。

接下来就是对Service \_readylock的监测，如果\_readlock为Lock状态，则将其加入到"就绪服务"队列\_ready\_services中。最好的办法当然是在状态可能改变的地方：

```

// 发送消息到指定Service msg的管理权将转交 调用者不需再关心msg的释放问题
bool ServiceManager::Send(int32_t sid, Message* msg)
{
    if (sid < kMaxServiceNum)
    {
        ServicePtr sptr = _serviceMap[sid];
        if (sptr != nullptr)
        {
            if (sptr->PushMsg(msg))
            {
				// 将该服务加入到就绪服务队列 该队列线程安全
                PushService(sptr);
            }
            return true;
        }
    }
    delete msg;
    return false;
}
// ServiceManager线程入口，通过该入口让所有Service Run起来
// 该函数不断从就绪服务队列中取出服务，并执行其Receive入口处理Service中的消息
void ServiceManager::ExecThread()
{
    try
    {
        // 不断执行_ready_services中的Service
        while (_runing)
        {
            ServicePtr sptr = _ready_services.Pop();
            if (sptr != nullptr)
            {
                if (sptr->Receive()) 
                {// 如果执行完成后 还有未处理消息
                    // 重新投递到待执行队列
                    PushService(sptr);
                }
            }
            else
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        }
    }
    catch (std::runtime_error& err)
    {
        std::cerr << "runing thread catch one exception : " << err.what() << std::endl;
    }
}

```

ExecThread函数，就是整个Service，乃至整个框架的发动机，通过让多个thread执行该入口，即可充分利用多线程，均衡处理所有Service中的消息:

```

// 开始运行
// threadNum：指定运行的线程数量
// 如果ServiceManager已经在运行中 则在原有线程基础上再新开threadNum个线程
void ServiceManager::Start(int threadNum)
{
    AutoLocker aLock(&_locker);
    if (_runing == false)
    {   // ServiceManager需要一个TimerThread用于管理所有定时消息
        _runing = true;
        std::thread* t = new std::thread(TimerThread);
        _threads.push_back(t);
        
    }
    
    for (int i = 0; i < threadNum; i++)
    {
        std::thread* t = new std::thread(ExecThread);
        _threads.push_back(t);
    }
}

```

##整个流程

###一. 框架消息处理流程
- ServiceManager::Start(int threadNum) 指定线程池线程数 开始运行所有Service::Receive()
- Service::Receive()从双缓冲消息队列中取出已有消息，逐个调用Service::ReceiveMsg(Message* msg)处理单条消息
- Service::ReceiveMsg(Message* msg)通过Message::GetType()得到每条消息类型，并且通过std::dynamic_cast将msg转换成对应类型nmsg，最后调用ProcessMsg(nmsg)完成分发
- 基类Service::ProcessMsg定义了所有消息的处理接口：

```

// 接口 处理各类消息 返回true代表消息将由框架删除 返回false自行管理该消息
virtual bool ProcessMsg(Message* msg);
virtual bool ProcessMsg(TimerMessage* msg);
virtual bool ProcessMsg(UserMessage* msg);
virtual void ProcessMsg(CycleMessage* msg);
virtual bool ProcessMsg(InsideMessage* msg);

```

如果调度的Service本身重写了对应ProcessMsg,那么将调用重写的ProcessMsg，否则将使用基类Service的ProcessMsg,后者只是忽略消息，不对消息做处理。对于GameService，它重写了ProcessMsg:

```

bool ProcessMsg(UserMessage* msg) override;
bool ProcessMsg(InsideMessage* msg) override;

```
	    
并完成了对消息的解码和响应函数的回调，因此对于LoginService和MapService，它们只需调用Regist注册消息响应函数后，ProcessMsg会将消息解码并回调到对应函数。ProcessMsg中的回调机制将逻辑由框架导出到了业务层。

- 
###二. 服务的消息推送流程

前面说的是消息的处理流程，下面从消息的产生开始讨论消息的生命周期和传递流程。消息一共有四种：UserMessage(T) InsideMessage(T) CycleMessag  TimerMessage，后两种定时器相关的消息由ServiceManager统一管理，因此这里不作阐述。

**UserMessage**是来自客户端的消息，在前面的博客中，讲到了网络层到框架的接口函数：`Player::Decode(const char* data, size_t len)`，网络层将收到的数据交给该函数(当len==0时，表示客户端断开连接)：

```

int32_t Player::Decode(const char* data, size_t len)
{
    // 客户端断线
    if (data == nullptr || len == 0)
    {
        // 通知业务逻辑层 处理下线逻辑
        Message* msg = new UserMessageT<PlayerPtr>(data, len, shared_from_this());
        ServiceManager::Send(_sid, msg);
        return 0;
    }

    // 消息的解包
    const char* buff = data;
    size_t remainLen = len;
    static const uint16_t headLen = ProtocolStream::kHeadLen + ProtocolStream::kMsgIdLen;
    while (remainLen > headLen)
    {
        int32_t msgLen = std::max(headLen, *((uint16_t*)buff));
        if (remainLen < msgLen)
        {
            break;
        }

        // 发送到Service框架层
        Message* msg = new UserMessageT<PlayerPtr>(buff, msgLen, shared_from_this());
        if (!ServiceManager::Send(_sid, msg))
        {
            // 服务器主动断线
            return -1;
        }

        remainLen -= msgLen;
        buff += msgLen;
    }
    return remainLen;
}

```

Player::Decode简单解决粘包问题，当客户端有数据来临(len!=0)或断开连接时(len==0)，均创建UserMessageT并传入Player指针，通过ServiceManager::Send发送到Service框架。这里传入的Player指针很重要，框架的消息回调机制就是通过这个指针来将消息关联到Player的。在PlayerManager::OnConnect()中，有新用户连接时，创建Player的同时为Player指定了一个所属服务，这个服务的sid保存在Player中。Player的所有消息均发往其所属服务。对于刚连接的Player，该服务自然是LoginService。当Player登录成功时，将所属服务特换为MapService，之后所有的业务逻辑都在MapService上面跑。

**InsideMessage**是服务之间的内部消息，它在Service之间转发消息时产生，通过Service::SendMsg创建内部消息，最后通过Service::Send发送。

```

// 发送只包含消息ID的内部消息
bool SendMsg(int32_t sid, int64_t sessionid, int16_t msgid)
{
    InsideMessage* msg = new InsideMessage();
    msg->_dessid = sid;
    msg->_srcsid = GetSid();
    msg->_sessionid = sessionid;
    msg->_msgid = msgid;
    Service::Send(sid, msg);
}

// 发送包含消息数据的内部消息
template < typename MsgT > 
bool SendMsg(int32_t sid, int64_t sessionid, int16_t msgid, MsgT& t)
{
    InsideMessageT* msg = new InsideMessageT<MsgT>();
    msg->_dessid = sid;
    msg->_srcsid = GetSid();
    msg->_sessionid = sessionid;
    msg->_msgid = msgid;
    msg->_data = t;
    Service::Send(sid, msg);
}

```

UserMessage和InsideMessage在创建之后，都会交给ServiceManager::Send，之后便不用关心其生命周期。Message由框架管理。在Service处理这些消息时：

```

// 取出消息队列中的消息  调用ReceiveMsg处理消息
// 如果处理完之后 队列中还有剩余消息 则返回true 否则返回false
bool Service::Receive()
{
	//....

    std::vector<Message*>* msgs = _msgqueue.PopAll();
    for (auto msg : *msgs)
    {
		// 确保消息处理完成后自动删除
        std::unique_ptr<Message> autodel(msg);
        if (!ReceiveMsg(msg))
        {
			// ReceiveMsg返回false 取消自动删除
            autodel.release();
        }
    }
    msgs->clear();

    if (_msgqueue.Size())
        return true;

	// ...
    return false;
}

```

ReceiveMsg处理完消息后，返回true，消息将由框架自动删除，否则消息将由逻辑自行保管。通常不自动删除的消息是帧消息，该消息始终只有一条，处理完成之后，调整下次触发时间，再将其加入到定时器队列。

### 三. 完整的消息请求与响应

####1.用户连接
PlayerManager::OnConnect 创建并关联Player和Session 并且为Player指定所属登录服务的_sid -> Session::StartRecv 开始接收数据

####2.用户请求与响应

推送请求：Session::ReadComplete 数据到达 -> Player::Decode 解包 -> ServiceManager::Send 推送消息到指定服务 -> Service::PushMsg 此时消息已经在服务的消息队列

处理和响应请求：Service::Receive 取出消息 -> Service::ReceiveMsg 还原消息 -> Service::ProcessMsg 重载各类消息的处理方式 GameService和DBService的ProcessMsg中，完成对消息的解码和回调 -> 消息响应函数 -> Player::SendMsg 发送响应 -> Session::SendMsg 完成对消息的编码 -> Session::SendAsync 发送消息数据 

