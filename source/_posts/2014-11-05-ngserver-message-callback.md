---
layout: post
title: NGServer 消息的注册与回调
categories:
- GameServer
tags:
- NGServer
---

在前面Service框架的介绍中，提到在GameService的`ProcessMsg(UserMessage*)`和`ProcessMsg(InsideMessage*)`中，都完成了消息的回调处理。消息响应函数的注册是在服务初始化(Init())中完成的。需要注册和回调的消息有InsideMessage和UserMessage，对于InsideMessage，响应函数只有一种形式：即为响应服务的成员函数。而对于UserMessage，由于UserMessage有Player指针，响应函数则会有多种形式：

<!--more-->

1. 作为注册Service的成员函数，并且将Player作为第一个参数。这常在登录和注册流程中发生，如 `LoginService::OnPlayerLogin(Player& player, const C2S_Login& msg)`。 登录和注册的验证流程在LoginService中统一处理。
2. 作为Player的成员函数，当Player登录成功后，此时客户端与服务器进行的交互都是基于业务逻辑的，因此应在Player的成员函数处理。如 `Player::OnEnterGate(const C2S_EnterGate& msg)`
3. 其它响应函数，如全局函数。

事实上，基于UserMessage中的Player指针，我们可以实现上面的调用方式，现在就需要通过一种或多种的注册回调机制，来实现对各种响应函数形式的注册和回调。

##使用消息注册与回调

消息的注册通过指定消息ID和消息响应函数来完成，注册函数主要有如下形式：

```
bool MapService::Init()
{
	// 注册用户消息 响应函数原型： void MapService::OnWorldChat(Player* player, C2S_WorldChat& msg)
	RegistPlayer(MsgId::kC2S_WorldChat, &MapService::OnWorldChat, this);
	// 注册用户消息 响应函数原型： void Player::OnEnterGate(const C2S_EnterGate& msg)
	RegistPlayer(yuedong::protocol::kC2S_EnterGate, &Player::OnEnterGate);
	// 注册用户消息 响应函数原型：void Test(Player* player, Test);
	
	// 注册响应服务之间的内部消息
	RegistInside(SSMsgId::kSS_PlayerLogin, &MapService::OnPlayerLogin, this);
	return true;
}
```

上面注册了三种主要消息，通过RegistPlayer注册玩家消息，通过RegistInside注册内部消息。RegistPlayer通过模板推导和函数重载完成了三种响应函数原型的注册。下面以RegistPlayer为例，讲述消息注册机的内部机制：

```
class GameService : public Service
{
// ....
// 消息注册
public:
	// 注册第一个参数为Player*的回调函数 
	// 当 F 模板推导为全局函数时，第一个参数为Player*  
	//	如 void Test(Player*, C2S_Test&)
	// 当 F 模板推导为Player成员函数时，将解析出来的Player*直接作为this指针调用该成员函数
	//  如 Player::OnEnterGate(C2S_EnterGate&)
	template<typename MsgEnum, typename F>
	void RegistPlayer(MsgEnum msgid, F f)
	{
	    _calltype[(uint16_t)msgid] = cbPlayerAgent;
	    _player_delegate.Regist((uint16_t)msgid, f);
	}
	
	// 注册第一个参数为Player*的MapService成员函数 
	//	如MapService::OnWorldChat(Player*, C2S_WorldChat&)
	template<typename MsgEnum, typename F, typename ObjT>
	void RegistPlayer(MsgEnum msgid, F f, ObjT* obj)
	{
	    _calltype[(uint16_t)msgid] = cbPlayerAgent;
	    _player_delegate.Regist((uint16_t)msgid, f, obj);
	}
//....
private:
	DelegateManager<std::pair<Player*, ProtocolReader&>> _player_delegate;
};
```

在`bool MapService::ProcessMsg(UserMessage* msg)`中回调响应函数：

```
bool MapService::ProcessMsg(UserMessage* msg)
{
    UserMessageT<PlayerPtr>* msgT = dynamic_cast<UserMessageT<PlayerPtr>*>(msg);
    if (msgT == nullptr)
        return true;

    PlayerPtr player = msgT->GetClient();
    int32_t sid = player->GetSid();

    // 不是发送给当前服务的消息 转发
    if (sid != _sid)
    {
        return ServiceManager::Send(sid, msg);
    }

    // 客户端断开连接
    if (msg->_len == 0)
    {
        player->Offline();
        _session_manager->RemoveSession(player->GetConnId());
        return true;
    }


    ProtocolReader reader(msg->_data, msg->_len);
    uint16_t msgid = reader.ReadMsgId();
    CallBackType cbType = _calltype[msgid];
    switch (cbType)
    {
    case cbPlayerDelegate:
        auto arg = std::pair<Player*, ProtocolReader&>(player.get(), reader);
        _player_delegate.Call(msgid, arg);
        break;

	//case ...
	//	break;
	
	default:
		break; 
    }

    return true;
}
```

在`bool MapService::ProcessMsg(UserMessage* msg)`中，取出UserMessage中的PlayerPtr指针，将其与ProtocolReader一起打包成std::pair，而事实上，这个pair才是最终的解码器，在这一点上，也可以专门写一个UserMessageReader类来读取UserMessage的Player指针，以及消息数据。后面也会向这方面改进。可以注意到这个pair也是 _player_delegate的DelegateManager模板参数,下面介绍DelegateManager.

####DelegateManager

DelegateManager是一个模板类，它第一个模板参数Decoder，是解码器

```
// AutoCall.h
template<typename Decoder, size_t Capacity = 65535>
class DelegateManager
{

    typedef typename IDelegate<Decoder>* DelegatePtr;
    DelegatePtr _caller[Capacity];

public:
    DelegateManager()
    {
        memset(_caller, 0, sizeof(_caller));
    }

    ~DelegateManager()
    {
        for (size_t i = 0; i < Capacity; i++)
        {
            if (_caller[i] != nullptr)
            {
                delete _caller[i];
                _caller[i] = nullptr;
            }
        }
    }

    bool Call(uint16_t id, Decoder& s)
    {
        if (_caller[id] != nullptr)
            return _caller[id]->Call(s);
        else
            return false;
    }

	// 内部注册接口
    DelegatePtr Regist(uint16_t id, DelegatePtr dp)
    {
        if (_caller[id] != nullptr)
            delete _caller[id];

        _caller[id] = dp;
        return dp;
    }
// 外部具体注册方式 省略了函数原型不完全匹配时的注册接口 此时参数类型需要显式给出 在调用时隐含转换
public:
	// 完全匹配 全局函数
    template<typename R>
    DelegatePtr Regist(uint16_t id, R(*f)())
    {
        return Regist(id, CreateDelegate0<Decoder>(f));;
    }

    template<typename R, typename T1>
    DelegatePtr Regist(uint16_t id, R(*f)(T1))
    {
        return Regist(id, CreateDelegate1<Decoder, T1>(f));
    }

    template<typename R, typename T1, typename T2>
    DelegatePtr Regist(uint16_t id, R(*f)(T1, T2))
    {
        return Regist(id, CreateDelegate2<Decoder, T1, T2>(f));
    }

    // 完全匹配 成员函数
    template<typename R, typename ObjT>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)(), ObjT* obj)
    {
        std::function<R()> bindf = std::bind(f, obj);
        return Regist(id, CreateDelegate0<Decoder>(bindf));
    }

    template<typename R, typename ObjT, typename T1>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)(T1), ObjT* obj)
    {
        std::function<R(T1)> bindf = std::bind(f, obj, std::placeholders::_1);
        return Regist(id, CreateDelegate1<Decoder, T1>(bindf));
    }

    template<typename R, typename ObjT, typename T1, typename T2>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)(T1, T2), ObjT* obj)
    {
        std::function<R(T1, T2)> bindf = std::bind(f, obj, std::placeholders::_1, std::placeholders::_2);
        return Regist(id, CreateDelegate2<Decoder, T1, T2>(bindf));
    }

    // 完全匹配  成员函数  该成员函数的this指针从Decoder中读取
    // 这里必须要使用bind函数 预留出this指针的位置
    template<typename R, typename ObjT>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)())
    {
        auto bindf = std::bind(f, placeholders::_1);
        return Regist(id, CreateDelegate1<Decoder, ObjT*>(bindf));
    }

    template<typename R, typename ObjT, typename T1>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)(T1))
    {
        auto bindf = std::bind(f, placeholders::_1, placeholders::_2);
        return Regist(id, CreateDelegate2<Decoder, ObjT*, T1>(bindf));
    }

    template<typename R, typename ObjT, typename T1, typename T2>
    DelegatePtr Regist(uint16_t id, R(ObjT::*f)(T1, T2))
    {
        auto bindf = std::bind(f, placeholders::_1, placeholders::_2, placeholders::_3);
        return Regist(id, CreateDelegate3<Decoder, ObjT*, T1, T2>(bindf));
    }
};
```

DelegateManager管理所有消息ID到消息响应的映射，并提供注册和回调结果。
Regist的多种重载识别出需要创建的Delegate对象，由DelegateManager统一管理。


注册主要通过Regist函数的重载和模板推导来进行三种注册方式(实际上不止三种)：全局函数，Service成员函数，Player成员函数。

DelegateManager中，通过Delegate类来代理响应函数。CreateDelegate用于创建响应函数对应的Delegate：

```
// AutoCall.h
template<typename Decoder, typename FuncT>
IDelegate<Decoder>* CreateDelegate0(FuncT f)
{
    return new Delegate0<Decoder, FuncT>(f);
}

template<typename Decoder, typename T1, typename FuncT>
IDelegate<Decoder>* CreateDelegate1(FuncT f)
{
    return new Delegate1<Decoder, T1, FuncT>(f);
}

template<typename Decoder, typename T1, typename T2, typename FuncT>
IDelegate<Decoder>* CreateDelegate2(FuncT f)
{
    return new Delegate2<Decoder, T1, T2, FuncT>(f);
}
```

最终的Delegate，需要保存回调函数，并提供调用接口Call:

```
template <typename Decoder>
class IDelegate
{
public:
    virtual ~IDelegate(){}
    virtual bool Call(Decoder& s) = 0;
};

/***********************************************************/
/*    默认的Delegate，所有参数都通过Decode全局函数解码得出    */
/***********************************************************/

// 0个参数的响应函数
template<typename Decoder, typename FuncT>
class Delegate0 : public IDelegate < Decoder >
{
    FuncT _func;

public:
    Delegate0(FuncT func) :
        _func(func){}

    bool Call(Decoder& s) override
    {
        _func();
        return true;
    }
};

// 1个参数的响应函数
template<typename Decoder, typename T1, typename FuncT>
class Delegate1 : public IDelegate < Decoder >
{
    FuncT _func;

public:
    Delegate1(FuncT func) :
        _func(func){}

    bool Call(Decoder& s) override
    {
        std::remove_const < std::remove_reference<T1>::type >::type t1;

        if (!Decode(s, t1))
            return false;

        _func(t1);
        return true;
    }
};

// 2个参数
template<typename Decoder, typename T1, typename T2, typename FuncT>
class Delegate2 : public IDelegate < Decoder >
{
    FuncT _func;

public:
    Delegate2(FuncT func) :
        _func(func){}

    bool Call(Decoder& s) override
    {
        std::remove_const< std::remove_reference<T1>::type >::type t1;
        std::remove_const< std::remove_reference<T2>::type >::type t2;

        if (!Decode(s, t1))
            return false;
        if (!Decode(s, t2))
            return false;

        _func(t1, t2);
        return true;
    }
};
```

Delegate保存回调函数，并且提供调用接口，调用接口Call仅有一个参数，就是解码器，也是DelegateManager的模板参数。对于我们的\_player\_delegate来说，就是pair<Player*, ProtocolReader&>。而上面的Delegate类是默认实现，通过Decode全局函数完成对Decoder的解码，在前面消息编解码中提到过，ProtocolReader实现了这样一个接口。而对于我们的pair，需要特例化，方式一是特例化Decode，方式二是特例化Delegate类。我们采用方法二：

```
// AutoCallSpecial.h
/*******************************************************************************************************/
/*   特例化Decoder: std::pair<T1, ProtocolReader&> T1是响应函数的第一个参数 其他参数从ProtocolReader中读取  */
/*******************************************************************************************************/
// 带一个参数 T1
template<typename T1, typename FuncT>
class Delegate1<std::pair<T1, ProtocolReader&>, T1, FuncT> : public IDelegate < std::pair<T1, ProtocolReader&> >
{
    FuncT _func;

public:
    Delegate1(FuncT f) :
        _func(f){}

    bool Call(std::pair<T1, ProtocolReader&>& s) override
    {
        _func(s.first);
        return true;
    }
};

// 带两个参数  第一个参数为T1 第二个参数从ProtocolReader中读取
template < typename T1, typename T2, typename FuncT > 
class Delegate2<std::pair<T1, ProtocolReader&>, T1, T2, FuncT> : public IDelegate < std::pair<T1, ProtocolReader&> > 
{
    FuncT _func;

public:
    Delegate2(FuncT f) :
        _func(f){}

    bool Call(std::pair<T1, ProtocolReader&>& s) override
    {
        std::remove_const< std::remove_reference<T2>::type >::type t2;

        if (!Decode(s.second, t2))
            return false;

        _func(s.first, t2);
        return true;
    }
};
```

如果通过一个UserMessageReader来对UserMessage特殊解码的话，便可以直接特例化Decode，更加简便一些。

AutoCallSpecial.h中还对InsideMessage完成了特例化，而消息的回调方式也不仅限于cbPlayerDelegate一种。添加一种自定义的回调方式也比较简单：

1. 先自定义一个解码器，将所需参数包含进去，解码器可以是个自定义类，也可以是个容器或其它，将其作为DelegateManager的模板参数
2. 在CallBackType中添加该回调类型
3. 在对应ProcessMsg中，组建自己的解码器，调用DelegateManager::Call函数
4. DelegateManager会最终调到 Delegate::Call 因此如果有必要  需要对Delegate进行特例化，保证使用你的解码器能正确解码 或者直接使用默认Delegate类中的Decode方式，特例化全局Decode函数。

