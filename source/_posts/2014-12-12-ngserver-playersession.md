---
layout: post
title: NGServer 加入PlayerSession
categories:
- gameserver
tags:
- NGServer
---

## PlayerSession类

在之前的网络底层设计中，Player和Session之间通过组合实现弱关联，但仍然有个诟病：Player类和Session类在网络连接到来时一并创建了。这样后面在做断线重连的时候，会有两个Player。而事实上LoginService只管登录认证，登录认证的时候并不需要创建Player类，因此可以延迟Player的创建，将其放在MapService中。而这之前LoginService的登录认证也需要用户的一些基本信息。基于这些，实现了PlayerSession类：

<!--more-->

```
class PlayerSession : public Session
{
public:
    PlayerSession(const std::shared_ptr<Socket> socket, int32_t conn_id);
    ~PlayerSession();

	// .....
	
    // 网络数据解码
    int32_t Decode(const char* data, int32_t len);

    // 发送消息
    template<typename MsgT>
    bool SendMsg(MsgId msgid, MsgT& t);

	// ....
	
private:
    int32_t _sid = 0;       // 所属服务ID
    std::shared_ptr<Player> _playerToken; // 玩家指针
    SessionState _state = kSessionState_None;   // 会话状态
    std::string _owner;       // 登录用户名
};
```

解码将在PlayerSession而不是Player中完成，在登录完成之前，LoginService通过PlayerSession与玩家交互，在登录验证完成之后，LoginService将玩家登录信息和PlayerSession一并发送到MapService，MapService完成对Player的创建，并于PlayerSession建立关联：

```
void MapService::OnPlayerLogin(SS_PlayerLogin& msg)
{
    PlayerSessionPtr session = msg.session;
    if (session == nullptr)
        return;

    int64_t playerid = msg.login_info.playerid;
    // 创建 Player 并与PlayerSession关联
    PlayerPtr player = std::make_shared<Player>(playerid, session);
    player->SetMapService(dynamic_pointer_cast<MapService>(shared_from_this()));
    session->SetPlayerToken(player);
    session->SetSid(GetSid()); 
    
    AddPlayer(player);
    
    // 向数据库加载玩家信息
    // ...
    S2D_LoadPlayer loadmsg;
    loadmsg.playerid = playerid;
    SendToDB(playerid, kS2D_LoadPlayer, loadmsg);
}
```

之后客户端业务逻辑上与MapService交互，在GameService::Process(UserMessage*)解码时提取出_playerToken，即可通过Player类完成业务逻辑。

加入了PlayerSession之后，消息注册回调机制也更复杂了一些，为了方便管理，这些注册和回调均放在GameService中。


