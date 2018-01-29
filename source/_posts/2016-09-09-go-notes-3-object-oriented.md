---
title: Go 笔记(3) 面向对象和接口
layout: post
categories: go
tags: go

---
   
探索Go类型扩展，类和继承，以及接口的用法和实现。
 
## 面向对象
 
### 1. 类型扩展

```go
package main
	
import "fmt"
	
// 定义了一个新类型:Integer，与int不能直接比较/赋值
type Integer int
	
func (a *Integer) Add(b Integer) Integer{
    return *a + b
}
```
	
### 2. 类和继承
	
在Go中，传统意义上的类相当于是对struct的类型扩展：

```go
package main
	
import "fmt"
	
type Rect struct{
    x, y float64
    w, l float64
}
	
func (r Rect) Area() float64{
    return r.l * r.w
}
	
func main(){
    c := Rect{1,1,4,4}
    fmt.Println(c.Area())
}
```

Go中的继承通过匿名组合实现：

```go
package main
	
import "fmt"
	
type Base struct {
    Name string
}
func (base *Base) Foo() {
    fmt.Println("Base Foo()")
}
func (base *Base) Bar() {
    fmt.Println("Base Bar()")
}
// 以组合的方式 定义继承
// 当derive.xxx在Derive中未找到时，将从基类Base中查找
// 也可通过derive.Base.xxx直接引用基类Base的方法或成员
type Derive struct {
    Base
    age int // 这里的同名成员将覆盖Base中的成员
}
// 重写基类方法
func (d *Derive) Bar() {
    fmt.Println("Derive Bar()")
}
	
func main(){
    b := Base{"name"}
    d := Derive{b, 99}
    d.Foo() // == d.Base.Foo() 语法糖，Foo()函数的接收者只能是Base*
    d.Bar()
    fmt.Println(d.Name,d.age)
}
```

还可以以指针的方式从一个类型派生：

```go
type Derive struct {
    *Base
    ...
}
```

这个时候Derive的初始化需要提供一个Base的指针，它存在的意义类似于C++中的虚基类，Go将C++面向对象中一些”黑盒子”放到了台面上来，如this指针(作为一个特殊的参数显现出来)，虚函数表(Go中不允许派生类指针到基类指针的隐式转换，也就无需虚函数表来实现多态)，虚基类(通过显式基类指针，简洁明了的实现了这一需求)。

Go中没有private public等关键字，要使符号对其它包可见，则需要将该符号定义为大写字母开头。如Base中的Name能被其它引用了Base所在包的代码访问到，而Derive中age则不能。Go中没有类级别的访问控制。

## 接口

接口(interface)是一系列方法声明的组合，同时它本身也是一个类型。

### 1. 非侵入式接口

侵入式接口是指实现类需要明确声明实现了某个接口，目前C++/Java等语言均为侵入式接口。这类接口的缺点是类的实现方需要知道需求方需要的接口，并提前实现这些接口。这给类设计带来很大困难，因为设计类的时候，你并不知道也不应该关心它会被怎么使用。

GO中的接口是非侵入式的，接口与类分离，类只需要关心它应该有那些功能(函数)，而无需操心其应该满足哪些接口(契约)，**一个类只要实现了某个接口的所有函数，那么它就实现了这个接口**：

```go
type IReader interface{
    Read(buf []byte) (n int, err error)
}
	
type IWriter interface{
    Write(buf []byte) (n int, err error)
}
	
type IFile interface{
    Read(buf []byte) (n int, err error)
    Write(buf []byte) (n int, err error)
}
	
type IStream interface{
    Read(buf []byte) (n int, err error)
    Write(buf []byte) (n int, err error)
}
	
type IDevice interface{
    Name() string
}
	
// File定义无需指定实现接口，直接实现其方法即可
// 根据File类的实现，可以得到：
// File类实现了 IDevice接口
// File*类实现了以上所有接口
type File struct {
    // ...
}
func (f *File) Read(buf []byte) (n int, err error){
    // ...
    return
}
func (f *File) Write(buf []byte) (n int, err error){
    // ...
    return
}
func (f File) Name() (s string){
    return
}
```

Go的非侵入式接口的意义：

1. Go语言的标准库，没有复杂的继承树，接口与类之间是平坦的，无需绘制类库的继承树图。
2. 实现类的时候，只需要关心自己应该提供哪些方法(自身功能)，不用再纠结实现哪些接口，接口由使用方按需定义，而不用事前规划。3. 不用为了实现一个接口而导入一个包，因为多引用一个外部的包，就意味着更多的耦合。接口由使用方按自身需求来定义，使用方无需关心是否有其他模块定义过类似的接口。
### 2. 接口赋值

由于接口本身是一种类型，因此它可被赋值。接口赋值分为两种：将对象赋值给接口和将接口赋值给接口：

{% codeblock lang:go %}
	// 1. 将对象赋值给接口
	// 赋值条件：对象需实现该接口
	f := File{}
	// ok
	var I1 IDevice = f
	// ok. Go会根据 func (f File) Name() 自动生成 func (f *file) Name()方法
	var I2 IDevice = &f
	// error. File类实现的IFile接口中，有函数的接收者为File*
	// func (f *File) Read(buf []byte) 不能转化为 func (f File) Read(buf []byte)
	// 因为前者可能在函数中改变f，后者不能，可能造成语义上的不一致
	var I3 IFile = f
	// ok
	var I4 IFile = &f
	// 赋值完成之后 可通过接口直接调用对象方法
	I1.Name()
	
	
	// 2. 将接口赋值给接口
	// 赋值条件：左值接口需是右值接口的子集
	var I5 IReader = I1 // error
	var I6 IFile   = I3 // ok
	var I7 IReader = I3 // ok
{% endcodeblock %}### 3. 接口查询
既然我们可以将对象或者接口赋值给接口，那么也应该有方法能让我们从一个接口查询出其指向对象的类型信息和接口信息：

	f := File{}
	// 接口查询
	var I1 IDevice = f
	// 判断接口I1指向的对象是否实现了IFile接口
	I2, ok := I1.(IFile) // ok = false File类型没有实现IFile接口 File*类型实现了
	    
	// 类型查询
	// 方法一 type assertions
	f2, ok := I1.(File) // ok = true
	// 方法二 type switch
	// X.(type)方法只能用在switch语句中
	switch(I1.(type)){
	    case int:       // 如果I1指向的对象为int
	    case File:      // 如果I1指向的对象为File
	    ...
	}


### 4. 接口组合

前面的IFile接口定义等价于：

```go
type IFile interface{
    IReader
    IWriter
}
```

接口组合可以以更简便的方式复用接口类似于类继承，只不过没有成员变量。

### 5. 空接口

在Go中的任何对象都满足空接口`interface{}`，所以`interface{}`可以指向任何对象：

```go
var v1 interface{} = 1
var v2 interface{} = "abc"
var v3 interface{} = struct{ x int }{1}
var v4 interface{} = v3
```
	
`interface{}`比C++中的`void*`更强大，比`template<>`更灵活，结合接口查询和反射，构建底层代码变得非常容易。

### 6. 反射

简单概括，反射一种检查存储在接口变量(任意类型值)中的“类型-值对”的机制。任何接口变量(包括空接口变量)都包含了其对应的具体类型和值信息：

```go
var f = new(File)
var r IReader
r = f
fmt.Println(reflect.TypeOf(r), reflect.ValueOf(r))
// 输出: *main.File &{}
var w IWriter
w = r.(IWriter)
...
```

IReader接口变量只提供了访问Read方法的能力，但其接口变量仍然保存了有关该值的所有类型信息，因此我们可以通过接口查询得到IWriter接口变量。接口的静态类型决定了哪些方法可以通过接口变量调用，但接口变量本身可能包含更大的方法集。

有了这个机制，我们才能通过反射从任意接口变量，获取对象完整的属性。关于反射的API都在reflect包中提供，通过`reflect.TypeOf`和`reflect.ValueOf`获取接口变量的Type和Value，reflect为Type和Value提供了大量的方法，如`Type.Kind()`,`Value.Interface()`等。

现在我们尝试通过反射修改接口变量的值：


	var x float64 = 3.4	v := reflect.ValueOf(x)
	v.Set(4.1) // error: cannot use 4.1 (type float64) as type reflect.Value in argument to v.Set


由于在`refect.ValueOf(x)`中操作的是x的拷贝，因此实际上v.Set即使能操作成功，也不能如我们预期一般修改x的值。因此reflect提供`Value.CanSet()`来辨别这类不能成功修改的值：

>> CanSet reports whether the value of v can be changed. A Value can be changed only if it is addressable and was not obtained by the use of unexported struct fields. If CanSet returns false, calling Set or any type-specific setter (e.g., SetBool, SetInt) will panic.

我们可以通过*float64类型的反射来修改x的值:

```go
var x float64 = 3.4
p := reflect.ValueOf(&x)
fmt.Println("type of p:", p.Type())
fmt.Println("CanSet of p:" , p.CanSet())
v := p.Elem()
fmt.Println("CanSet of v:" , v.CanSet())
// v的地址是有效的(保存在p.Value()中) 因此可以修改
v.SetFloat(7.1)
fmt.Println(v.Interface())
fmt.Println(x)
// 输出:
// type of p: *float64
// CanSet of p: false
// CanSet of v: true
// 7.1
// 7.1
```

推荐阅读:

1. 接口和反射的好文：https://blog.go-zh.org/laws-of-reflection

