---
layout: post
title: shared_ptr的引用链
categories:
- c/c++
tags:
- c/c++
- multi-thread

---
总结下几个使用shared_ptr需要注意的问题:

<!--more-->

###一. 相互引用链

```
class C;
class B : public std::enable_shared_from_this<B>
{
public:
    ~B(){ cout << "~B" << endl; }
    void SetPC(std::shared_ptr<C>& pc){ _pc = pc; }    

private:
    std::shared_ptr<C> _pc;
};

class C : public std::enable_shared_from_this<C>
{
public:
    ~C(){ cout << "~C" << endl; }
    void SetPB(std::shared_ptr<B>& pb){ _pb = pb; }
    
private:
    std::shared_ptr<B> _pb;
};

int main()
{
    std::shared_ptr<C> pc = std::make_shared<C>();
    std::shared_ptr<B> pb = std::make_shared<B>();
    pc->SetPB(pb);
    pb->SetPC(pc);
    return 0;
}
```

上面的代码中，B和C均不能正确析构，正确的做法是，在B和C的释放函数，如Close中，将其包含的shared_ptr置空。这样才能解开引用链。

###二. 自引用
还有个比较有意思的例子：

```
class C : public std::enable_shared_from_this < C >
{
public:

    ~C()
    {
        std::cout << "~C" << std::endl;
    }

    int32_t Decode(const char* data, size_t)
    {
        return 0;
    }
    void SetDecoder(std::function<int32_t(const char*, size_t)> decoder)
    {
        _decoder = decoder;
    }


private:
    std::function<int32_t(const char*, size_t)> _decoder;
};

int main()
{
    {
        std::shared_ptr<C> pc = std::make_shared<C>();
        auto decoder = std::bind(&C::Decode, pc, std::placeholders::_1, std::placeholders::_2);
        pc->SetDecoder(decoder);
    }
    // C不能正确析构 因为存在自引用
    return 0;
}
```

上面的C类包含了一个function，该function通过std::bind引用了一个std::shared_ptr<C>，所以\_decoder其实包含了一个对shared_ptr<C>的引用。导致C自引用了自身，不能正确析构。需要在C的Close之类的执行关闭函数中，将\_decoder=nullptr，以解开这种自引用。

###三. 类中传递

下面的例子中有个更为隐蔽的问题：

```
class Session : public std::enable_shared_from_this < Session >
{
public:

    ~Session()
    {
        std::cout << "~C" << std::endl;
    }

    void Start()
    {
        // 进行一些异步调用
        // 如 _socket.async_connect(..., boost::bind(&Session::ConnectCompleted, this), boost::asio::placeholders::error, ...)
    }

    void ConnectCompleted(const boost::system::err_code& err)
    {
		if(err)
			return; 

        // ... 进行处理
        // 如 _socket.async_read(..., boost::bind(&Session::ReadCompleted, this), boost::asio::placeholders::error, ...)
    }

	void Session::ReadComplete(const boost::system::error_code& err, size_t bytes_transferred)
	{
	    if (err || bytes_transferred == 0)
	    {
	        DisConnect();
	        return;
	    }
		// 处理数据 继续读
		// ProcessData();
		// _socket.async_read(...)
	}

private:
    std::function<int32_t(const char*, size_t)> _decoder;
};

int main()
{
    {
        std::shared_ptr<Session> pc = std::make_shared<Session>();
        pc->Start();
    }
    return 0;
}
```

上面Session，在调用Start时，调用了异步函数，并回调自身，如果在回调函数的 boost::bind 中 传入的是shared\_from\_this()，那么并无问题，shared\_ptr将被一直传递下去，在网络处理正常时，Session将正常运行，即使main函数中已经没有它的引用，但是它靠boost::bind"活了下来"，boost::bind会保存传给它的shared\_ptr，在调用函数时传入。当网络遇到错误时，函数直接返回。此时不再有新的bind为其"续命"。Session将被析构。

而真正的问题在于，如果在整个bind链中，直接传递了this指针而不是shared\_from\_this()，那么实际上当函数执行完成后，Session即会析构，包括其内部的资源(如 \_socket)也会被释放。那么当boost底层去执行网络IO时，自然会遇到错误，并且仍然会"正常"回调到对应函数，如ReadCompleted，然后在err中告诉你："由本地系统终止网络连接"(或:"An attempt to abort the evaluation failed. The process is now in an indeterminate state." )。让人误以为是网络问题，很难调试。而事实上此时整个对象都已经被释放掉了。

注：由于C++对象模型实现所致，成员函数和普通函数的主要区别如下：

1. 成员函数带隐式this参数
2. 成员函数具有访问作用域，并且函数内会对非静态成员变量访问做一些转换,如 \_member\_data 转换成 this->\_member\_data;

也就是说，**成员函数并不属于对象，非静态数据成员才属于对象**。

因此如下调用在编译期是合法的：

`((A*)nullptr)->Func();`

而如果成员函数A::Func()没有访问A的非静态成员变量，这段代码甚至能正确运行，如:

```
class Test
{
public:
    void Say()
    {
        std::cout << "Say Test" << std::endl;
    }

    void Set(int data)
    {
        _data = data;
    }

private:
    int _data;
};
int main()
{
	// 运行成功
    ((Test*)nullptr)->Say();
	// 运行会崩掉，尝试访问空指针所指内存(_data)
    ((Test*)nullptr)->Set(1);
    return 0;
}
```

正因为这种特性，有时候在成员函数中纠结半天，也不会注意到这个对象已经"不正常了"，被释放掉了。

###四. shared_ptr 使用总结


1. 尽量不要环引用或自引用，可通过weak_ptr来避免环引用：owner持有child的shared_ptr child持有owner的weak_ptr
2. 如果存在环引用或自引用，记得在释放时解开这个引用链
3. 对于通过智能指针管理的类，在类中通过shared_from_this()而不是this来传递本身
4. 在类释放时，尽量手动置空其所有的shared_ptr成员，包括function
