---
title: go module 来了
layout: post
categories: go
tags: go
---

go module 是 go1.11 引入的新概念，为 go  当前饱受诟病的 GOPATH 和依赖管理提供了更好的解决方案。在理解 go module 之前，先回顾下当前 Go 的项目结构和依赖管理都有什么问题:

1.GOPATH

GOPATH一定程度上简化了项目构建，但是给了开发者过多的限制，你的项目必须位于 GOPATH 下，否则编译器找到它，想要使用你自己的项目组织结构，要么你需要为每个项目设置一个 GOPATH，要么使用软链接来实现。大多数 go 新手都会纠结于应该使用一个 GOPATH 还是为每个项目创建一个 GOPATH，还是为所有依赖创建一个 GOPATH，受到一堆限制，却并没有得到便利。

<!--more-->

2.依赖管理

依赖管理？对不起，go 没有依赖管理，go1.11之前所有的[依赖管理方案](https://github.com/golang/go/wiki/PackageManagementTools)都是基于 Go 没有依赖管理这个事实之上的一些变通方案(tricks)。据说这个起因要追溯到 Google 内部，其使用巨大的单个仓库来维护项目代码，没有第三方仓库，也就不需要版本控制。go1.5开始关于依赖管理的最大变化就是 vendor 机制，它鼓励你将所有的依赖作为项目代码的一部分去管理，其实也是 "Google 风格" 的延续，只不过你可以选择使用某个版本的依赖，然后将其"冻结"到项目的 vendor 目录下，这一方面保证了可重现的构建，另一方面，解决了不同项目使用同一个依赖的不同版本的问题，但单片仓库和版本管理的问题仍然存在，依赖缺乏明确的版本定义，如果没有指定要使用的依赖版本，那么将是依赖这个 branch，然后再通过 hash 来校验，如果版本冲突了，你很难定位版本，并且解决冲突。


#### go module 初试

一个 module 是指一组相关的 package，通常对应于一个 git 仓库，module 是代码交换和版本管理的基本单位，即 module 的依赖也是一个 module，go 命令现在直接支持 module 相关操作。由于现在还是试验阶段，go1.11 通过一个临时的环境变量 GO111MODULE 来控制启动和停用go module，该环境变量有三个值:

    auto: 默认值，即在 GOPATH 目录下，使用传统的 GOPATH 和 vendor 来查找依赖，在非 GOPATH 下则使用 go module 
    on: module-aware mode，在任何目录都启用 go module，使用 go module 来控制依赖管理，在这种模式下，GOPATH 不再作为构建时的imports路径，只是作为存放下载的依赖($GOPATH/pkg/mod)和安装二进制文件的目录($GOPATH/bin，如果 GOBIN 未设置)
    off: GOPATH mode，停用 go module，和 go1.11之前一样，使用 GOPATH 和 vendor 来定位依赖，并使用 dep 之类的依赖版本管理工具来冻结依赖
    

在介绍`go mod`命令前，我们先简单看下 go module 长啥样。假设我们设置`GO111MODULE=on`，现在开始对 GOPATH/src/ngs 库(之前由 dep 管理依赖)进行移植。

执行 `go mod init ngs`，会在 ngs 根目录下生成一个 go.mod 文件，该文件和 dep 的 Gopkg.toml 文件一样，用于记录当前module所依赖的版本，对新项目而言，只会生成一行`module packagename`，如果是已有项目，go module 会自动从 Gopkg.toml 等已有的依赖版本信息中导入生成依赖版本信息，比如以下是项目的 Gopkg.toml 文件内容:

    [[constraint]]
      branch = "master"
      name = "github.com/yuin/gopher-lua"

    [[constraint]]
      name = "google.golang.org/grpc"
      version = "1.12.2"
      
    [[constraint]]
      branch = "v2"
      name = "gopkg.in/mgo.v2"
      
对应生成的 go.mod 为:

    module ngs

    require (
        github.com/yuin/gopher-lua v0.0.0-20180611022520-ca850f594eaa
        google.golang.org/grpc v1.12.2
        gopkg.in/mgo.v2 v2.0.0-20160818020120-3f83fa500528
    )
  
  
注意，go.mod 中每个依赖都有严格的版本信息，这也是不同于之前 dep 等工具的地方，比如在 Gopkg.toml 中， gopher-lua 使用的 master 分支，go.mod 中，则会为依赖自动生成一个伪版本号`v0.0.0-20180611022520-ca850f594eaa`，你可以通过命令来手动升级它。这种自动冻结的特性不仅保证了可重现的构建，并且版本冲突的显式清晰的，你可以很直观地在 go.md 中看到冲突的原因，那个版本更新或者更稳定。

>> go module 使用[语义化版本(semantic versions)](https://semver.org/lang/zh-CN/)标准来作为描述依赖版本的格式，这样版号可以通过直接比较来决定那个版本更新。版号通常通过 git tag 来标注。对于没有通过 tag 打版本号的提交，go module 使用伪版本号(pseudo-version) 来标记，伪版号的格式为 [之前最近一次的版本号]-[提交时间]-[提交哈希值]，比如 v0.0.0-20180611022520-ca850f594eaa，这样伪版本号也可以用于比较，伪版本号不需要手动输入，会由 go module 在冻结版本时自动生成。

现在我们的 ngs 已经成为了一个 go module，现在我们为其添加一个依赖: `go get github.com/gorilla/websocket@v1.3.0`，可以看到 go.mod 中多出一行: `github.com/gorilla/websocket v1.3.0`，但 GOPATH 和 vendor 下都没有看到 websocket，其被下载到了 `$GOPATH/pkg/mod/github.com/gorilla/websocket@1.3.0`目录，在 module-aware mode 下，`$GOPATH/pkg/mod` 目录会作为依赖被下载后的缓存目录，这里的依赖会将版本作为路径的一部分(与之前依赖管理本质区别)。我们可以以下方式对其进行升级/维护:

    go get -u 将会升级到最新的次要版本或者修订版本(x.y.z, z是修订版本号， y是次要版本号)
    go get -u=patch 将会升级到最新的修订版本
    go get package@version 将会升级到指定的版本号version

当然，我们这里在代码中并没有用到 websocket，可以运行 `go mod tidy` 来新增被漏掉的，或者删除多余的依赖，运行之后 go.mod 恢复如初。

可以看到，在 go module 模式下，我们不再需要 vendor 目录来保证可重现的构建，而是可以通过一个 go.mod 来基于每个依赖的精确管理号，并通过`go get` 等命令即可管理依赖升级/降级等。当然，如果你仍然想保留 vendor 目录，可以通过 `go mod vendor` 命令将项目用到的依赖拷贝到 vendor 目录下(为了保证兼容性，vendor 目录下的依赖目录名是不包含版本号的)。除了 go.mod 外，go module 还会生成一个 go.sum 来记录每个依赖版本的哈希值，用于校验版本正确性。通常情况下，你不需要手动编辑 go.mod，通过 `go get`，`go mod` 等命令来完成依赖管理的同时，go.mod 也会自动更新。

以下是 go module 相关的一些命令:

    go mod init: 初始化 go module
    go mod download: 下载 go.mod 中的依赖到本地 Cache ($GOPATH/pkg/mod 下)
    go mod vendor: 将项目依赖拷贝到 vendor 下
    go mod tidy: 相当于 dep ensure，增加缺失的依赖(module)，丢掉没用的依赖(module)
    go mod verify: 校验依赖
    go mod edit: 编辑依赖，通过命令行手动升级或获取依赖
    go list -m all: 列出当前项目(main module)的构建列表
    
go 的任何构建命令都可以判断依赖缺失并决定是否需要添加到 go.mod，比如如果你在你的项目代码没有依赖redis，然后你在代码中加入`import "github.com/go-redis/redis"` ，然后直接执行go build，将会导致 redis 被发现为缺失依赖，被自动添加进 go.mod 中。你可以通过 `-mod` 构建选项来控制这一行为，该选项有如下几个值:

- `-mod=readonly`: 构建过程中，如果发现需要更改 go.mod，将会构建失败，即 go.mod 在构建过程中为只读的。 注: `go get` 命令不受此限制，`go mod` 命令不接受 -mod 选项
- `-mod=vendor`: go 命令假设所有的依赖都存放在 vendor 目录下，并且忽略 go.mod 中的依赖描述
    
大概了解了 go module 之后，我们回顾它是如何解决我们前面提出的两个问题的:

1. go module 通过 go.mod 来定位当前 module(也叫做 main module) 的 root path，即从当前执行命令的目录向上查找，直到找到go.mod，而不再通过 `$GOPATH/src` 来定位项目。
2. go module 对每个依赖生成严格的版本号，并且将同一个依赖的不同版本以目录区分开来，以 $GOPATH/pkg/mod 作为不同 module 共享依赖的路径。

现在 go module 已经有一些依赖版本管理的雏形了，离 [Erlang Rebar3](http://wudaijun.com/2016/09/erlang-rebar3/) 这种成熟的依赖管理虽然还有一些距离，但确实实用性，易用性都要好很多。