---
title: Go 笔记(2) 顺序编程
tags: go
categories: go
layout: post

---

## 不定参数&多返回值

不定参数只能是最后一个参数，它实际上是数组切片参数的语法糖：

	// 语法糖 相当于 func myfunc(args []interface{})
	func myfunc(args ...interface{}){
		for _, arg := range args {        fmt.Println(arg)
	}
	
	// 参数会被打包为 []{arg1,arg2,arg3}
	myfunc(arg1,arg2,arg3)
	// 要完成可变参数的完美传递 需要用...将Slice打散
	func myfunc2(args ...interface{})
		// 此时args已经是Slice 如果不打散将作为一个参数 不能完美传递
		myfunc(args)
		// 编译器在此处有优化 最终会直接将args传入 不会打散再打包 参考: http://www.jianshu.com/p/94710d8ab691
		myfunc(args...) 
	end
	
	
	
多返回值为函数提供了更大的便利性，无需传引用或者专门构造返回值结构体，并且在错误处理方面也更简便，在前面的示例代码中已经初尝甜头。

	// 定义多返回值函数时，可以为返回值指定名字
	func (file *File) Read(b []byte) (n int, err Error){
		// n和err在函数开始时，被自动初始化为空
		...
		... n = xxx
		...
		... err = xxx
		...
		// 直接执行return时，将返回n和err变量的值
		return
	}
	
多返回值的在Plan9 C编译器上的实现是由调用者在其栈上分配n和err的内存，由被调用方修改调用方栈上的n和err的值：

![](/assets/image/go/go-func-call.png "")
	
## 匿名函数&闭包

匿名函数允许函数像变量一样被定义，传递，和使用。Go语言支持随时在代码里定义匿名函数。

	// 赋给变量
	F = func (a, b int) int {
		return a + b
	}
	F(1,2)
	// 直接执行
	func (a, b int) int {
		return a + b
	}(1,2)

                                                                                                                                   
### 1. 闭包的概念

闭包是可以包含自由(未绑定到特定对象)变量的代码块，这些变量不在这个代码块内或者任何全局上下文中定义，而是在定义代码块的环境中定义。要执行的代码块(由于自由变量包含在代码块中，所以这些自由变量以及它们所引用的对象没有被释放)为自由变量提供绑定的计算环境(作用域)。

### 2. 闭包的价值

闭包的价值在于可以作为函数对象或者匿名函数，对于类型系统而言，这意味着不仅要表示数据还要表示代码。支持闭包的多数语言都将函数作为第一类对象，就是说这些函数可以存储到变量中作为参数传递给其它函数，最重要的是能够被函数动态创建和返回。

### 3. Go语言中的闭包

Go语言中的闭包同样也会引用到函数外的变量，闭包的实现确保只要闭包还被使用，那么闭包引用的变量会一直存在。 

```go                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  
package main
import "fmt"
	
func main() {
    var j int = 5
    return_closure := func()(func()) {
        var i int = 10
        return func() {
            i = i + 1
            j = j + 1
            fmt.Printf("i, j: %d, %d\n", i, j)
        }
    }
	
    // 同一个闭包c1 共享所有外部环境 i, j
    c1 := return_closure()
    c1()
    c1()
	
    j = j + 1
    // c1 c2 只共享return_closure作用域之外的变量 j
    // return_closure之内定义的变量i将在每次调用时重新生成，因此只对同一个closure有效
    c2 := return_closure()
    c2()
}
	
// 输出：
i, j: 11, 6
i, j: 12, 7
i, j: 11, 9
```

为了实现闭包:

- Go必须有能力识别闭包函数的引用变量(这里的j)，并将它们分配在堆上而不是栈上(escape analyze技术)
- 用一个闭包结构体保存函数和其引用环境

下面分别阐述这两点：

#### escape analyze

```go
package test
func F() *int {
	var i int
	i = 5
	return &i
}
```

在C语言中，在函数中返回该函数栈上的地址是不被允许的，因为当函数调用完成后函数栈会被回收。Go当然也有函数栈和栈回收的概念，因此它将i分配在堆上而不是栈上，通过`go tool compile -S x.go`查看汇编代码:

    ...
    0x001d 00029 (tmp.go:3) LEAQ    type.int(SB), AX
    0x0024 00036 (tmp.go:3) MOVQ    AX, (SP)
    0x0028 00040 (tmp.go:3) PCDATA  $0, $0
    0x0028 00040 (tmp.go:3) CALL    runtime.newobject(SB) // 相当于new(int)
    0x002d 00045 (tmp.go:3) MOVQ    8(SP), AX // 将i的地址放入AX
    0x0032 00050 (tmp.go:4) MOVQ    $5, (AX) // 将AX存放的内存地址值设为5
    ...

也可通过`-gcflags=-m`选项编译来查看:

	▶ go build --gcflags=-m x.go
	./tmp.go:2: can inline F
	./tmp.go:5: &i escapes to heap
	./tmp.go:3: moved to heap: i

Go编译器依靠escape analyze来识别局部变量的作用范围，来决定变量分配在堆上还是栈上，这与GC技术是相辅相成的。

#### 闭包结构体

闭包结构体在src/cmd/compile/internal/gc/closure.go的walkclosure函数生成，具体实现太过复杂，其注释简要地说明了实现方式：

	// Create closure in the form of a composite literal.
	// supposing the closure captures an int i and a string s
	// and has one float64 argument and no results,
	// the generated code looks like:
	//
	//	clos = &struct{.F uintptr; i *int; s *string}{func.1, &i, &s}
	//
	// The use of the struct provides type information to the garbage
	// collector so that it can walk the closure. We could use (in this case)
	// [3]unsafe.Pointer instead, but that would leave the gc in the dark.
	// The information appears in the binary in the form of type descriptors;
	// the struct is unnamed so that closures in multiple packages with the
	// same struct type can share the descriptor.

比如对我们闭包例子中return_closure生成的闭包，其闭包结构体表示为:

	type.struct{
         .F uintptr//闭包调用的函数指针
         j *int// 指向闭包的上下文数据，c1,c2指向不同的堆地址
    }

### 3. 错误处理

Go的错误处理主要依靠 `panic`，`recover`，`defer`，前两者相当于throw和catch，而defer则是Go又一个让人惊喜的特性，defer确保语句在函数结束(包括异常中断)前执行，更准备地说，**defer语句的执行时机是在返回值赋值之后，函数返回之前**:

```go
func f1() (r int) {
	defer func() {
		r++
	}()
	return 0
}
/* 函数返回: 5
f1等价于:
func f1() (r int){
	r = 0 // 返回值赋值
	func() { 	 // 执行defer函数
		r++
	}()
	return 	 // 函数返回
}
*/

func f2() (r int) {
	t := 5
	defer func() {
		t = t + 5
	}()
	return t
}
/*函数返回: 1
f2等价于:
func f2() (r int) {
	t := 5
	r = t
	func() {
		t = t + 5
	}()
	return
}
*/

func f3() (r int) {
	defer func(r int) {
		r = r + 5
	}(r)
	return 1
}
/*函数返回: 5
f3等价于:
func f3()(r int){
	r = 1
	func(r int) {
		r = r + 5
	}(r) // 值传参 不会影响返回的r的值
	return
}
*/
```

因此，`return x`其实不是"原子操作"，在其中会插入defer函数执行，在[Go官方文档](https://golang.org/ref/spec#Defer_statements)中也提到了这点。

defer还有如下特性：

1. 一个函数可定义多个defer语句
2. 多个defer语句按照先入后出的顺序执行
3. defer表达式中的变量值在defer表达式定义时就已经明确
4. defer表达式可以修改函数中的命名返回值

defer的作用：

1. 简化异常处理(在defetr中recover)，避免异常与控制流程混合(try ... catch ... finally)
2. 在defer中做环境清理和资源释放

更多阅读:

1. 多返回值和闭包: https://www.teakki.com/p/57df64ccda84a0c45338154e
