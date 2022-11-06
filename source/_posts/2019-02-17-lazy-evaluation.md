---
title: 函数式中的延迟计算及惰性求值
layout: post
categories: programing
tags: programing
---

本文谈谈在函数式编程中的延迟计算，惰性求值等技术及其应用。

## Racket

本文将以 Racket 为例，以下是 Racket 的概要:

1. 更广泛的函数概念: 什么 if define + myfunc 等，统统都是函数
2. 前缀表达式: 同 Lisp, Scheme 等语言一样，Racket 使用前缀表达式，如(myfunc 1 2)，(+ 1 2 3)等
3. 支持可变性: 可修改变量值(不建议)，如 (set! x 2)，并且支持修改 Pair，Map 的指定元素

其它关于 Racket 的具体语法和 API 细节请参考[Raccket 中文文档](https://github.com/OnRoadZy/RacketGuideInChinese)。

## Delay Evaluation

Delay Evaluation 意为延迟计算，即表达式只在必要时才求值，而非被赋给某个变量时立即求值。

<!--more-->

要理解延迟计算，我们先看一个小例子:

```
(define (my-if e1 e2 e3)
    (if e1 e2 e3))
    
(define (factorial x)
  (my-if (= x 0)
         1
         (* x (factorial (- x 1)))))  
```

上面的代码实现了一个 `my-if` 函数，它的作用和 if 一样，以及一个计算阶乘的函数 factorial，只不过使用 `my-if` 替代了 if，如果你运行`(factorial 1)`，将陷入死循环，因为在对 `(factorial 1)` 求值时，将会对`(my-if e1 e2 e3)`求值，而在大多数语言包括 Racket 中，实参表达式是在被传入时即会被求值的，因为 e3 中递归调用了 factorial，然后又会对 `(factorial 0)` 求值，如此递归，并且没有终止，因为要对 factorial 函数求值完成后，`my-if` 表达式才能求值，才能终止递归。而 if 则不同，它只有在 x 不为 0 时才会递归对 `(factorial (- x 1))` 求值，不会形成无限递归。

要解决这种情况，我们需要让 `my-if` 在求值时，先不对 `(factorial (- x 1))` 求值，等到 `my-if` 判断 e1 为 false(x 不等于 0)，即确实需要对e3求值时才求值，这就是延迟计算，因此我们需要将以上函数改成这样:

```
(define (my-if e1 e2 e3)
    (if e1 (e2) (e3)))
    
(define (factorial x)
  (my-if (= x 0)
         (lambda () 1)
         (lambda () (* x (factorial (- x 1))))))
```

`my-if` 的参数 e2, e3 只是个未被求值的表达式，通过不带参的匿名函数代入，由于函数只会在被调用的时候才会被求值，从而达到延迟计算的目的。这种通过函数传入表达式本身而不是具体值从而达成延迟计算的方式有个专业的计算机术语叫做[Thunk](https://en.wikipedia.org/wiki/Thunk)(形实转换程序)。Thunk 的关键点在于将裸表达式 `e` (会被立即求值)包装为 p: `(lambda() e)`(将表达式包裹在函数中)，并且在使用时调用 p: `(p)`(在需要时才计算表达式求值)。

有了 Thunk 之后，我们可以在某些情况下延迟函数参数的计算，但在另一些情况下，Thunk 反而会导致更多的计算:

```
; 未使用 Thunk, 通过累加的方式计算 n*e，n >= 1
 (define (my-mult1 e n)
  (cond [(= n 0) 0]
       [(= n 1) e]
       [#t (+ e (my-mult2 e (- n 1)))]))
      
; 使用 Thunk, 通过累加的方式计算 n*(e)，n >= 1
 (define (my-mult2 e n)
  (cond [(= n 0) 0]
       [(= n 1) (e)]
       [#t (+ (e) (my-mult2 e (- n 1)))]))
```

`my-mult1` 和 `my-mult2` 实现相同的功能，除了一个是直接传入表达式而另一个传入的是 Thunk，在这种情况下，`my-mult1` 只会计算表达式一次(即使 n==0)，而 `my-mult2` 会计算表达式 n 次(n==0时无需计算)。在 n 很大时，`my-mult1` 将明显优于 `my-mult2`。

因此实际上我们需要的是这样一种机制，它兼具 `my-mult1`(不会重复计算表达式) 和 `my-mult2`(延迟求值，表达式可能无需计算)的优点:

1. 延迟计算
2. 避免重复计算，比如计算过一次之后就记住它的值

这种机制被称为*惰性求值(Lazy Evaluation)*，天生具备惰性求值特性的语言称为*惰性语言(Lazy Language)*(如 Haskell)。。

## Lazy Evaluation

下面我们来尝试在 Racket 中自己实现惰性求值，延迟计算的 Thunk 技术前面已经介绍过，现在我们来考虑如何记住表达式的值，避免重复计算，一种可选的方案是在表达式上再封装一层，其中记录了表达式的计算状态和计算值，我们可以用一个 Pair 来记录，其第一个字段为表达式是否已经被计算(bool 值)，另一个字段为计算结果或Thunk。

在 Racket 中，Pair 分为可变和不可变两种，分别用 cons 和 mcons 构建，在这里，我们应该使用可变 Pair:

```
; 在 thunk 上再一次封装，加上计算状态
(define (my-delay thunk)
  (mcons #f thunk)) ; 将 thunk 封到 Pair 中，并初始化为未被计算(false)

; 计算 thunk，如果已经被计算，则不会再被计算  
(define (my-force p)
  (if (mcar p) ; 查看表达式是否已经被计算
    (mcdr p)   ; 如果已经被计算，则直接返回 Pair 第二个元素 
    (begin (set-mcar! p #t) ; 如果未被计算，则标记为已计算
          (set-mcdr! p ((mcdr p))) ; 计算 Pair 中的表达式(第二个元素)，执行计算，并将计算结果存为Pair第二个元素
          (mcdr p)))) ; 直接返回 Pair 中第二个元素
```

上面代码实现了两个函数 my-delay 和 my-force，与延迟计算中的`(lambda () e)` 和 `(e)` 类似，我们将表达式 e 变换为了p: `(my-delay (lambda () e))` 和 `(my-force p)`。现在我们可以用 my-delay 和 my-force 来优化 `my-mult2`，`my-mult2`无需任何修改，我们只需修改调用处:

```
; 以下两个函数调用均为计算 (+ (factorial 2) (factorial 2))，结果均为 4
; 延迟调用版本，会计算(factorial 2) 两次
> (my-mult2 (lambda () (factorial 2)) 2)
> 4
; 惰性求值版本(延迟调用+避免重复计算)，会计算(factorial 2) 一次
> (my-mult2 (let ([p (my-delay (lambda () (factorial 2)))])
              (lambda () (my-force p))) 2)
> 4              
```

惰性求值版本在最好情况下不会对表达式进行计算(n==0)，最差情况下也只会计算一次，兼具`my-mult1` 和 `my-mult2`的优点。

## Stream

延迟计算除了优化作用外，另一个应用就是 Stream(流)，Stream 是指一个无限大小的值队列，比如:

1. 用户输入事件: 如鼠标点击
2. Unix Pipes: `cmd1 | cmd2`，cmd2 从 cmd1 获取的处理结果，可能就是一个 Stream，如 cmd1为`tail -f ...`
3. 数学计算中，可能需要一个无穷大的数队列(如斐波那契队列)，消费者可以不断地获取下一个数进行处理

因此生产者无法事先穷举表示出来，另一方面，用多少数据通常由消费者决定，我们也就没有必要事先计算出所有的数据。因此，可以通过延迟计算实现 Stream。

现在我们尝试用 Thunk 实现两个简单的整数队列:

```
; 实现一个全是1的Stream [1,1,1,...]
; 正确版本
(define ones (lambda () (cons 1 ones)))
; 错误版本1: 编译错误，在 ones-bad1 定义中使用了 ones-bad1定义
; (define ones-bad1 (cons 1 ones-bad1))
; 错误版本2: 无限递归，ones-bad2的求值需要对ones-bad2求值，没有终止
; (define ones-bad2 (lambda () (cons 1 (ones-bad2))))

; 实现一个递增的自然数Stream [1,2,3,...]
; 辅助函数，f(x)，返回Pair: (x, Thunk-of-f(x+1))
(define (f x) (cons x (lambda () (f (+ x 1)))))
; 将 f(1) 封装为Thunk
(define nats (lambda () (f 1)))
```

以下是使用示例:

```
> (nats) ; 调用 nats 将返回一个 Pair，第一个元素是当前获取到的值，第二个元素是一个新的 Stream
'(1 . #<procedure:...era/racket/a.rkt:29:22>)
> (car (nats)) ; 取出第一个自然数
1
> (car ((cdr (nats)))) ; 取出第二个自然数
2
```


上面实现了两个Thunk, ones 和 nats，前者没有内部状态(每次返回值是一样的)，后者有内部状态。那么 nats 是如何保存状态的呢？函数式也可以有内部状态？不，函数式中的函数当然没有内部状态，状态是通过辅助函数 f 的参数来传递的，第 n 次调用 nats 会返回一个新的 f(n+1) Thunk，对外表现为调用 Stream 返回的 Pair 的第二个元素始终都是个Thunk(无参匿名函数)，但其实 Stream 每次返回的 Thunk 都是不一样的(封装了不同的 f 调用)，这也是为什么 Stream 每次都要返回 Thunk 的原因。

如果是非函数式语言如 C，我们可以很方便地实现一个 `Counter()` 函数，通过静态局部变量来保存当前计数，而无需返回一个新的函数。但同时也失去了函数式的诸多好处，如延迟计算，因为程序员和编译器都很难判断`Counter()`是否有副作用(或者以后会改为具备副作用，比如修改了全局变量)，也就不能保证延迟计算是无痛的。

## Memoization

我最初接触[Memoization](https://zh.wikipedia.org/wiki/%E8%AE%B0%E5%BF%86%E5%8C%96)是在动态规划中，指的是如果一个问题具有最优子结构，并且会对多个子问题重复计算，那么我们应该将子问题的结果保存下来(Memoization)，避免对子问题的重复计算。Memoization 适用于很多使用递归并且会有大量重复计算的问题，比如背包问题，找零钱问题，最短路径问题，斐波那契数列问题等等。

这里我们以最简单的斐波那契数列为例，以下是几个求第 n 个斐波那契数的函数:

```
; fib1: 原始方案，直接自上而下递归
(define (fib1 x)
  (if (or (= x 1) (= x 2))
      1
      (+ (fib1 (- x 1))
         (fib1 (- x 2)))))

; fib2: 自下而上递归，避免子问题重复计算
; 将子问题的计算结果通过函数参数传到上层问题，思路类似于迭代
(define (fib2 x)
  (letrec ([f (lambda (acc1 acc2 y)
                (if (= y x)
                    (+ acc1 acc2)
                    (f (+ acc1 acc2) acc1 (+ y 1))))])
    (if (or (= x 1) (= x 2))
        1
        (f 1 1 3))))

; fib3: 自上而下递归，使用我们前面的 my-delay my-force 技术
(define (fib3 x)
  (my-delay (lambda () (if (or (= x 1) (= x 2))
      1
      (+ (my-force (fib3 (- x 1)))
         (my-force (fib3 (- x 2))))))))

; fib4: 自上而下递归，使用 Memoization 技术
; 用一个 map 保存计算过的子问题结果
(define fib4
  (let ((memo (make-hash '((0 . 0) (1 . 1))))) ; 创建 map，key 为fib4函数参数 n
    (lambda (n)
      (unless (hash-has-key? memo n) ; 查看 memo map，是否已经计算过该子问题
        (hash-set! memo n (+ (fib4 (- n 1)) (fib4 (- n 2))))) ; 如果没有计算过，则计算，并将结果存入 memo map
      (hash-ref memo n)))) ; 此时肯定已经计算过了，直接取出 memo map 中的结果

; 测试代码执行时间
> (time (fib1 35))
cpu time: 518 real time: 519 gc time: 0
9227465
> (time (fib2 35))
cpu time: 0 real time: 0 gc time: 0
9227465
> (time (my-force(fib3 35)))
cpu time: 2784 real time: 2957 gc time: 912
9227465
> (time (fib4 35))
cpu time: 0 real time: 0 gc time: 0
9227465
```

现在我们来分析测试结果，fib1 和 fib2 的结果没什么意外，毕竟原始的 fib1 函数是一个指数增长的函数，其复杂度为即O(2^n)，而 fib2 通过自下而上求解，用迭代的思路将其优化为 O(n)，提升效果明显。 

fib3 的运行时间有些意外，它竟然比原始的 fib1 还慢了数倍，my-delay 和 my-force 不是只会计算一次结果么？需要注意的是，我们的 fib3 虽然用了 my-delay，但是却没有真正实现避免重复计算，因为我们没有将 `my-delay(fib(x))` 作为所有递归 `fib(x)` 的替代， 而是在每次调用 `fib(x)` 是生成了一个新的my-delay，已有的计算过的 `my-delay(fib(x))` 并没有保存下来，因此仍然会递归再次求解，再加上 my-delay 和 my-force 本身的开销，也就出现了比 fib1 还慢的结果。严格意义上说，fib3 不只是没有避免重复计算，就连延迟计算的优势也没有发挥出来，因为 my-force 总是在封装返回后立即被 my-force 使用。

fib4 通过 Memoization 技术来避免重复计算，性能表现和 fib2 一样优秀，当然，实际上会比 fib2 慢一些，毕竟多了 hash map 存取。但 fib2 本身是基于斐波那契数列特性的优化，对类似找零钱问题，背包问题等，自下而上的递归就不那么好用了，并且也会传递更多的计算上下文，而 Memoization 贵在它是一种更通用，甚至可以做进编译器的优化方案，具备更好的可读性和扩展性。

Memoization 和惰性求值虽然都可以避免重复计算，但惰性求值是依靠将单个表达式封装后的结果(如 my-delay 的 Pair)到处传递来实现的，Memoization 则考虑在表达式外部的上下文(闭包)中，对计算结果进行保存，因此对复杂的问题来说，实现 Memoization 要比惰性求值更简单直观。

## Lazy Language

我们前面讨论的惰性求值都是以在 Racket 中手动实现来阐述的，而事实上像柯里化一样，某些语言可能内置惰性求值，这类语言被称为惰性语言。最出名的惰性语言如 Haskell，在 Haskell 中你可以用 `[1..]` 来表示1到无穷大的列表，当你需要时，可以通过`[1..] !! 999`取出其中第1000个元素(值即为1000)。另外，假如我有一个列表 xs，doubleMe 会将 xs 中的元素`*2` ，那么在Haskell中，`doubleMe(doubleMe(doubleMe(xs)))` 只会遍历列表一次。

另外，Racket 语言虽然不是天生的惰性语言，和 Scheme 一样，它也通过内置 delay 和 force 来支持手动惰性，并且使用比my-delay 更简单快捷:

```
> (define laz (delay (fib1 10))) ; delay 后面只需跟表达式即可，无需是个 Thunk
> laz
#<promise:laz>
> (promise? laz) ; 判断 laz 是否是个 promise，即惰性表达式
#t
> (force laz)
55
```

有意思的是，Racket 将 delay 封装后的惰性表达式(类似my-delay返回的 Pair) 称作 promise，我猜它的意思是，我在创建时不会立即求值，但是我给你个"承诺"，当你需要值时我会计算给你，并且内部保证不会重复计算。[JS 异步编程](http://wudaijun.com/2018/07/javascript-async-programing/)中，用于保存异步执行结果，状态以及回调的结构体也叫 Promise，它的意思是: 你发起一个异步调用，我承诺将来一定会给出个结果(成功/失败)，你挂载上去的回调函数我也会在将来结果揭晓后进行调用。这两个 Promise 的"命名撞衫"非常有意思，它们虽然出自不同的语言，用于不同的领域，但都有延迟意思，只不过本文的 delay 由创建者决定何时取值，而 JS 中的 Promise 由异步过程决定何时返回值。

## At Last

前面的讨论各种技术本质上是为了延迟计算和避免重复计算，这些技术绝大部分(除了 Memoization) 都只应用在函数式语言中，因为只有函数式语言才能更好地确保函数没有副作用，从而确保函数求值的时机和次数对整个计算的正确性不会有影响，更进一步甚至将这些技术做到了语言内部。而对于过程式来说，由于其本身的可变性和副作用，这方面的路还很长。本文用 Racket 实现的 my-delay 和 Memozation 技术都用到了可变语义，因为我们需要这样一个上下文来辅助我们优化计算，使用了这些可变语义的函数从计算语义上来说仍然是"无副作用的"(PS: 严格意义上的无副作用不存在，CPU，内存都是有状态的全局上下文)。这主要是指，虽然函数有了自己的状态(通过闭包实现)，但对函数使用者来说，从计算结果上来讲并无区别。

换句话说，过程式羡慕函数式的无状态无副作用带来的优化空间和健壮性，而函数式有时候也未尝不羡慕过程式可变性带来的灵活性和便利。