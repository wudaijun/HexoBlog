---
layout: post
title: C++ 右值引用
tags:
  c/c++
categories:
  c/c++
  
---


## 一. 定义

通常意义上，在C++中，可取地址，有名字的即为左值。不可取地址，没有名字的为右值。右值主要包括字面量，函数返回的临时变量值，表达式临时值等。右值引用即为对右值进行引用的类型，在C++98中的引用称为左值引用。

如有以下类和函数:

```

class A
{
private:
	int* _p;
};

A ReturnValue()
{
	return A();
}

```

`ReturnValue()`的返回值即为右值，它是一个不具名的临时变量。在C++98中，只有常量左值引用才能引用这个值。 

```

A& a = ReturnValue(); // error: non-const lvalue reference to type 'A' cannot bind to a temporary of type 'A'
      
const A& a2 = ReturnValue(); // ok

```

通过常量左值引用，可以延长ReturnValue()返回值的生命周期，但是不能修改它。C++11的右值引用出场了：

`A&& a3 = ReturnValue();`

右值引用通过"&&"来声明， a3引用了ReturnValue()的返回值，延长了它的生命周期，并且可以对该临时值进行修改。

<!--more-->

## 二. 移动语义

右值引用可以引用并修改右值，但是通常情况下，修改一个临时值是没有意义的。然而在对临时值进行拷贝时，我们可以通过右值引用来将临时值内部的资源移为己用，从而避免了资源的拷贝：

```

#include<iostream>

class A
{
public:
	A(int a)
		:_p(new int(a))
	{
	}

	// 移动构造函数 移动语义
	A(A&& rhs)
		: _p(rhs._p)
	{
		// 将临时值资源置空 避免多次释放 现在资源的归属权已经转移
		rhs._p = nullptr; 
		std::cout<<"Move Constructor"<<std::endl;
	}
	// 拷贝构造函数 复制语义
	A(const A& rhs)
		: _p(new int(*rhs._p))
	{
		std::cout<<"Copy Constructor"<<std::endl;
	}
	
private:
	int* _p;
};

A ReturnValue() { return A(5); }

int main()
{
	A a = ReturnValue();
	return 0;
}

```

运行该代码，发现Move Constructor被调用(在g++中会对返回值进行优化，不会有任何输出。可以通过`-fno-elide-constructors`关闭这个选项)。在用右值构造对象时，编译器会调用`A(A&& rhs)`形式的移动构造函数，在移动构造函数中，你可以实现自己的**移动语义**，这里将临时对象中_p指向内存直接移为己用，避免了资源拷贝。当资源非常大或构造非常耗时时，效率提升将非常明显。如果A没有定义移动构造函数，那么像在C++98中那样，将调用拷贝构造函数，执行**拷贝语义**。移动不成，还可以拷贝。

### std::move

C++11提供一个函数std::move()来将一个左值强制转化为右值：

```
A a1(5);
A a2 = std::move(a1);
```

上面的代码在构造a2时将会调用移动构造函数，并且a1的\_p会被置空，因为资源已经被移动了。而a1的生命周期和作用域并没有变，仍然要等到main函数结束后再析构，因此之后对a1的\_p的访问将导致运行错误。

std::move乍一看没什么用。它主要用在两个地方：

1. 帮助更好地实现移动语义
2. 实现完美转发(下面会提到)

考虑如下代码：

```
class B
{
public:
	B(B&& rhs)
		: _pb(rhs._pb)
	{
		// how can i move rhs._a to this->_a ?
		rhs._pb = nullptr;
	}

private:
	A _a;
	int * pb;
}
```

对于B的移动构造函数来说，由于rhs是右值，即将被释放，因此我们不只希望将\_pb的资源移动过来，还希望利用A类的移动构造函数，将A的资源也执行移动语义。然而问题出在如果我们直接在初始化列表中使用：`_a(rhs._a)` 将调用A的拷贝构造函数。因为参数 rhs.\_a 此时是一个具名值，并且可以取址。实际上，B的移动构造函数的参数rhs也是一个左值，因为它也具名，并且可取址。这是在C++11右值引用中让人很迷惑的一点：**可以接受右值的右值引用本身却是个左值**

这一点在后面的完美转发还会提到。现在我们可以用std::move来将rhs.\_a转换为右值：`_a(std::move(rhs._a))`，这样将调用A的移动构造。实现移动语义。当然这里我们确信rhs.\_a之后不会在使用，因为rhs即将被释放。
	
	
## 三. 完美转发

如果仅仅为了实现移动语义，右值引用是没有必要被提出来的，因为我们在调用函数时，可以通过传引用的方式来避免临时值的生成，尽管代码不是那么直观，但效率比使用右值引用只高不低。

右值引用的另一个作用是完美转发，完美转发出现在泛型编程中，将模板函数参数传递给该函数调用的下一个模板函数。如：

```
template<typename T>
void Forward(T t)
{
	Do(t);
}
```

上面的代码中，我们希望Forward函数将传入参数类型原封不动地传递给Do函数，即Forward函数接收的左值，则Do接收到左值，Forward接收到右值，Do也将得到右值。上面的代码能够正确转发参数，但是是不完美的，因为Forward接收参数时执行了一次拷贝。

考虑到避免拷贝，我们可以传递引用，形如`Forward(T& t)`，但是这种形式的Forward并不能接收右值作为参数，如Forward(5)。因为非常量左值不能绑定到右值。考虑常量左值引用：`Forward(const T& t)`，这种形式的Forward能够接收任何类型(常量左值引用是万能引用)，但是由于加上了常量修饰符，因此无法正确转发非常量左值引用：

```
void Do(int& i)
{
	// do something...
}

template<typename T>
void Forward(const T& t)
{
	Do(t);
}

int main()
{
	int a = 8;
	Forward(a); // error. 'void Do(int&)' : cannot convert argument 1 from 'const int' to 'int&'
	return 0;
}
```

基于这种情况， 我们可以对Forward的参数进行const重载，即可正确传递左值引用。但是当Do函数参数为右值引用时，Forward(5)仍然不能正确传递，因为Forward中的参数都是左值引用。

下面介绍在 C++11 中的解决方案。

### 引用折叠

C++11引入了引用折叠规则，结合右值引用来解决完美转发问题：

```

typedef const int T;
typedef T& TR;
TR& v = 1; // 在C++11中 v的实际类型为 const int&

```

如上代码中，发生了引用折叠，将TR展开，得到 T& & v = 1(注意这里不是右值引用)。 这里的 T& + & 被折叠为 T&。更为详细的，根据TR的类型定义，以及v的声明，发生的折叠规则如下：
	
	T&  + &   = T&
	T&  + &&  = T&
	T&& + &   = T&
	T&& + &&  = T&&
	
上面的规则被简化为：只要出现左值引用，规则总是优先折叠为左值引用。仅当出现两个右值引用才会折叠为右值引用。

### 再谈转发

那么上面的引用折叠规则，对完美转发有什么用呢？我们注意到，对于T&&类型，它和左值引用折叠为左值引用，和右值引用折叠为右值引用。基于这种特性，我们可以用 T&& 作为我们的转发函数模板参数：

```

template<typename T>
void Forward(T&& t)
{
	Do(static_cast<T&&>(t));
}

```

这样，无论Forward接收到的是左值，右值，常量，非常量，t都能保持为其正确类型。

当传入左值引用 X& 时：

```
void Forward(X& && t)
{
	Do(static_cast<X& &&>(t));
}
```

折叠后：

```
void Forward(X& t)
{
	Do(static_cast<X&>(t));
}
```

这里的static_cast看起来似乎是没有必要，而它实际上是为右值引用准备的：

```
void Forward(X&& && t)
{
	Do(static_cast<X&& &&>(t));
}
```

折叠后：

```
void Forward(X&& t)
{
	Do(static_cast<X&&>(t));
}
```

前面提到过，可以接收右值的右值引用本身却是个左值，因为它具名并且可以取值。因此在`Forward(X&& t)`中，参数t已经是一个左值了，此时我们需要将其转换为它本身传入的类型，即为右值。由于static_cast中引用折叠的存在，我们总能还原参数本来的类型。

在C++11中，`static_cast<T&&>(t)` 可以通过 `std::forward<T>(t)` 来替代，`std::forward`是C++11用于实现完美转发的一个函数，它和`std::move`一样，都通过static_cast来实现。我们的Forward函数最终变成了：

```
template<typename T>
void Forward(T&& t)
{
	Do(std::forward<T>(t));
}
```

可以通过如下代码来测试：
```
#include<iostream>
using namespace std;

void Do(int& i)       { cout << "左值引用"    << endl; }
void Do(int&& i)      { cout << "右值引用"    << endl; }
void Do(const int& i)  { cout << "常量左值引用" << endl; }
void Do(const int&& i) { cout << "常量右值引用" << endl; }

template<typename T>
void PerfectForward(T&& t){ Do(forward<T>(t)); }

int main()
{
	int a;
	const int b;
	
	PerfectForward(a);			// 左值引用
	PerfectForward(move(a));		// 右值引用
	PerfectForward(b);			// 常量左值引用
	PerfectForward(move(b));		// 常量右值引用
	return 0;
}
```

## 四. 附注

左值和左值引用，右值和右值引用都是同一个东西，引用不是一个新的类型，仅仅是一个别名。这一点对于理解模板推导很重要。对于以下两个函数
```
template<typename T>
void Fun(T t)
{
	// do something...
}

template<typename T>
void Fun(T& t)
{
	// do otherthing...
}
```
`Fun(T t)`和`Fun(T& t)`他们都能接受左值(引用)，它们的区别在于对参数作不同的语义，前者执行拷贝语义，后者只是取个新的别名。因此调用`Fun(a)`编译器会报错，因为它不知道你要对a执行何种语义。另外，对于`Fun(T t)`来说，由于它执行拷贝语义，因此它还能接受右值。因此调用`Fun(5)`不会报错，因为左值引用无法引用到右值，因此只有`Fun(T t)`能执行拷贝。

最后，附上VS中 `std::move` 和 `std::forward` 的源码:
```

// move
template<class _Ty> 
inline typename remove_reference<_Ty>::type&& move(_Ty&& _Arg) _NOEXCEPT
{	
	return ((typename remove_reference<_Ty>::type&&)_Arg);
}

// forward
template<class _Ty> 
inline _Ty&& forward(typename remove_reference<_Ty>::type& _Arg)
{	// forward an lvalue
	return (static_cast<_Ty&&>(_Arg));
}

template<class _Ty> 
inline 	_Ty&& forward(typename remove_reference<_Ty>::type&& _Arg) _NOEXCEPT
{	// forward anything
	static_assert(!is_lvalue_reference<_Ty>::value, "bad forward call");
	return (static_cast<_Ty&&>(_Arg));
}

```
