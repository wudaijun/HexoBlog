---
layout: post
title: NGServer 消息的编解码
categories:
- gameserver
tags:
- ngserver
---

消息编解码(或序列化)主要是将消息体由一些标准库容器或自定义的类型，转化成二进制流，方便网络传输。为了减少网络IO，编解码中也可能在存在数据"压缩和解压"，但这种压缩是针对于特定的数据类型，并不是针对于二进制流的。在NGServer的消息编解码中，并不涉及数据压缩。

### 一. 消息编码格式

NGServer的消息分为首部和消息体，首部共四个字节，包括消息长度(包括首部)和消息ID，各占两个字节。消息体为消息编码后的二进制数据。

在消息体中，针对于不同的数据类型而不同编码。对于POD类型，直接进行内存拷贝，对于非POD类型，如标准库容器，则需要自定义编码格式，以下是几种最常见的数据类型编码：

std::string 先写入字符串长度，占两个字节，再写入字符串内容。
std::vector 先写入vector的元素个数(占两个字节)，在对其元素逐个递归编码(如果元素类型为string，则使用string的编码方式)。
std::list	编码方式与vector类似
T arr[N]	对于这种类型，不需要写入元素个数，因为在消息结构体中指出了固定长度N，因此可以通过模板推导得到N。所以递归写入N个元素T即可。对于简单数据类型T，如T为char时，可以通过模板特例化对其优化。

<!--more-->

### 二. ProtocolStream

NGServer的消息编解码依靠两个类：ProtocolReader和ProtocolWriter。这两个类派生于ProtocolStream，ProtocolStream简单维护一个用于编码或解码的线性缓冲区，并记录缓冲区的当前状态，如总大小，当前偏移，等等。一个ProtocolStream的缓冲区即代表一条消息，因此它ProtocolReader/ProtocolWriter总是在缓冲区头四个字节中读出或写入消息长度和消息ID。

ProtocolReader从缓冲区中读出消息，也就是解码，由于缓冲区的数据是二进制的，因此我们需要提供需要读出的数据类型。因此ProtocolReader提供的接口如下：

```
template<typename T>
bool ProtocolReader::AutoDecode(T& t);
```

Decode在缓冲区的当前偏移处，读出数据t，并返回操作结果。而根据T的类型不同，读取方式也不一样，这需要通过模板推导来完成。


### 三. 数据类型

T的类型概括有四种：

- 基本POD类型，如 int, double, char 等  
- 标准库非POD类型，如 std::string, std::vector, std::list 等
- 自定义POD类型，如:
		
```
struct A1
{
	char name[36];
	char pwd[36];
};
```

- 自定义非POD类型，如：

```
struct A2
{
	string name;
	vector<int> data;
};
```

- C数组类型 由于其推导方式不同 因此单独归为一类

关于c++ POD类型和std::is\_pod，std::is\_standard\_layout，std::is\_trivial等函数，可参见下面两篇博客：

1. http://m.oschina.net/blog/156796
2. http://www.cnblogs.com/hancm/p/3665998.html

这里说的POD指的是 std::is\_trivial<T\>::value && std::is\_standard\_layout<T\>::value

### 四. ProtocolReader解码推导流程
推导流程如下：

**1.如果T是C数组类型 (std::is_array<T>::value == true)**，那么下一个推导模型应该为：

```
template<typename T, size_t arraySize>
bool ProtocolReader::DecodeArray(const T (&arr)[arraySize]);
```

如此便能推导出数组的元素类型，以及数组的大小

注：std::is\_array<T\>用于判别一个类型是否为**C风格数组类型**，对于c++的容器vector，std::is\_array<vector<int\>>::value的值为false，因为vector本身也是一个类。

根据我们对C数组的编码方式，下一步我们需要递归通过ProtocolReader::AutoDecode(arr[i])来依次递归对数组元素进行解码。

**2.如果T不是C型数组**，那么T是一个类(或基本类型)。此时通过Decode来对该类进行编解码，Decode读取缓冲区数据，对POD类型和预定义的特例化类型(一般是标准库容器)进行读取并解码：
	
```
template<typename T>
bool ProtocolReader::Decode(T& t);
```

对于POD类型，无论是基本数据类型或者自定义类型，均无需特例化，直接内存拷贝即可。这也是Decode()的默认实现。而对于标准库中的容器，则可以针对性的模板特例化：

```
template<typename T>
bool ProtocolReader::Decode(std::vector<T>& vec);
```
	
而对于最后一种类型，自定义非POD类型，模板自动推导则爱莫能助了，比如对于结构体A2，它的推导流程是: AutoDecode(A2&) -> Decode(A2&) 到了这里，框架无法再推导出A2内部的乾坤了。这就需要A2的定义者提供一个特例化的解码函数AutoDecode(A2&)，为什么不特例化Decode(A2&)呢？因为AutoDecode()是解码的最外层接口，使用者通过自定义的AutoDecode能够获得最大的灵活性。


那么问题来了，由于上面提到的AutoDecode Decode等函数均是ProtocolReader的成员函数，那么AutoDecode(A2&)也应该定义在ProtocolReader中，这样做有两点不足之处：

1. 大量的模板特例化会使ProtocolReader变得异常臃肿难读，并且消息的定义和特例化在不同的文件。容易在定义之后忘记特例化。
2. 编译依赖性增大，添加任意一条非POD消息，都需要重新编译整个ProtocolReader.h以及包含它的所有模块。

而解决方案就是将类中的模板推导转为全局模板推导AutoDecode，然后自定义类的特例化均在全局中，最后再通过Decode调用ProtocolReader接口进行已知类型的推导。

具体流程：

```
/******************* STEP 1 内部自动解码接口 转向全局自动模板推导 **************************/ 
template<typename T>
bool ProtocolReader::Decode(T& t)
{
	// 转向全局推导
	return AutoDecode(*this, t);
}

/****************** STEP 2 通过是否是C数组分发到不同推导接口 ******************************/
// 全局自动推导 这是全局入口 也是自定义的非POD消息的重载入口
template<typename S, typename T>
bool AutoDecode(S& s, T& t)
{
	/* 
	*	Serializer是辅助类 它通过 std::is_array<T>::value 的不同值来转调到不同的模板推导接口
   	*	即 Serializer<true>::DeSerialize(s,t) 和 Serializer<false>::DeSerialize(s,t)
	*/
	return Serializer<std::is_array<T>::value>::DeSerialize(s, t);
}

/***************** STEP 3 Serializer 完成对C数组和非C数组的分发 *************************/
/* Serializer对C数组的分发接口
*	推导出数组元素类型和元素个数
*	通过DecodeArray进行解码
*/
template<typename S, typename T, size_t arraySize>
bool Serializer<true>::DeSerialize(S& s, T (&t)[arraySize])
{
	return DecodeArray(s, t, arraySize);
}

/* Serializer对非C数组的分发接口
*  通过Decode尝试直接解码
*/
template<typename S, typename T>
bool Serializer<false>::DeSerialize(S& s, T& t)
{
	return Decode(s, t);
}

/****************** STEP 4.A 对C数组 T[arraySize] 进行解码 *****************************/
/*
*	DecodeArray 
*	对固定长度的数组进行解码
*/
template<typename S, typename T>
bool DecodeArray(S& s, T* t, size_t arraySize)
{
	uint16_t size = static_cast<uint16_t>(arraySize);
	for(uint16_t i=0; i<size; i++)
	{
		// 递归对元素进行自动解码
		if(!AutoDecode(s, t[i]))
			return false;
	}
	return true;
}

// 对基本类型的C数组特例化 直接内存拷贝
template<typename S>
bool DecodeArray(S& s, int* arr, size_t arraySize){ return s.Read((void*)arr, arraySize*sizeof(int)); }

template<typename S>
bool DecodeArray(S& s, float* arr, size_t arraySize){ return s.Read((void*)arr, arraySize*sizeof(float)); }

template<typename S>
bool DecodeArray(S& s, double* arr, size_t arraySize){ return s.Read((void*)arr, arraySize*sizeof(double)); }

template<typename S>
bool DecodeArray(S& s, int64_t* arr, size_t arraySize){ return s.Read((void*)arr, arraySize*sizeof(int64_t)); }

/*********************** STEP 4.B 对非C数组 进行直接解码 *******************************/
// 默认解码 对于POD类型 直接内存拷贝
template<typename S, typename T>
bool Decode(S& s, T& t)
{
    static_assert(std::is_trivial<T>::value, "is not trivial. need to customize");
    static_assert(std::is_standard_layout<T>::value, "is not standard_layout. need to customize");
    return s.Read((void*)&t, sizeof(t));
}

// 预定义特例化
// 对string的解码 在ProtocolReader中完成 此时类型已确定
template<typename S>
bool Decode(S& s, std::string& t){ return s.Read(t);  }

template<typename S>
bool Decode(S& s, std::wstring& t){ return s.Read(t);	}

// 对标准库容器的解码 由于标准容器元素类型可能仍为自定义类型，因此需要继续递归解码
template<typename S, typename T>
bool Decode(S& s, std::vector<T>& t){ return DecodeArray(s, t); }

template<typename S, typename T>
bool Decode(S& s, std::list<T>& t){ return DecodeArray(s, t); }

// 解码动态长度容器 
template<typename S, typename T>
bool DecodeArray(S& s, T& t)
{
    uint16_t size;
    if (s.Read(size))
    {
        for (uint16_t i = 0; i < size; i++)
        {
            T::value_type v;
			// 逐个对元素进行自动解码
            if (!AutoDecode(s, v))
                return false;
            t.push_back(v);
        }
    }
    return true;
}
```

注意，对数组元素或标准库容器元素解码时，都调用AutoDecode，这是因为如果容器元素是用户自定义的非POD类型，那么可以通过用户重载的AutoDecode进行正确解码。总之，对于未知类型，都应该通过AutoDecode确保用户自定义类型得到正确解码。而Decode只针对于两种类型：POD类型和标准库容器类型，对于前者默认内存拷贝，对于后者通过AutoDecode对元素逐个解码。如果用户没有提供自定义类型的AutoDecode特例化，那么Decode判断其POD类型并执行内存拷贝，如果该类型不是POD类型，那么static_assert将在编译器给出错误："is not trivial. need to customize" 或 "is not standard layout. need to customize"。
而C数组通过在AutoDecode转向分支DecodeArray，DecodeArray完成元素个数解析之后，也通过AutoDecode对元素递归解码。

### 五. 自定义消息类型的特例化

自定义的非POD消息类型A2的特例化如下：

```
bool AutoDecode(ProtocolReader& s, A2& t)
{
	return AutoDecode(s, t.name) && AutoDecode(s, t.data);
}
```

这是全部特例化，它特例化了解码类ProtocolReader和解码类型A2。而自动化模板推导中使用typename S来模板化编解码类，这是为了提高灵活性，让全局自动模板推导框架可以用于多种编解码类。

如果自定义消息类更复杂一些：

```
struct A3
{
	std::string str;
	A2 a2;
};
```

此时A3为复合的自定义非POD类型，如果只为A3提供特例化而忘了给A2特例化：

```
bool AutoDecode(ProtocolReader& s, A3& t)
{
	return AutoDecode(s, t.str) && AutoDecode(s, t.a2);
}
```

那么 `AutoDecode(s, t.str)`能够解码成功，而`AutoDecode(s, t.a2)`，则会失败。因此最好在定义任何一个与客户端交互的非POD结构体时，都需要提供对应编解码规则。而不是在特例化消息的时候才去注意其成员有无非POD类型需要特例化。

### 六. 特例化宏

编码的推导过程和解码大同小异，只不过最终是写入缓冲区而不是读取缓冲区。NGServer还有一个ProtocolSize类，用于获取消息编码之后的大小，推导流程也和编解码流程一致。目前没有什么太大的作用。因此实际上在特例化自定义类的编解码规则时，需要同时提供AutoEncode，AutoDecode，AutoMsgSize三个全局函数。这样在消息比较多时，编写对应编解码规则是一件比较麻烦的事情，并且容易出错。

因此可以对这些编解码特例化提供一个宏，方便定义其编解码规则：

```
#define AUTOCUSTOMMSG1(T, v1) \
    bool Encode(ProtocolWriter& s, const T& t){ \
        return AutoEncode(s, t.v1); } \
    \
    bool Decode(ProtocolReader& s,  T& t){ \
        return AutoDecode(s, t.v1); } \
    \
    uint32_t GetMsgSize(ProtocolSize& s, const T& t ){ \
        return AutoMsgSize(s, t.v1); } 

#define AUTOCUSTOMMSG2(T, v1, v2) \
    bool Encode(ProtocolWriter& s, const T& t){ \
        return AutoEncode(s, t.v1) && AutoEncode(s, t.v2); } \
    \
    bool Decode(ProtocolReader& s,  T& t){ \
        return AutoDecode(s, t.v1) && AutoDecode(s, t.v2); } \
    \
    uint32_t GetMsgSize(ProtocolSize& s, const T& t ){ \
        return AutoMsgSize(s, t.v1) + AutoMsgSize(s, t.v2); } 

#define AUTOCUSTOMMSG3(T, v1, v2, v3) \ 
......
```

如此，对于A2，我们只需在协议cpp文件添加：

	AUTOCUSTOMMSG2(A2, name, data);

即可。

### 七. 回到ProtocolReader
ProtocolReader通过Decode函数转向全局模板推导，最后再回到ProtocolReader进行缓冲读取，由于ProtocolReader缓冲区对应于一条消息，因此解码的缓冲区offset偏移初始化为4(前四个字节为消息头部)。它提供基本类型和string的读取，最后附上主要代码：

```
class ProtocolReader : public ProtocolStream
{
public:
    ProtocolReader(char* buf, uint32_t len) :
        ProtocolStream(buf, len){}

    template<typename T>
    bool Decode(T& t)
    {
        return AutoDecode(*this, t);
    }

    // 读取二进制数据
    bool Read(void* ptr, uint32_t len)
    {
        if (Remain() >= len)
        {
            memcpy(ptr, _buf + _offset, len);
            _offset += len;
            return true;
        }
        return false;
    }

    // 读取基本类型的数据
    inline bool Read(char& v)    { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(int8_t& v)  { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(uint8_t& v) { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(int16_t& v) { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(uint16_t& v){ return Read((void*)(&v), sizeof(v)); }
    inline bool Read(int32_t& v) { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(uint32_t& v){ return Read((void*)(&v), sizeof(v)); }
    inline bool Read(int64_t& v) { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(uint64_t& v){ return Read((void*)(&v), sizeof(v)); }
    inline bool Read(float& v)   { return Read((void*)(&v), sizeof(v)); }
    inline bool Read(double& v)  { return Read((void*)(&v), sizeof(v)); }

    // 对string解码
    inline bool Read(std::string& v)     { return ReadString(v); }
    inline bool Read(std::wstring& v)    { return ReadString(v); }

    // 读取头部和消息ID
    inline uint16_t ReadHead()
    {
        uint16_t* h = (uint16_t*)_buf;
        return *h;
    }
    inline uint16_t ReadMsgId()
    {
        uint16_t* h = (uint16_t*)_buf;
        return *(h + 1);
    }
private:
    bool ReadString(std::string& v)
    {
        uint16_t len;
        if (Read(len))
        {
            v.clear();
            if (len > 0)
            {
                assert(Remain() >= len*sizeof(char));
                v.append((const char*)(_buf + _offset), len);
                _offset += len;
            }
            return true;
        }
        return false;
    }

    bool ReadString(std::wstring& v)
    {
        uint16_t len;
        if (Read(len))
        {
            v.clear();
            if (len > 0)
            {
                assert(Remain() >= len*sizeof(wchar_t));
                v.append((const wchar_t*)(_buf + _offset), len);
                _offset += len*sizeof(wchar_t);
            }
        }
    }
};
```
