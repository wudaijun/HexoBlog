---
title: Go 常用命令
layout: post
tags: go
categories: go
---

### 环境管理

- Go版本管理: [gvm](https://github.com/moovweb/gvm)(go version manager)
- GOPATH管理: [gvp](https://github.com/pote/gvp)(go version package)
- 依赖版本管理: [gpm](https://github.com/pote/gpm)(go package manager)

### go build

用于编译指定的源码文件或代码包以及它们的依赖包。

> import导入路径中的最后一个元素是路径名而不是包名，路径名可以和包名不一样，但同一个目录只能定义一个包(包对应的_test测试包除外)

<!--more-->

编译包:

	# 当前路径方式
	cd src/foo && go build
	# 包导入路径方式
	go build foo bar
	# 本地代码包路径方式
	go build ./src/foo
	
go build 在编译只包含库源码文件的代码包时，只做检查性的编译，不会输出任何结果文件。如果编译的是main包，则会将编译结果放到执行命令的目录下。

编译源码文件:

	# 指定源码文件使用文件路径
	# 指定的多个源码文件必须属于同一个目录(包)
	go build src/foo/foo1.go src/foo/foo2.go

当执行以上编译时，编译命令在分析参数的时候如果发现第一个参数是Go源码文件而不是代码包时，会在内部生成一个名为“command-line-arguments”的虚拟代码包。也就是当前的foo1.go foo2.go属于"command-line-arguments"包，而不是foo包，因此除了指定的源码文件和它们所依赖的包，其它文件(如foo3.go)不会被编译。

同样，对于库源码文件，build不会输出任何结果文件。对于main包的源文件，go build要求有且只能有一个main函数声明，并将生成结果(与指定的第一个源码文件同名)放在执行该命令的当前目录下。

构建与`go build`之上的其它命令(如`go run`，`go install`)，在编译包或源码文件时，过程和特性是一样的。

常用选项:

|  选项 | 描述 |
| ------| ------ |
| -v | 打印出那些被编译的代码包的名字。 |
| -n | 打印编译期间所用到的其它命令，但是并不真正执行它们。|
| -x | 打印编译期间所用到的其它命令。注意它与-n标记的区别。|
| -a | 强行对所有涉及到的代码包（包含标准库中的代码包）进行重新构建，即使它们已经是最新的了。|
| -work | 打印出编译时生成的临时工作目录的路径，并在编译结束时保留它。在默认情况下，编译结束时会删除该目录。|

### go run

go run编译(通过go build)并运行命令源码文件(main package)，查看过程:

	go run -x -work src/main/main.go
	# build 临时目录
	WORK=/var/folders/n5/j8y6skrx1xn3_ls64gl1lrsmmp53rv/T/go-build979313546
	# main.go依赖foo包  先编译foo包
	mkdir -p $WORK/foo/_obj/
	mkdir -p $WORK/
	cd /Users/wudaijun/Work/test/src/foo
	/usr/local/Cellar/go/1.7/libexec/pkg/tool/darwin_amd64/compile -o $WORK/foo.a -trimpath $WORK -p foo -complete -buildid cd61b5a9f3c8eba0f3088adca894fc9bf695826b -D _/Users/wudaijun/Work/test/src/foo -I $WORK -pack ./foo.go
	# 在虚拟包 command-line-arguments 中编译 main.go
	mkdir -p $WORK/command-line-arguments/_obj/
	mkdir -p $WORK/command-line-arguments/_obj/exe/
	cd /Users/wudaijun/Work/test/src/main
	/usr/local/Cellar/go/1.7/libexec/pkg/tool/darwin_amd64/compile -o $WORK/command-line-arguments.a -trimpath $WORK -p main -complete -buildid 9131b7dd9f64a85bb423da7f8a7d408c089a23e8 -D _/Users/wudaijun/Work/test/src/main -I $WORK -I /Users/wudaijun/Work/test/pkg/darwin_amd64 -pack ./main.go
	# 链接
	cd .
	/usr/local/Cellar/go/1.7/libexec/pkg/tool/darwin_amd64/link -o $WORK/command-line-arguments/_obj/exe/main -L $WORK -L /Users/wudaijun/Work/test/pkg/darwin_amd64 -w -extld=clang -buildmode=exe -buildid=9131b7dd9f64a85bb423da7f8a7d408c089a23e8 $WORK/command-line-arguments.a
	# 从临时目录运行可执行文件
	$WORK/command-line-arguments/_obj/exe/main
	Call Foo()

可看到`go run`的执行结果都在WORK临时目录中完成，由于使用了`-work`选项，因此WORK目录会在`go run`执行完成后保留。`go run`只接受命令源文件而不接收包路径作为参数，并且不会在当前目录生成任何文件。

### go install

`go install`只比`go build`多干一件事：安装编译后的结果文件到指定目录。

### go test

`go test`编译指定包或源文件，并执行所在包对应的测试用例。一个符合规范的测试文件指：

- 文件名必须是_test.go结尾的，这样在执行go test的时候才会执行到相应的代码
- 你必须import testing这个包
- 所有的测试用例函数必须是Test开头
- 测试用例会按照源代码中写的顺序依次执行
- 测试函数TestXxx()的参数是testing.T，我们可以使用该类型来记录错误或者是测试状态
- 测试格式：`func TestXxx (t *testing.T)`,Xxx部分可以为任意的字母数字的组合，但是- - 首字母不能是小写字母[a-z]，例如Testintdiv是错误的函数名
- 函数中通过调用testing.T的Error, Errorf, FailNow, Fatal, FatalIf方法，说明测试不通过，调用Log方法用来记录测试的信息

测试分为包内测试和包外测试，即测试源码文件可于被测试源码文件位于同一个包(目录)，或者测试源码文件声明的包名可以是被测试包名+"_test"后缀。

另外，可以用一些插件来辅助编写测试用例，如[gotest](https://github.com/cweill/gotests/)(支持sublime, emacs, vim)。

