---
title: 初识 Rust
layout: post
categories: rust
tags: rust
---

之前被同事安利了很多次Rust，周末没事去[Rust官方文档](https://kaisery.github.io/trpl-zh-cn/title-page.html)学习了下，记录一些对Rust语言粗浅理解。

### 一. 所有权系统

要说Rust语言的核心优势，应该就是运行效率+内存安全了，这两者都与其独树一帜的所有权系统有关。要谈所有权系统，GC是个不错的切入点，众所周知，编程语言GC主要包含两种: 手动GC和自动GC，它们各有利弊，总的来说是运行效率和内存安全之间的权衡取舍。而Rust则尝试两者兼顾，Rust的GC，我将其理解为半自动GC或编译期GC，即开发者配合编译器通过所有权约束来明确变量的生命周期，这样Rust在编译期就已经知道内存应该何时释放，不需要运行时通过复杂的[GC算法](https://wudaijun.com/2017/12/gc-study/)去解析变量的引用关系，也无需像C/C++让开发者对各种内存泄露、越界访问等问题如履薄冰。这也是Rust敢号称可靠的系统级编程语言，运行时效率叫板C/C++的底气来源。

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

Rust所有权系统的核心规则如下:

1. Rust 中的每一个值都有一个被称为其 所有者（owner）的变量。
2. 值有且只有一个所有者。
3. 当所有者（变量）离开作用域，这个值将被丢弃。

规则需要简单，要达成这套规则的完备性，还需要其它系统方方面面的协助和完善。下面展开聊聊。

#### 1. 控制权转移

当发生局部变量赋值，如执行 `let s = String::from("big str"); let s1 = s;` 时，Rust要么执行深拷贝，代价是运行时开销，要么浅拷贝，代价是s和s1只能有其中一个对String有所有权(否则会导致对堆内存的二次回收)。Rust选择了第二种方案，即s1拥有String的所有权，s在赋值给s1后不再有效，这之后对s的访问将会导致编译错误。在Rust中，这叫做**控制权转移**，此时也称`let s1 = s;`是**转移语义**，在Rust中，变量与值的交互方式分为以下几种:

1. 移动(Move)语义: 浅拷贝，且会发生控制权转移，这是Rust的默认行为
2. 克隆(Clone)语义: 深拷贝，通过**显式**调用clone()来避免控制权转移，如 `let s1 = s.clone();`，如此s1和s均可继续使用
3. 复制(Copy)语义: 浅拷贝，主要针对值语义这类浅拷贝安全的场景，Rust默认为整型、布尔、字符、浮点、以及元组(当且仅当其包含的类型也都实现Copy的时候)实现了复制语义，因此对于`let a = 5; let b = a;`，不需要显式Clone，也不会发生控制转移，a和b可继续使用
4. 引用(Borrowing)语义: 也叫借用语义，Rust引用类似其它语言的指针，Rust创建引用的过程也称为借用，它允许你使用值但不获取其所有权

Clone是比Copy更基础的概念，对支持Copy语义的对象，它必然也是支持Clone的(值语义的浅拷贝就是它的深拷贝)。实现上来说，Clone，Copy均是Rust提供的trait(类似OOP接口，但可包含默认实现，后面Rust OOP编程中再详说)，其中Clone trait依赖Copy trait，简单来说: 所有想要实现Copy trait的类，都需要同时实现Clone trait。这样从实现层保证了所有可Copy的对象，必然是可Clone的。

小结下Copy和Clone的区别和联系:

- Clone是显式的，Rust不会在任何地方自动调用clone()执行深拷贝。Copy是隐式的，编译期识别到Copy语义对象的复制时，会自动执行简单浅拷贝，并且不会发生控制转移
- Clone是可重写的，各个类型可以自定义自己的clone()方法。Copy是不可重写的，因为编译器直接执行栈内存拷贝就行了，如果某个类型需要重写Copy，那么它就不应该是Copy语义的
- 支持Copy语义的类型必然支持Clone语义

下面这个例子进一步说明几种赋值语义，引用语义的细节将单独在下一节展开讨论。

``` rust
// === Case1: 移动 ===
struct MyStruct {
    part: i32,
}

fn main() {
    let a = MyStruct {part: 123};
    let b = a;
    // 编译错误: a的数据控制权转移到了b，a将无法再被使用
    println!("{}, {}", i.part, j.part)

}

// === Case2: 克隆 ===
struct MyStruct {
    part: i32,
}

// 实现Clone trait
impl Clone for MyStruct {
    fn clone(&self) -> Self {
    	 // 等价于 MyStruct { part: self.part }，因为i32是满足复制语义的(浅拷贝即深拷贝)
        MyStruct { part: self.part.clone() }
    }
}

fn main() {
    let a = MyStruct {part: 123};
    let b = a.clone();	// 显式指明clone()，执行深拷贝
    // OK. 之后a和b都具有各自独立的数据所有权，因此均可使用
    println!("{}, {}", a.part, b.part)
}

// === Case3: 复制 ===

// derive是Rust中的属性，类似类型注解的概念
// #[derive(Copy, Clone)] 表示在 MyStruct 上实现Copy，Clone两个trait，并使用这两个trait的默认实现
// Clone trait默认实现会逐个调用struct的字段的clone()方法来实现深拷贝，类似前面Case2手动重写的clone()方法
//            如果有字段未实现Clone trait(比如包含另一个自定义Struct)，则编译错误
// Copy trait不需要也不允许重写，如果有字段未实现Copy trait(比如包含String字段)，同样会触发编译错误
// 对于MyStruct而言，由于它实现了Copy trait，因此它的clone()方法完全可以直接写成:
// fn clone(&self) -> Self {
// 		*self
// } 
#[derive(Clone, Copy)]
struct MyStruct {
    part: i32,
}

fn main() {
    let a = MyStruct {part: 123};
    // 等价于 let mut b = a.clone();
    let mut b = a;
    b.part = 456;
    // OK. a和b具有独立的数据所有权
    println!("{}, {}", a.part, b.part)
}

// === Case4: 引用 ===
fn main() {
	let a = MyStruct{part: 123};
	let b = &a;
	// OK. b只是引用了a，并不会发生控制权转移
	println!("{}, {}", a.part, b.part)
}
```

Rust编译器会识别和检查变量类型是否实现或调用了指定trait，从而决定变量赋值是什么语义，以确定控制权归属。


#### 2. 使用引用来避免控制权转移

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

选用`fist_word`是因为它展示了Rust引用的另一个有意思的特性。由于`first_word`返回的引用结果是基于引用参数的局部引用，因此当main调用`s.clear()`时，事实上也导致word引用失效了，导致得到非预期的结果。这在其它语言是指针/引用带来的难点之一，即要依靠开发者去解析内存引用关系，确保对内存的修改不会有非预期的副作用。而在Rust中，上面的代码不会通过编译！

和变量一样，Rust中的引用分为可变引用和不可变引用，可变引用需要在可变变量的基础上再显式声明: 如`let r = &mut s;` Rust编译器会想尽办法保证**引用的两大原则**:

1. 在任意给定时间，要么只能有一个可变引用，要么只能有多个不可变引用
2. 引用必须总是有效的 (例如函数返回一个局部变量的引用将会得到编译错误)

结合上面的规则，`s.clear`需要清空string，因此它会尝试获取s的一个可变引用(函数原型为:`clear(&mut self)`)，而由于s已经有一个不可变引用word，这破坏了规则1，因此编译器会报错。

对于规则2，编译器的**借用检查器**会比较引用和被引用数据的生命周期，确保不会出现悬挂引用，如以下代码不会编译通过:

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

以上对引用的限制，有个非常显著的好处就是避免并发数据竞争问题:

1. 两个或更多指针同时访问同一数据
2. 至少有一个指针被用来写入数据
3. 没有同步数据访问的机制

Rust可以在编译期就避免大部分的数据竞争！

#### 3. 生命周期注解

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

生命周期注解也可用于结构体中，用于声明结构体与其字段的生命周期关系:

```rust
// 这个标注意味着 ImportantExcerpt 的实例不能比其 part 字段中的引用存在的更久
struct ImportantExcerpt<'a> {
    part: &'a str,
    // 如果part是String的引用，则会编译错误，因为String拥有自己数据的所有权
    // 生命周期注解只用来标注引用与引用间的生命周期关系(以保证引用的有效性)，而不能用于强行关联两个独立的生命周期
    // part: 'a String,
}

fn main() {
    let mut i = ImportantExcerpt { part: "123"};
    {
    	  // 编译错误: 结构体实例i的生命周期比其引用字段part所引用的String s更长，违反了生命周期注解约束
        let s = String::from("123456");
        let part = s.as_str();
        // 编译成功: 这里part是字面量的不可变引用，而字面量存储二进制程序的特定位置，因此满足生命周期注解约束
        // let part = "123456";
        
        i.part = part;
    }
    println!("{}", i.part)
}
```

#### 4. 智能指针

前面讨论的控制权转移(确保一个值只有一个所有者，它负责这个值的回收)，引用(也就是指针，用于避免不必要的控制权转移)，生命周期注解(用于协助编译期保证引用的有效性)，主要都是围绕栈内存来的，只有String是个特例，它的实际内存会分配在堆上，以满足可变动态长度字符串的需求。在Rust中，栈内存和堆内存是被明确指定和分配的，Rust开发者通常会在出现以下情况时考虑用堆:

1. 当有一个在编译时未知大小的类型，而又想要在需要确切大小的上下文中使用这个类型值的时候: 比如在String，链表
2. 当有大量数据并希望在确保数据不被拷贝的情况下转移所有权的时候
3. 当希望拥有一个值并只关心它的类型是否实现了特定 trait 而不是其具体类型的时候

在Rust中，有如下几种指针:

1. `Box<T>`: 运行将数据分配在堆上，留在栈上的是指向堆数据的指针。`Box<T>`会在智能指针作用域结束时回收对应堆内存。`Box<T>`本身的是移动语义的，类似C++ `auto_ptr`。`Box<T>`与Rust引用的区别在于，前者指向的是堆内存，因此总能保证是有效的，而后者通常指向的是栈内存，因此需要借用检查器，生命周期注解等机制来确保引用是有效的。
2. `Rc<T>`: `Rc<T>`类似C++`shared_ptr`，基于引用计数而非控制权+作用域来回收堆内存，但`Rc<T>`对共享数据是只能读的(仍然受限于借用器检查，用于避免数据竞争)。`Rc<T>`默认也是移动语义的，可以调用`Rc::Clone(rc)`方法(比`rc.clone()`方法更轻量)以获得独立的`Rc<T>`并增加引用计数。
3. `RefCell<T>`: 能够基于不可变值修改其内部值，对`RefCell<T>`的借用检查将**发生运行时而非编译期**。如以下代码会导致运行Panic:

```rust
// RefCell<T>例子，以下代码会编译成功，但是运行Panic
fn main() {
    let x = RefCell::new(123);
    let a = x.borrow();
    let b = x.borrow();
    // OK. 运行时借用检查允许多个不可变引用
    println!("{}, {}", a, b);
    // Panic here! 运行时检查发现同时存在可变引用和不可变引用
    let mut c = x.borrow_mut();
    *c = 456;
    println!("{}", c);
}
```

`RefCell<T>`在天生保守的Rust编译规则下，为开发者提供了更高的灵活性，但也需要承担更大的运行时风险。一个`RefCell<T>`的应用场景是，通过Mock将原本的外部IO行为(`&self`参数的trait)，替换为内部数据变更(`&self`参数不变，但MockStruct通过持有`RefCell<T>`实现内部数据可变性)。

另外，由于`Rc<T>`支持对相同数据同时存在多个所有者，但是只能读数据，而`RefCell<T>`允许在不可变语义下实现内部可变性，那么`Rc<RefCell<T>>`就可以实现基于引用计数，可存在多个具有读写数据权限的智能指针(完整版C++ `shared_ptr`):

```
fn main() {
    let x = &Rc::new(RefCell::new(123));
    let a = Rc::clone(x);
    let b = Rc::clone(x);
    let c = Rc::clone(x);
    *b.borrow_mut() = 456;
    *c.borrow_mut() = 789;
    // Output:
    // RefCell { value: 789 }, RefCell { value: 789 }, RefCell { value: 789 }
    println!("{:?}, {:?}, {:?}", a, b, c)
}
```

#### 5. 小结

先总结下前面提到的Rust的各种机制是如何配合所有权系统来实现通过栈内存来管理堆内存，做到运行时零GC负担的:

1. 浅拷贝对象: 如i32，float，plain struct，默认直接执行栈拷贝，不涉及控制权转移，和常规语言无二
1. 深拷贝对象: 比如String，通过控制权转移来保证单所有者，在所有者退出作用域时，通过Drop trait确保数据被正确回收
2. 引用: 本质只是指针地址，借助编译器的借用检查器来避免数据竞态并保证引用的有效性，有时还需要开发者通过生命周期注解进行协助
3. 智能指针: 和String类似，也是深拷贝对象，但提供了更灵活的内存控制，包括避免深拷贝和控制权转移，引用计数共享数据，内部可变性等

总之，Rust编译器是天生保守的，它会尽全力拒绝那些可能不正确的程序，Rust确实能在编译期检查到很多大部分语言只能在运行期暴露的错误，这是Rust最迷人的地方之一。但是，与此同时，Rust编译器也可能会拒绝一些正确的程序，此时就需要如生命周期注解，`Rc<T>`等工具来辅助编译器，甚至通过`RefCell<T>`，unsafe等方案来绕过编译器检查。把**编译器做厚**，把**运行时做薄**，是Rust安全且高效，能够立足于系统级编程语言的根本。

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

传统OOP的继承(subclass)主要有两个作用，**代码复用** 和 **子类化(subtype)** ，如C++的继承就同时实现了这两点，继承是一把双刃剑，因为传统继承不只是有代码复用和子类化的功能，它还做到了字段复用，即对象父子内存模型的一致性，当引入对象内存模型之后，各种多重继承，菱形继承所带来的问题不堪其扰。**虚基类**，**显式指定父类作用域**或者干脆**不允许多重继承**等方案也是头痛医头，脚痛医脚。

近年兴起的新语言，如Golang就没有继承，它通过内嵌匿名结构体来实现代码复用，但丢失了dynamic dispatch，通过interface{}(声明式接口，隐式implement)来实现子类化，但也带来了运行时开销。

关于subclass, subtype, dynamic dispatch等概念，可以参考我之前的[编程范式游记](https://wudaijun.com/2019/05/programing-paradigm/))。

在Rust中，是通过trait来实现这两者的，trait本质上是**实现式接口**，用于对不同类型的相同方法进行抽象。Rust的trait有如下特性:

1. trait是需要显式指明实现的
2. trait可以提供默认实现，但不能包含字段(部分subclass)
3. trait的默认实现可以调用trait中的其它方法，哪怕这些方法没有提供默认实现(dynamic dispatch)
4. trait可以用做参数或返回值用于表达满足该接口的类型实例抽象(subtype)
5. trait本身也可以定义依赖(supertrait)，如Copy trait依赖Clone trait
6. 作为泛型约束时trait可通过+号实现拼接，表示同时满足多个接口

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

这个小例子有如下需要关注的细节:

1. Rust 在创建 channel 时无需指定其大小，因为Rust Channel的大小是没有限制的，并且明确区分发送端和接收端，对channel的写入是永远不会阻塞的
2. Rust 在创建 channel 时也无需指定其类型，这是因为 tx 和 rx 是泛型对象，编译器会根据其实际发送的数据类型来实例化泛型(如这里的`std::sync::mpsc::Sender<std::string::String>`)，如果尝试对同一个 channel 发送不同类型，或者代码中没有调用`tx.send`函数都将会导致编译错误
3. Rust编译器本身会尝试推测闭包以何种方式捕获外部变量，但通常是保守的借用。这里 move 关键字强制闭包获取其使用的环境值的所有权，因此main函数在创建线程后对val和tx的任何访问都会导致编译错误
4. `tx.send`也会导致val变量发生控制权转移，因此在新创建线程在`tx.send(val)`之后对val的任何访问也会导致编译错误
5. Rust通过Send trait标记类型所有权是否能在线程间传递(只是标记，无需实现)，几乎所有Rust类型的所有权都是Send的(除了像`Rc<T>`这种为了性能刻意不支持的并发的，跨线程传递会导致编译错误。应该使用线程安全的`Arc<T>`)

上面的3,4其实就是我们在并发编程常犯的错误：对相同变量的非并发安全访问，由于闭包的存在，使得这类"犯罪"的成本异常低廉。而Rust的所有权系统则巧妙地在编译器就发现了这类错误，因为变量所有权只会同时在一个线程中，也就避免了数据竞争。

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

本文主要从所有权系统和编程范式的角度理解Rust，总的来说，这门语言给我的印象是很不错的。

从系统级编程语言的角度来说，它确实兼顾了安全和高效，这中间是Rust编译器在"负重前行"，其它语言的编译器更多关注语法正确性，而Rust编译器还会想尽办法分析和保证代码安全性，这也是所有权系统及其相关机制的意义，这些规则前期可能要多适应下，但遵循这些约束能够换来巨大的健壮性和运行效率收益。

从高级编程语言的角度来说，Rust从多种编程范式(过程式、函数式、面向对象、泛型、元编程等)中取其精华去其糟粕，具有强大的灵活性和抽象能力，在图形、音视频、Web/应用前后端等各个应用领域全面发力，未来可期。

由于对Rust缺乏实践，本文更多还是提炼汇总，如果有合适的应用场景，倒是很愿意用Rust实践下，增强理解。
