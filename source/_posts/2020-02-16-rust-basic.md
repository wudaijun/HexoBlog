---
title: 初识 Rust
layout: post
categories: rust
tags: rust
---

之前被同事安利了很多次Rust，周末没事去[Rust官方文档](https://kaisery.github.io/trpl-zh-cn/title-page.html)学习了下，记录一些对Rust语言粗浅理解。

### 一. 所有权系统

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

结合上面的规则，`s.clear`需要清空string，因此它会尝试获取s的一个可变引用(函数原型为:`clear(&mut self)`)，而由于s已经有一个不可变引用word，这破坏了规则2，因此编译器会报错。Rust通过显式的引用可变性 + 编译期检查实现了类似常量指针的功能(但其实在Rust中真正指针是Box<T>，它是另一个独立的对象)。

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

#### 6. 其它补丁

除了前面讨论的这些特性之外，Rust还针对所有权系统提供了其它工具，用于各类上述规则无法满足的情形，这里只是列举，不再详述。

1. `Box<T>`: 相当于C的`malloc`，用于允许将一个值放在堆上而不是栈上，在栈上只保留固定大小的指针字段
2. `Rc<T>`: 非线程安全的引用计数指针，用于实现多所有权，通过`Rc::clone`即可获得一个新的指针，与被克隆指针指向同一个对象
3. `RefCell<T>`: 能够基于不可变值修改其内部值(即RefCell字段)，它的本质是对RefCell字段的可变借用检查将**发生运行时而非编译期**

总之，Rust编译器是天生保守的，它会尽全力拒绝那些可能不正确的程序，Rust确实能在编译期检查到很多大部分语言只能在运行期暴露的错误，这是Rust最迷人的地方之一。但是，与此同时，Rust编译器也可能会拒绝一些正确的程序，此时就需要如生命周期注解，`Rc<T>`等工具来辅助编译器，甚至通过`RefCell<T>`，unsafe等方案来绕过编译器检查。把**编译器做厚**，把**运行时做薄**，是Rust易用但高效，能够立足于系统级编程语言的根本。

最后总结下Rust所有权系统的规则:

1. Rust 中的每一个值都有一个被称为其 所有者（owner）的变量。
2. 值有且只有一个所有者。
3. 当所有者（变量）离开作用域，这个值将被丢弃。

Rust的所有权系统重度依赖编译器的各种检查，在使用简单和运行快速安全之下，是Rust编译器在负重前行，Rust的编译速度目前来看还不是很理想，一直在优化。但作为一名开发者，个人是很赞同这种**编译器能做的检查，就决不让开发者操心**的准则的。

### 二. 函数式特性

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

### 三. OOP特性

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

### 四. 泛型和元编程

Rust的泛型和元编程赋予语言更强大的灵活性。这里只列举个人目前学习到的一些要点。

Rust泛型的一些特性:

1. 模板泛型: 在编译期填充具体类型，实现单态化
2. 支持枚举泛型: 如: `enum Option<T> { Some(T), None, }`
3. Trait Bound: `fn notify(item: impl Summary) {...` 等价于 `fn notify<T: Summary>(item: T) {...` 等价于 `fn notify<T>(item: T) where T: Summary {...`
4. blanket implementations: 对实现了特定 trait 的类型有条件地实现方法，如标准库为任何实现了`Display` trait的类型实现了`ToString` trait: `impl<T: Display> ToString for T {`。这意味着你实现了A trait，标准库/第三方库就可以为你实现B trait。这是trait和泛型的一种特殊结合，也是Rust trait和传统OOP不同的地方之一

元编程能够生成代码的代码，如C++的模板由于其在预编译期处理，并且图灵完备，完全可以作为另一种语言来看待，它的执行结果就是另一种语言的代码。Rust的元编程通过宏来实现，宏的语法类似于这样:

```rust
#[macro_export]
macro_rules! vec {
    ( $( $x:expr ),* ) => {
        {
            let mut temp_vec = Vec::new();
            $(
                temp_vec.push($x);
            )*
            temp_vec
        }
    };
}
```

这段代码能将`let v: Vec<u32> = vec![1, 2, 3];`转换成:

```rust
let mut temp_vec = Vec::new();
temp_vec.push(1);
temp_vec.push(2);
temp_vec.push(3);
temp_vec
```

由于宏编程日常开发中使用较少，这里不再展开讨论。

### 五. 并发编程

基于Rust本身系统级编程语言的定位，Rust标准库本身只提供对OS Thread的基础抽象，即运行时本身不实现**轻量级线程**及其调度器，以保持其运行时的精简高效。

Rust的所有权系统设计之初是为了简化运行时的内存管理，解决内存安全问题，而Rust作为系统级编程语言，并发自然也是绕不过去的传统难题，起初Rust觉得这是两个独立的问题，然而随着所有权系统的完善，Rust发现**所有权系统也能解决一系列的并发安全问题**。相较于并发领域佼佼者Erlang前辈的口号"任其崩溃(let it crash)"，Rust的并发口号也是不输分毫: "无畏并发(fearless concurrency)"。下面我们来看看Rust为何如此自信，Rust支持消息交互和共享内存两种并发编程范式。

#### 1. 消息交互

Rust消息交互CSP模型，但也与Go这类CSP语言有一些区别。

```rust
fn main() {
    let (tx, rx) = mpsc::channel();
    let val = String::from("hi");
    thread::spawn(move || {
        tx.send(val).unwrap();
        
    });
    let received = rx.recv().unwrap();
    println!("Got: {}", received);
}
```

这个小小的例子有如下需要关注的细节:

1. Rust 在创建 channel 时无需指定其大小，因为Rust Channel的大小是没有限制的，并且明确区分发送端和接收端，对channel的写入是永远不会阻塞的。
2. Rust 在创建 channel 时也无需指定其类型，这是因为 tx 和 rx 是泛型对象，编译器会根据其实际发送的数据类型来实例化泛型(如这里的`std::sync::mpsc::Sender<std::string::String>`)，如果尝试对同一个 channel 发送不同类型，如果代码中没有调用`tx.send`函数都将会导致编译错误。
3. Rust编译器本身会尝试推测闭包以何种方式捕获外部变量，但通常是保守的借用。这里 move 关键字强制闭包获取其使用的环境值的所有权，因此main函数在创建线程后对val和tx的任何访问都会导致编译错误
4. `tx.send`本身是转移语义，即会转移val变量的控制权，因此在新创建线程在`tx.send(val)`之后对val的任何访问也会导致编译错误

上面的3,4其实就是我们在并发编程常犯的错误：对相同变量的非并发安全访问，由于闭包的存在，使得这类"犯罪"的成本异常低廉。而Rust的所有权系统则巧妙地在编译器就发现了这类错误，因为变量所有权只会同时在一个线程中，也就避免了有意无意的变量共享(哪怕只读)。

#### 2. 共享内存

受Rust所有权系统的影响，Rust中的内存共享初看起来有点繁杂:

```rust
use std::sync::{Mutex, Arc};
use std::thread;

fn main() {
    let counter = Arc::new(Mutex::new(0));
    let mut handles = vec![];

    for _ in 0..10 {
        let counter = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            let mut num = counter.lock().unwrap();

            *num += 1;
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }

    println!("Result: {}", *counter.lock().unwrap());
}
```

同样，这里面也有一些细节:

1. 和channel一样，`Mutex<T>`也是泛型的，并且只能通过`lock`才能得到其中的`T`值，确保不会忘记加锁
2. Mutex会在脱离作用域时，会自动释放锁，确保不会忘记释放锁
3. 这里有多个线程需要共享Mutex的所有权，因此需要用到并发安全的引用计数智能指针`Arc<T>`(`RC<T>`不是线程安全的)

### 六 体会

本文比较散乱，主要从编程范式的角度理解Rust，总的来说，这门语言给我的感觉还是挺好的，既有强于其它静态语言的安全性，又想尽办法让编写Rust像动态语言一样方便简洁，这中间Rust编译器功不可没。所有权的概念让Rust在编程语言中独树一帜，可能要多适应下，这种特性让我想起了Erlang中的变量不可变，为代码分析和并发安全提供了很多便利，所有权系统本质上也是一种不变性约束，即**一个值的所有权只能属于一个变量**，这让编译器可以检查一些隐藏的代码错误，并且保持高效的运行时(对比golang的`-race`竞态检查要让运行时多占几倍CPU内存，并且运行时还要帮开发者检查并发的map访问)。准备有机会找个合适的场景用Rust实践下，增强理解。
