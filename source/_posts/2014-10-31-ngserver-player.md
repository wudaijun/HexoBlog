---
layout: post
title: NGServer Session -> Player
categories:
- gameserver
tags:
- ngserver
---


在服务器中，一般都有一个代表客户端或玩家的类，用来处理一些相关逻辑并保存必要数据。也就是NGServer中的Player类，在网络模型中，一般一个Player对应一次会话(Session)，因此在很多服务器模型中，客户端类直接从Session类派生，这样客户端可以直接通过父类Session的接口发送数据，并且通过实现Sessoin的虚函数对数据进行处理。这种模型的好处在于简单，客户端类能够完全控制网络IO，并且对IO事件进行及时地处理。比如连接断开，那么客户端类可以通过实现Session的OnClose()函数完成一些业务逻辑上的处理，比如保存用户数据。而这种编程模型，将客户端和网络会话的耦合性提到了最高：Client is a Session。方便的同时，很大程度上限制了模块的可拓展性，比如客户端的断线重连，由于这种继承关系，导致Session在销毁的同时必然导致Client"逻辑上"的断线，这样玩家重连的时候，数据只能重新加载，建立新的Session和Client。这种情况还会发生在客户端异处登录时，原有客户端被挤下线的同时，逻辑上的数据也丢失了，而新的客户端将重新加载数据。除了断线重连之外，该模型还会造成不必要的编译依赖。因此我们需要将逻辑上的客户端和底层的网络Session解耦。

<!--more-->

一种可行的解耦方式是让Session和Player以"包含"的方式并存。即让Session指针或引用作为Player的一个成员。如此数据的发送仍然比较简单，而数据的接收和处理则需要Session通知Player类，这里有两种方式：

1. 让Session也包含一个Player的引用，如此Session在收到数据或连接关闭时也能调用Player接口进行业务逻辑上的处理。
2. 通过std::bind直接让Player的数据解码接口(Decoder)交给Session，Session的数据接收和关闭均通过Decoder交由Player,如此实现更弱的耦合性。

NGServer采用第二种方式：

```
void PlayerManager::OnConnect(const std::shared_ptr<Socket>& socket)
{
	uint32_t id = ++_connect_id;

	// 创建Player和Session 并将Player和Session关联
	std::shared_ptr<Session> session = std::make_shared<Session>(socket, id);
	std::shared_ptr<Player> player = std::make_shared<Player>(session, LoginService::sDefaultSid);
	std::function<int32_t(const char*, size_t len)> decoder = std::bind(&Player::Decode, player, std::placeholders::_1, std::placeholders::_2);
	player->SetConnId(id);
	session->SetDecoder(decoder);

	AddPlayer(player);

	session->StartRecv();
}
```

PlayerManager管理所有Player的连接，它继承于AsyncTcpListener，一个连接监听器，提供OnConnect接口处理客户端连接事件。因此PlayerManager负责Session和Player的创建和管理，并将Session和Player关联。当有新用户连接时，在OnConnect中，创建Player和Session，并相互关联。Session将收到的数据通过Player::Decode解码，该函数返回解包完成后缓冲区的剩余长度，以便Session调整缓冲区。
	
```
// Session收到新的数据
void Session::ReadComplete(const boost::system::error_code& err, size_t bytes_transferred)
{
    if (err || bytes_transferred == 0)
    {
        DisConnect();
        return;
    }
    _recv_total += bytes_transferred;
    _recv_off += bytes_transferred;

    // 处理数据
    if (ProcessData())
    {
        // 继续接收数据
        AsyncReadSome();
    }
}

// 对缓冲区中的数据解包 返回false则断开连接
bool Session::ProcessData()
{
    assert(_decoder);
    // 将数据交由解码器处理 返回处理之后的缓冲区剩余字节数 返回-1表示服务器主动断线
    int32_t remain = _decoder(_recv_buf,_recv_off);

    // 服务器断开连接
    if (remain < 0)
    {
        ShutDown(ShutDownType::shutdown_receive);
        DisConnect();
        return false;
    }

    // 处理之后的偏移
    if (remain > 0 && remain < kBufferSize)
    {
        size_t remain_off = _recv_off - remain;
        _recv_off = (size_t)remain;
        memcpy(_recv_buf, _recv_buf + remain_off, _recv_off);
    }
    else
    {
        _recv_off = 0;
    }
    return true;
}
```

网络底层部分到此结束，焦点将由Player::Decode转向逻辑层。
