---
title: 初识 Rust
layout: post
categories: rust
tags: rust
---

之前被同事安利了很多次Rust，周末没事去[Rust官方文档](https://kaisery.github.io/trpl-zh-cn/title-page.html)学习了下，记录一些个人粗浅理解。

### 一. Rust中的所有权系统

要说Rust最有别于其它语言的特性，应该就是它的所有权系统了。要谈所有权系统，从GC谈起是个不错的切入点，我们众所周知的程序语言GC只要包含两种: 手动GC和自动GC，它们各有利弊，总的来说是运行时效率和开发效率之前的权衡取舍，由于现代硬件设施发展速度很快，运行时效率越来越不是问题，因此自动GC逐渐成为新语言的标配。而Rust的GC，按照我的理解，可以将其看做半自动GC，即开发者在代码中通过所有权约束来明确变量的生命周期，这样Rust在编译器就已经知道内存应该何时释放，也就不需要运行时通过复杂的[GC算法]([常见GC算法](https://wudaijun.com/2017/12/gc-study/)去解析变量的引用关系，对运行时几乎零负担，这也是Rust敢号称系统级编程语言，运行时效率叫板C/C++的底气来源。

<!--more-->

Rust GC的核心就是所有权系统，它基于以下事实:

1. 编译器能够解析局部变量的生命周期，正确管理栈内存的收缩扩张
2. 堆内存最终都是通过栈变量来读取和修改

那么，我们能否让堆内存管理和栈内存管理一样轻松，成为编译期就生成好的指令呢？Rust就是沿着这个思路走的，它将堆内存的生命周期和栈变量绑定在一起，当函数栈被回收，局部变量失效时，其对应的堆内存也会被回收。

```rust
{
    let s = String::from("hello"); // 从此处起，s 是有效的
    // 使用 s
}                               // 此作用域已结束，
                                // s 不再有效
```

如代码所示，局部变量s和对应的字符串堆内存绑定在了一起，称s对这块堆内存具备所有权，当s无效时，对应String堆内存也会回收。编译器知道s的作用域，也就自然知道何时执行对String执行回收。

以上是所有权系统的核心理念，但要达成整套系统的完备性，还需要一些其它规则来辅助:

#### 1. 控制权转移

当发生局部变量赋值，如执行 `let s1 = s;` 时，Rust要么执行深拷贝，代价是运行时开销，要么浅拷贝，代价是s和s1只能有其中一个对String有所有权(否则对堆内存二次回收)。Rust选择了第二种方案，即s1拥有String的所有权，s在赋值给s1后不再有效，这之后对s的访问将会导致编译错误。在Rust中，这叫做**控制权转移**，如果不想发生控制权转移，可以使用`s.clone()`来获得s的深拷贝。

#### 2. 值语义的控制权转移

针对简单值(即可直接分配在栈上的值)，按照控制权转移规则，如果有`let a = 5; let b = a;` 那么a也无效了，而实际上针对整数这种类型，大多数语言都是值语义的，在Rust中，这种值语义的类型通过`Copy trait`来实现，对于`Copy trait`类型来说，它不需要显式Clone，也不会发生控制权转移。

同样不会发生控制权转移的还有切片，如`let a = [1, 2, 3, 4, 5]; let slice = &a[1..3];`，slice指向了a的部分元素，相当于引用了a的一部分，这不会发生控制权转移。

#### 3. 函数调用的控制权转移

按照局部变量赋值的控制权转移规则，函数返回值和函数参数的隐式赋值也会导致控制权转移:

```rust
fn main() {
        let s1 = String::from("hello");
        // 调用calculate_length后，s1的控制权转移给了函数实参，在这之后s1就失效了
        // 为了后续能够继续访问String数据，需要通过返回值将控制权又转移回来
        let (s2, len) = calculate_length(s1); 
        // 这里就不能继续访问s1了，只能使用s2
        println!("The length of '{}' is {}.", s2, len);
}

fn calculate_length(s: String) -> (String, usize) {
        let length = s.len();
        (s, length)
}
```

可以看到，在控制权转移规则下，这种控制权转来转去的方式非常麻烦。这种情况下，更合适的做法是使用引用，在不转移控制权的前提下传递参数，但这里我们以另一个函数`first_word`为例，该函数求字符串内空格分隔的第一个单词:

```rust
// first_word 通过引用借用了 s1，不发生控制权转移，函数返回后也不会回收形参s指向的值
fn first_word(s: &String) -> &str {
    let bytes = s.as_bytes();
    for (i, &item) in bytes.iter().enumerate() {
        if item == b' ' {
            return &s[0..i];
        }
    }
    &s[..]
}

fn main() {
    let mut s = String::from("hello world");
    let word = first_word(&s);
    s.clear();
    println!("the first word is: {}", word);
}
```

选用`fist_word`是因为它展示了Rust引用的另一个有意思的特性。由于`first_word`返回的引用结果是基于引用参数的局部引用，因此当main调用`s.clear()`时，事实上也导致word引用失效了，导致得到非预期的结果。这在其它语言是指针/引用带来的难点之一，即要依靠开发者去解析内存引用关系，确保对内存的修改不会有非预期的副作用。而在Rust中，上面的代码不会通过编译！因为Rust对引用做了诸多限制:

1. 和变量一样，引用分为可变引用和不可变引用，可变引用需要在可变变量的基础上再显式声明: 如`let r = &mut s;`
2. 在任意给定时间，要么只能有一个可变引用，要么只能有多个不可变引用
3. 引用必须总是有效的 (例如函数返回一个局部变量的引用将会得到编译错误)

结合上面的规则，`s.clear`需要清空string，因此它会尝试获取s的一个可变引用(函数原型为:`clear(&mut self)`)，而由于s已经有一个不可变引用word，这破坏了规则2，因此编译器会报错。Rust通过显式的引用可变性 + 编译期检查实现了类似常量指针的功能。

#### 4. 引用有效性问题

引入了引用并不是就万事大吉了，还要考虑引用有效性问题:

```rust
{
    // rust不允许存在空值，确切地说是不允许使用空值，这里只是声明r，在第一次使用r前必须先初始化它，否则编译器会报错
    let r;
    {
        let x = 5;
        r = &x;
    } // 这之后 r 引用的 x 已经脱离作用域失效了，而 r 还在有效作用域内，继续访问 r 将会导致非预期结果
    println!("r: {}", r);
}
```

那么如果避免以上代码呢，当然又是依靠万能的Rust编译器了，编译器的**借用检查器**会比较引用和被引用数据的生命周期，确保不会出现悬挂引用。

#### 5. 生命周期注解

有Rust编译器的殚精竭虑，开发者就能安全使用这套所有权系统而高枕无忧了么，当然不是，编译器所知也仅限于编译期就能获得的信息，比如以下代码:

```rust
fn longest(x: &str, y: &str) -> &str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}

fn main() {
    let string1 = String::from("abcd");
    let string2 = "xyz";

    let result = longest(string1.as_str(), string2);
    println!("The longest string is {}", result);
}
```

上面的代码无法通过编译，因为longest函数的参数和返回值都是引用，编译器无法获悉函数返回的引用是来自于x还是来自于y(这是运行时的东西)，那么前面说的借用检查器也就无法通过分析作用域保证引用的有效性了。

这个时候就需要建立一套额外的规则来辅助借用检查器，将本来应该在运行时决议的事情放到编译器来完成，Rust把这套规则叫做**生命周期注解**，生命周期注解本身不影响引用的生命周期，它用来指定函数的引用参数和引用返回值之间的生命周期对应关系，这样编译器就可以按照这种关系进行引用生命周期推敲，生命周期注释的语法和泛型类似(这也是比较有意思的一点，将引用生命周期像类型一样来抽象):

```rust
// 'a 和泛型中的T一样，这里的注解表示:  'a 的具体生命周期等同于 x 和 y 的生命周期中较小的那一个
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}

// 下面是一些例子，说明Rust编译器是如何依靠注解来保证引用的有效性的

// 例1 
// 根据longest的生命周期注解，result的生命周期应该等于string1,string2中较短的那个
// 而这里result的生命周期明显大于string2，因此借用检查器会报错
fn main() {
    let string1 = String::from("long string is long");
    let result;
    {
        let string2 = String::from("xyz");
        result = longest(string1.as_str(), string2.as_str());
    }
    println!("The longest string is {}", result);
}

// 例2
// 这里的result虽然早于string2声明，但由于Rust不能使用未赋值的变量，因此result的生命周期其实是从第一次赋值开始的
// 从而满足longest引用返回值生命周期<=任一引用参数生命周期，能够正常运行
fn main() {
    let string1 = String::from("long string is long");
    {
        let result;
        let string2 = String::from("xyz");
        result = longest(string1.as_str(), string2.as_str());
        println!("The longest string is {}", result);
    }
}


// 例3
// 如果我们将longest改成这样，它将不能通过编译
// 因为编译器看到了longest函数返回了y，然而生命周期注解中，输入引用y和返回值引用是两个独立的生命周期，互不关联。编译器觉得自己被欺骗了。
fn longest<'a,'b>(x: &'a str, y: &'b str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}
```

最后总结下Rust所有权系统的规则:

1. Rust 中的每一个值都有一个被称为其 所有者（owner）的变量。
2. 值有且只有一个所有者。
3. 当所有者（变量）离开作用域，这个值将被丢弃。

Rust的所有权系统重度依赖编译器的各种检查，在使用简单和运行快速安全之下，是Rust编译器在负重前行，Rust的编译速度目前来看还不是很理想，一直在优化。但作为一名开发者，个人是很赞同这种**编译器能做的检查，就决不让开发者操心**的准则的。

### 二. Rust中的FP特性

我在[理解函数式编程](https://wudaijun.com/2018/05/understand-functional-programing/)中提到，现在的语言不再受限于各种编程范式的约束，而是更偏实用主义，Rust也是这样的语言，它受函数式语言的影响颇深。

#### 1. 函数是第一类对象

函数可作为参数，返回值，动态创建，并且动态创建的函数具备捕获当前作用域上下文的能力，也就是闭包，提供标准库容器迭代器模式并支持开发者扩展等，这些都是如今大部分语言的标配，无需过多解释。

有一点需要提一下，Rust的闭包如果要捕获上下文的话，也要考虑到所有权转移的问题(转移，引用，可变引用)，并且Rust编译器会尝试自动推测你的闭包希望以那种方式来捕获环境。

#### 2. 变量可变性

Rust中的变量默认是不可变的，但也支持通过`let mut x = 5;`声明可变变量。合理使用不可变变量能够利用编译器检查使代码易于推导，可重入，无副作用。

#### 3. 模式匹配

模式匹配我最早在Erlang中接触，这个起初不是很适应的功能在用习惯之后，会发现它可以为程序提供更多对程序控制流的支配权，写出强大而简洁的代码。Rust也支持模式匹配:

```rust
struct Point {
    x: i32,
    y: i32,
}
fn main() {
    let p = Point { x: 7, y: 2 }; // 构造一个Point值匹配给命名变量p
    match p {
        Point { x :0, y} => println!("case 1: {}", y), 	// 匹配p.x==0
        Point { x, y: 0..=2 } => println!("case 2: {}", x), // 匹配0<=p.y<=2
        Point { x: a, y: _ } => println!("case 3: {}", a), // 匹配其它情况，并将字段x的值赋给变量a
    }
    if let Point {x: 7, y: b} = p { // 匹配 x==7，并取出y值
    	println!("case 4: {}", b)
    }
}
```

### 三. Rust中的OOP特性

#### 1. Object

Rust提供基本的结构体字段封装和字段访问控制(可见性)，并且允许在此之上扩展结构体方法及方法的可见性:

``` rust
pub struct MyStruct {
    x : i32     // 默认为私有字段
    pub name : String // 指定为公有字段
}

impl MyStruct {
    pub fn getx(&self) -> i32 {
        self.x
    }
}
```

#### 2. 继承

OOP的继承(subclass)主要有两个作用，**代码复用** 和 **子类化(subtype)** ，如C++的继承就同时实现了这两点，继承是一把双刃剑，因为传统继承不只是有代码复用和子类化的功能，它还做到了字段复用，即对象父子内存模型的一致性，当引入对象内存模型之后，各种多重继承，菱形继承所带来的问题不堪其扰。**虚基类**，**显式指定父类作用域**或者干脆**不允许多重继承**等方案也是头痛医头，脚痛医脚。

近10年兴起的新语言，如Golang就没有继承，它通过内嵌匿名结构体来实现代码复用，但丢失了dynamic dispatch，通过interface{}(声明式接口，隐式implement)来实现子类化，但也带来了运行时开销。

关于subclass, subtype, dynamic dispatch等概念，可以参考我之前的[编程范式游记](https://wudaijun.com/2019/05/programing-paradigm/))。

在Rust中，是通过trait来实现这两者的，trait本质上是**实现式接口**，用于对不同类型的相同方法进行抽象。Rust的trait有如下特性:

1. trait是需要显式指明继承实现的
2. trait可以提供默认实现，但不能包含字段(部分subclass)
3. trait的默认实现可以调用trait中的其它方法，哪怕这些方法没有提供默认实现(dynamic dispatch)
4. trait可以用做参数或返回值用于表达满足该接口的类型实例抽象(subtype)
5. trait可通过+号实现拼接，表示同时满足多个接口

以下代码简单展示了Rust trait的基本特性:

```rust
pub trait Summary {
    fn summarize_author(&self) -> String;

    fn summarize(&self) -> String {
        format!("(Read more from {}...)", self.summarize_author())
    }
}

pub trait Title {
    fn title(&self) -> String;
}

pub struct Tweet {
    pub username: String,
    pub title: String,
    pub content: String,
}

impl Summary for Tweet {
    fn summarize_author(&self) -> String {
        format!("@{}", self.username)
    }
}

impl Title for Tweet {
    fn title(&self) -> String {
        format!("{}", self.title)
    }
}

// 函数声明等价于 pub fn notify<T: Summary + Title>(item: T) {
// 即本质是bounded generic types的语法糖
pub fn notify(item: impl Summary + Title) {
    println!("1 new tweet: {}, {}", item.title(), item.summarize());
}

fn main() {
        let t = Tweet {
        	username: String::from("wudaijun"),
        	title: String::from("study rust"),
        	content: String::from("rust is the best language")
        };
        notify(t)
}
```

总的来说，Rust对OOP的支持是比较完善的，舍弃了继承和字段复用，通过trait来完成代码复用和子类化，避免了OOP继承的各种坑。


本文比较零散，看到哪写到哪，Rust的宏，并发编程，工程实践等高级特性待后续学习整理。