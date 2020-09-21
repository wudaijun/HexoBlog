---
layout: post
title: C++ 构造语义
tags: c/c++
categories: c/c++

---

本文是《深度探索C++对象模型》的读书笔记，主要根据自己的理解整理一下C++对象构造的实现细节以及其在实际编程中所带来的影响。

## 一. 构造函数

C++95标准对构造函数如下描述：

>对于 class X，如果没有任何user-declared constructor，那么会有一个default constructor被**隐式声明**出来.....一个被隐式声明出来的 default constructor 将是一个**trivial(浅薄无能的，没啥用的) constructor** ......

上面的话摘自《深度探索C++对象模型》P40，由于其省略了其中c++标准的部分内容，因此很容易造成误解：

编译器**隐式生成**的构造函数都是 trivial constructor .....

事实上，描述中提到 default constructor 被隐式声明出来（满足语法需要），而该构造函数是否被编译器合成（实现或定义），取决于**编译器是否需要在构造函数中做些额外工作**，一个没有被合成的 default constructor 被视为 trivial constructor(这也是c++标准原话的意思)，而当编译器在需要时合成了构造函数，那么该类构造函数将被视为 nontrivial。

另外，一个定义了 user-decalred constructor(用户定义的任何构造函数) 的类被视为具有 nontrivial constructor。

下面将着重讨论编译器隐式声明的构造函数在哪种情况下需要被合成(nontrivial)，哪种情况下无需被合成(trivial)：

<!--more>

考虑下面这个类：

```	
class A
{
private:
	int _ivalue;
	float _fvalue;
};
```

对于类A来说，编译器将为其隐式声明的默认构造函数被视为trivial。因为编译器无需在其声明的构造函数中，对A类对象进行任何额外处理。注意，编译器生成的默认构造函数不会对 _ivalue 和 _fvalue 进行初始化。因此在这种情况下，编译器隐式生成的默认构造函数可有可无，视之为"trivial"。

而对于如下四种情况，编译器隐式生成的默认构造函数(以下简称"隐式构造函数")是 nontrivial default constructor ：

#### a. 类中有 "带 nontrivial default constructor" 的对象成员

注意，这里的notrivial default constructor包括**用户定义的任何构造函数**或者**编译器生成的notrivial构造函数**。这实际上是一个递归定义，当类X中有具备notrivial default constructor的对象成员Y \_y时，X的隐式构造函数需要调用Y的默认构造函数完成对成员\_y的构造。如：
	
```	
class B
{
private:
	A _a;
};

class C
{
private:
	std::string _str;
};

```

我们说类B中的对象成员 A \_a "不带default constructor"，因为它只有一个隐式生成的 trivial default constructor。因此B的隐式构造函数中，无需操心对成员_a的构造。因而实际上B的隐式构造函数也被视为trivial(无关紧要)。而对于类C，由于其对象成员类型string具备用户(库作者)声明的默认构造函数，因此string的构造函数是nontrivial，所以编译器在为C合成的默认构造函数中，需要调用string的默认构造函数来为\_str初始化，此时C的构造函数便不再是"无关紧要"的，被视为 nontrivial。

#### b. 类继承于 "带 nontrivial default constructor" 的基类

情形b和情形a类似：当类具有 "带 nontrivial default constructor"的基类时，编译器隐式生成的默认构造函数需要调用基类的默认构造函数确保基类的正确初始化。此时该类构造函数视为nontrivial。

#### c. 类中有虚函数(或继承体系中有虚函数)

在这种情况下，编译器生成的隐式构造函数需要完成对虚函数表vtable的构造，并且将vtable的指针安插到对象中(通常是头四个字节)。此时的隐式构造函数自然是必不可少(nontrivial)。

#### d. 类的继承体系中具有虚基类

和情形c一样，编译器需要在合成的构造函数中，对虚基类进行处理(处理方式和虚函数类似，通过一个指针来指向虚基类，以保证虚基类在其继承体系中，只有一份内容)，这样才能保证程序能在运行中正确存取虚基类数据。被视为nontrivial。

#### 总结

编译器隐式声明的默认构造函数，是 trivial or nontrivial，取决于编译器是否需要在构造函数中做一些额外的处理，主要包括对象成员和基类的初始化(取决于对象成员或基类有无nontrivial default constructor)，以及对虚函数和虚基类的处理(取决于在其继承体系中是否有虚函数或虚基类)。这些工作使隐式构造函数不再是可有可无。

不存在以上四种情况并且没有用户定义的任何构造函数时，隐式构造函数也被称作 implicit trivial default constructors。这类构造函数实际上并不会被编译器合成出来。这也是对 trivial 和 nontrivial 的直观理解。

而实际上，即使你定义了自己的构造函数，如果类中满足以上四种情形之一，编译器也会将你的构造函数展开，将必要的处理(如vtable的构造)植入到你的构造函数中(一般是你的构造代码之前)。不过仍然请注意，一旦你定义了自己的构造函数，哪怕该函数什么也不做，该类也将被视为具备 nontrivial constrcutor。

## 二. 复制构造函数

就像 default constructor 一样，C++ Standard 上说，如果 class 没有声明一个 copy constructor，就会有隐式的声明(implicitly declared)或隐式的定义(implicitly defined)出现，和以前一样，C++ Standard 把 copy constructor 区分为 trivial 和 nontrivial 两种，只有 nontrivial 的实例才会被合成于程序之中。决定一个 copy constructor 是否为 trivial 的标准在于 class 是否展现出所谓的 "bitwise copy semantics(按位拷贝语义)"。

"按位拷贝语义"是指该类对象之间的拷贝构造，可以通过简单的"位拷贝"(memcpy)来完成，并且与该对象拷贝的原本语义一致。例如 上面的类A，它便具有按位拷贝语义。因此它的拷贝构造函数也是 trivial copy constructor。这样的拷贝构造函数不会被编译器合成到程序中。直接将其作为内存块拷贝即可(类似于 int double 之类的基本类型)。

那么类何时不具有按位拷贝语义？ 和构造函数一样，当编译器声明的拷贝构造函数需要替程序做一些事情时，视为nontrivial。具有也有如下四种情况：

1. 类中有 "带 nontrivial copy constructor" 的对象成员
2. 类继承于 "带 nontrivial copy constructor" 的基类
3. 类中有虚函数(或继承体系中有虚函数)
4. 类的继承体系中具有虚基类

对于1，2，复制构造函数需要通过调用基类或对象成员的 nontrivial 拷贝构造函数来保证它们的正确拷贝。

而对于3，考虑如下情形：

```

// class Derive public派生于 class Base
Derive d;
Derive d2 = d;
Base b = d; // 发生切割(sliced)行为

```

对于d2对象，编译器使用位拷贝并无问题(假设Derive并不存在1，2，4所述情况)，因为d和d2的虚函数表均来自于Derive。而对于`Base b = d;`编译器需要保证对象b的虚函数表为Base的虚函数表，而不是从对象d直接位拷贝过来的Derive类的虚函数表。否则在通过b调用Derive特有而基类Base没有的虚函数时，会发生崩溃(因为Base的虚函数表不含该函数)。因此对于有虚函数的类，编译器必须对该类的虚函数表"负责"，保证其正确初始化。

对于4，和情况3一样，编译器需要确保被构造的对象指向虚基类的指针(virtual base class point)得到正确初始化。

当类不满足以上四种情况时，我们说它的copy constructor为trivial。编译器不会合成trivial copy constrcutor到程序中。在拷贝对象时，执行简单的内存块拷贝。

## 三. trivial的一些扩展

在std中，提供了对某个类各个trivial属性的判别。如：
	
```

#include <iostream>

class A
{
public:
    A()
    {
    }

private:
    int _i;
    char* _str;
};

class B : public A
{

private:
    double _d;
};



int main()
{
	// 0 A 有 user-declared constructor
    std::cout << std::is_trivially_constructible<A>::value << std::endl; 
	// 1 A 没有 user-declared copy constructor 并且不含abcd情形       
    std::cout << std::is_trivially_copy_constructible<A>::value << std::endl;   

	// 0 B 需要调用A::A() 完成对基类的构造
    std::cout << std::is_trivially_constructible<B>::value << std::endl;
	// 1 B 没有 user-declared copy constructor 并且基类 A 没有 nontrivial copy constructor        
    std::cout << std::is_trivially_copy_constructible<B>::value << std::endl;   
    
    std::cout << std::is_trivial<A>::value << std::endl;	// 0
    std::cout << std::is_trivial<B>::value << std::endl;    // 0

    return 0;
}

```
	
std::is_***是c++11引入的关于类型特性(type\_traits)的一些列模板，它们可以在编译器就获得有关类型的特性信息。也就是说：

	std::cout << std::is_trivial<A>::value << std::endl;

在运行时相当于：

	std::cout << 1 << std::endl;

这种编译期获得结果的特性让我们可以结合 static_assert 完成更多的事情。如：

	static_assert(std::is_trivially_constructible<A>::value, "A is not pod type");

那么如果A不具备 trivial constructor，那么我们可以在程序编译期得到一个编译错误：A is not pod type

std::is_trivial判断一个类型是否为trivial类型。C++标准把trivial类型定义如下： 

- 没有 nontrivial constructor

- 没有 nontrivial copy constructor 

- 没有 nontrivial move constructor

- 没有 nontrivial assignment operator 

- 有一个 trivial destructor 

由于类A和类B均有 nontrivial constructor 因此它们都不是trivial类型。
