---
title: Docker 学习
layout: post
categories: tool
tags: docker

---

## 一. 理解 Docker

Docker是一种轻量级的虚拟化方案，虚拟化本身可以从两个角度来理解：

- 隔离性：可传统的虚拟机类似，资源隔离(进程，网络，文件系统等)可用于更好地利用物理机。Docker本身虚拟化的开销非常小，这也是它相对于传统虚拟机最大的优势
- 一致性：同样一份虚拟机镜像，可以部署在不同的平台和物理机上，并且内部的环境，文件，配置是一致的，这在当前多样化的平台，日益复杂的配置/部署流程，以及团队和团队间的协作中，有着重要的意义。想象一下，当你用Docker提交代码时，你做的事情跟以前是完全不同的。在以前我们只是把代码提交上去，而在Docker中我们把整台计算机（虚拟机）提交上去。为什么Docker这么火，就是因为它帮助开发者很简单的就让自己的开发环境跟生产环境一致。环境的标准化，意味着目录、路径、配置文件、储存用户名密码的方式、访问权限、域名等种种细节的一致和差异处理的标准化。

<!--more-->

Docker和其它虚拟机或容器技术相比，一是轻量，开销很小，二是发展迅速， 平台兼容性增长很快。虽然Docker的应用场景很多，但都是基于虚拟化和容器技术的这两种特性在特定问题下提出的解决方案。

下面来看看Docker的基本概念：

1. Docker是C/S模式的，包括docker CLI和docker daemon两部分，它们之间通过RESTful API交互，Docker CLI就是我们用的docker命令
2. 镜像(Image)：是一个只读的模板，包含了系统和运行程序，是用于创建容器的一系列指令(Dockfile)，相当于一份虚拟机的磁盘文件。
3. 容器(Container)：当镜像启动后就转化为容器，容器是运行着的镜像，在容器内的修改不会影响镜像，程序的写入操作都保存在容器中。容器可被启动，停止和删除，由docker daemon管理。
4. 仓库(Registry)：Docker镜像可通过公有和私有的仓库来进行共享和分发，仓库是存放和分享镜像文件的场所，功能类似于Github。Docker仓库有免费的[Docker Hub][]和付费的[Docker Store][]。

## 二. Docker 容器

### 1. 容器操作

通常我们都使用docker CLI和docker daemon交互完成docker操作，随着docker日渐完善，docker所提供的功能和参数也更复杂，以下只列举几个常用的。

    docker run [OPTIONS] IMAGE [COMMAND] [ARG...]

从镜像中创建并启动容器，常用Options有：

- `-d`：后台运行
- `-t`：为容器分配一个伪终端，通常于-i一起使用
- `-i`：以交互模式运行容器，如果开了-i而没有指定-t，可以通过管道与容器交互
- `-v`：为容器挂载目录，冒号前为宿主机目录，其后为容器目录
- `-p`： [hip:]hport:cport 端口映射，将容器端口绑定到指定主机端口
- `--name`：为容器命名
- `--link`：链接到其它容器，之后可通过容器ID或容器名访问该容器(只针对bridge)
- `--ip`：指定容器的IP
- `--network`：配置容器的网络
- `--rm`：当容器退出时，删除容器

完整的命令可通过`docker run --help`查看。

例如：

    docker run -it ubuntu:14.04 /bin/bash 

我们就以`ubuntu:14:04`镜像启动了一个容器，并进入到bash交互模式。docker所做的事情为，先在本地查找ubuntu镜像，如果没有，将从[Docker Hub][]中拉取到本地，解析镜像文件，创建容器，并运行`/bin/bash`命令。

每个容器在创建时，docker daemon都会为其生成一个Container ID，容器在运行结束后，为`STOP`状态，可以通过Container ID或容器名字再次启动/停止或删除。可通过`docker ps`来查看容器状态。以下是其它常用的容器管理命令：

    // 查看容器， 默认只显示运行中的容器，-a选项可显示所有容器
    docker ps [OPTIONS]
    // 启动容器
    docker start/stop [OPTIONS] CONTAINER [CONTAINER...]
    // 停止容器
    docker rm CONTAINER
    // 把后台容器调到前端
    docker attach [OPTIONS] CONTAINER
    // 查询容器的详细信息，也可用于镜像
    docker inspect [OPTIONS] CONTAINER/IMAGE
    // 在容器内执行指定命令 如:  docker exec -it CONTAINER bash
    docker exec [OPTIONS] CONTAINER COMMAND [ARG...]
    也可使用第三方工具如nsenter来进入容器


### 2. 容器持久化

镜像是分层存储的，容器也一样，每一个容器以镜像为基础层，在其上构建一个当前容器的可读可写层，容器对文件的所有更改都基于这一层。容器的可读可写层的生命周期与容器一样，当容器消亡时，容器在可读可写层作出的任何更改都将丢失(容器不能对基础镜像作出任何更改)。

有几种方式可以持久化容器作出的更改:

1. 通过`docker commit`以镜像构建的方式将可读可写层提交为一个新的镜像(`docker commit`是`docker run`的逆操作)。这种方式并不推荐，因为手动commit构建的镜像没有Dockerfile说明，是"隐晦"的，使用者并不知道你对镜像作出了何种修改。
2. 在运行容器时指定`docker run -v hostdir:containerdir`来将宿主机上的某个目录挂载到容器的指定目录下，这样容器对该目录作出的所有更改，都直接写入到宿主机上，效率也更高。这通常用于在容器中导出应用日志和数据，这样容器消亡后，日志和数据信息不会丢失。
3. 通过网络IO，将数据持久化到其它地方，如mongo，redis等。

我们在运行容器时，要尽量保证容器的运行是"无状态"的，即容器可以随时被终止而重要数据不会丢失。

## 三. Docker 镜像

### 1. Dockerfile

Docker的镜像通过一个Dockerfile构建，我们可以通过编Dockerfile来创建自定义镜像：

    # 这是注释
    INSTRUCTION args
    
Dockerfile不区分大小写，但惯例是将指令大写，下面介绍几个Dockerfile中常用的指令：

####  FROM

FROM命令必须是Dockerfile的第一条指令，用于指明基础镜像(镜像基础层)：
    
    # 格式：FROM <image>[:<tag>]
    FROM ubuntu:14:04
    FROM erlang
    
#### RUN

在当前镜像的顶层执行命令(比如安装一个软件包)，将执行结果commit到当前镜像层。

RUN有两种格式：

    # shell 格式，相当于 /bin/sh -c <command>
    # 意味着可以访问shell环境变量 如$HOME
    RUN <command>
    # exec 格式，推荐格式，直接执行命令，不会打开shell
    # 这种格式更灵活，强大
    RUN ["executable", "param1", "param2"]
    # 以下两种写法完全等价
    RUN echo "hello"
    RUN ["/bin/sh", "-c", "echo hello"]
    
#### CMD

CMD指令的主要目的是为容器提供默认值，这些默认值可以包含容器执行入口和参数，也可以只指定参数，这种情况下，容器入口由ENTRYPOINT指出。CMD有三种定义方式：

    # exec 格式 指定了执行入口和参数
    # 可被docker run <image>后的参数覆盖
    CMD ["executable","param1","param2"]
    # 当ENTRYPOINT存在时，exec格式退化为默认参数格式
    # 此时CMD提供的参数将被附加到ENTRYPOINT指定的入口上
    # 可被docker run <image>后的参数覆盖
    CMD ["param1", "param2"]
    # shell 格式 这种格式不能为ENTRYPOINT提供默认参数  只能提供默认执行入口
    # 会被ENTRYPOINT或docker run <image>指定的入口覆盖
    CMD command param1 param2
 
Dockerfile中只能有一个CMD命令(如果有多个，只有最后一个生效)，如果CMD要作为ENTRYPOINT的默认参数(即第二种定义方式)，那么CMD和ENTRYPOINT都必须以Json数组的方式指定。

CMD和RUN的区别：RUN在`docker build`构建镜像时执行，将执行结果写入新的镜像层(实际上也是通过容器写入的，详见后面`docker build`命令)，而CMD在`docker run`时执行，执行结果不会写入镜像。

#### ENTRYPOINT
  
ENTRYPOINT用于设置在容器启动时执行命令，ENTRYPOINT有两种定义方式：

    # exec格式 推荐格式
    ENTRYPOINT ["executable", "param1", "param2"]
    # shell格式 以这种方式定义，CMD和docker run提供的参数均不能附加给command命令参数
    ENTRYPOINT command param1 param2

`docker run <image> `后面的参数将会附加在ENTRYPOINT指定的入口上，如：

    FROM ubuntu:14.04
    ENTRYPOINT ["echo", "hello"]
    CMD ["world"]
    
构建镜像`docker build -t echo_img .`，之后如果我们以`docker run --rm echo_img`启动容器，CMD指定的默认参数将附加在ENTRYPOINT的入口上，因此相当于执行`echo hello world`。而如果我们以`docker run --rm echo_img wudaijun`启动容器，此时`docker run`提供的参数将覆盖CMD指定的默认参数，相当于执行`echo hello wudaijun`。

再举个例子：

    FROM ubuntu:14.04
    CMD ["echo", "hello"]
  
由于没有指定ENTRYPOINT，因此CMD指定了默认的执行入口`echo hello`，如果`docker run <image>`未指定任何参数，则执行`echo hello`，否则`docker run <image>`的参数将覆盖CMD指定的执行入口。如果我们再加上Dockerfile中再加一行`ENTRYPOINT ["echo"]`，并且`docker run <image>`后未指定参数，那么将执行`echo echo hello`，输出`echo hello`。

和CMD一样，ENTRYPOINT在Dockerfile中最多只能生效一个，如果定义了多个，只有最后一个生效，在docker run中可通过`docker run --entrypoint`覆盖ENTRYPOINT。

CMD和ENTRYPOINT的区别：CMD和ENTRYPOINT都可用于设置容器执行入口，但CMD会被`docker run <image>`后的参数覆盖；而ENTRYPOINT会将其当成参数附加给其指定的命令（不会对命令覆盖）。另外CMD还可以单独作为ENTRYPOINT的所接命令的可选参数。如果容器是Execuatble的，通常用法是，用ENTRYPOINT定义不常变动的执行入口和参数(exec格式)，用CMD提供额外默认参数(exec格式)，再用`docker run <image>`提供的参数来覆盖CMD。另外，ENTRYPOINT指定的入口也可以是shell script，用于实现更灵活的容器交互。

ENTRYPOINT，CMD，RUN在定义时，均推荐使用Json数组方式。参见[Dockerfile Best Practices][]

#### Exec和Shell区别

前面提到的RUN, CMD, ENTRYPOINT都有两种定义方式: 

	# Exec定义 相当于直接执行: /bin/echo hello
	ENTRYPOINT 	echo hello
	# Shell定义 相当于执行: /bin/sh -c "echo hello"
	ENTRYPOINT 	["echo", "hello"]
	

这两者除了前面所描述的使用方法的不同之外，本质上的区别是前者(Exec)的容器主进程(Pid=1)为命令本身，而后者(Shell)的容器主进程为/bin/sh，这会导致容器接收信号的进程不同，如`docker stop`与`docker kill`会向容器发送SIGTERM和SIGKILL信号，如果使用Shell方式启动命令，命令作为主进程/bin/sh的子进程将不能正确接收到信号。

因此，统一使用Exec是最佳实践，将容器看做一个进程，这个进程即为应用本身。

#### 其它命令

    ENV: 定义环境变量，该变量可被后续其它指令引用，并且在生成的容器中同样有效
    ADD: src dst 将本地文件拷贝到镜像，src可以是文件路径或URL，ADD支持自动解压tar文件
    COPY: 和ADD类似，但不支持URL并且不能自动解压
    EXPOSE: port, 指定容器在运行时监听的端口
    WORKDIR: path, 指定容器的工作目录(启动之后的当前目录)
    VOLUME: [path], 在容器中设置一个挂载点，用于挂载宿主机或其它容器的目录 

关于Dockerfile的语法参考[Dockerfile Reference][]。

### 2. docker build 原理

`docker build`的核心机制包括`docker commit`和`build cache`两部分。

#### docker commit

写好Dockerfile之后，通过`docker build`即可构建镜像：

    docker build -t 镜像名[:tag]  Dockerfile所在目录或URL

`docker build`将按照指令顺序来逐层构建镜像，每一条指令的执行结果将会commit为一个新的镜像层，并用于下一条指令。理解镜像层和commit的概念，是理解Docker镜像构建的关键。

镜像是被一层一层地"commit"上去的，而commit操作本身是由Docker容器执行的。`docker build`在执行一条指令时，会根据当前镜像层启动一个容器，Docker会在容器的层级文件系统最上层建立一层空的可读可写层(镜像层的内容对于容器来说是readonly的)，之后Docker容器执行指令，将执行结果写入可读可写层(并更新镜像Json文件)，最后再通过`docker commit`命令将可读可写层提交为一个新的镜像层。

Docker镜像层与镜像层之间是存在层级关系的，`docker build`会为Dockerfile每一条指令建立(commit)一个镜像层，并最终产生一个带标签(tag)的镜像，之前Dockerfile指令得到的镜像层(不会在构建完成后删除)是这个含标签镜像的祖先镜像。这样做的好处是最大化地复用镜像，不同的镜像之间可以共享镜像层，组成树形的镜像层级关系。

#### build cache

在`docker build`过程中，如果发现本地有镜像与即将构建出来的镜像层一致时，则使用已有镜像作为Cache，充当本次构建的结果。从而加快build过程，并且避免构建重复的镜像。

那么docker是如何知道当前尚未构建的镜像的形态，并且与本地镜像进行比较呢？

Docker镜像由镜像文件系统内容和镜像Json文件两部分构成，前者即为`docker commit`提交的可读可写层，而镜像Json文件的作用为：

- 记录镜像的父子关系，以及父子间的差异信息
- 弥补镜像本身以及镜像到容器转换所需的额外信息

比如镜像Json文件中记录了当前镜像的父镜像，以及当前镜像与父镜像的差异(比如执行了哪条指令)，`docker build`则在这个基础上进行预测：

- 判断已有镜像和目标镜像(当前正在构建的镜像)是父镜像ID是否相同
- 评估已有镜像的Json文件(如执行了那条命令，有何变动)，与目标镜像是否匹配

如果条件满足，则可将已有镜像作为目标镜像的Cache，当然这种机制是并不完善的，比如当你执行的指令有外部动态依赖，此时可通过`docker build --no-cache`禁止使用Cache。

另外，基于build cache的机制，我们在写Dockerfile的时候，应该将静态安装，配置命令等尽可能放在Dockerfile前面，这样才能最大程度地利用cache，加快build过程。因为一旦Dockerfile前面有指令更新了并导致新的镜像层生成，那么该指令之后的镜像层cache也就完全失效了(树结构长辈节点更新了，子节点当然就不一样了)。


### 3. docker build 示例

Dcokerfile:

    FROM ubuntu:14.04
    # 创建一个100M的文件 /test
    RUN dd if=/dev/zero of=/test bs=1M count=100
    RUN rm /test
    RUN dd if=/dev/zero of=/test bs=1M count=100
    # 在根目录统计容器大小
    ENTRYPOINT ["du", "-sh"]

build镜像：

    ▶ docker build . 
    Sending build context to Docker daemon   599 kB
    Step 1 : FROM ubuntu:14.04
     ---> 1e0c3dd64ccd
    Step 2 : RUN dd if=/dev/zero of=/test bs=1M count=100
     ---> Running in d98f674c46f2
    100+0 records in
    100+0 records out
    104857600 bytes (105 MB) copied, 0.0980112 s, 1.1 GB/s
     ---> f3a606172d91
    Removing intermediate container d98f674c46f2
    Step 3 : RUN rm /test
     ---> Running in 14544c0dc6a0
     ---> 7efc0655e95d
    Removing intermediate container 14544c0dc6a0
    Step 4 : RUN dd if=/dev/zero of=/test bs=1M count=100
     ---> Running in 387be027ef2f
    100+0 records in
    100+0 records out
    104857600 bytes (105 MB) copied, 0.0852024 s, 1.2 GB/s
     ---> 38e3ea5c1412
    Removing intermediate container 387be027ef2f
    Step 5 : ENTRYPOINT du -sh
     ---> Running in e190adcbcce2
     ---> baec9103f182
    Removing intermediate container e190adcbcce2
    Successfully built baec9103f182

可以看到build过程为不断基于当前镜像启动中间容器(如d98f674c46f2容器基于1e0c3dd64ccd镜像层执行指令`RUN dd if=/dev/zero of=/test bs=1M count=100`并提交f3a606172d91镜像层)。通过`docker history <image>`可查看镜像层级关系：

    docker history baec9103f182                                                                                
    IMAGE               CREATED             CREATED BY                                      SIZE                COMMENT
    baec9103f182        4 minutes ago       /bin/sh -c #(nop)  ENTRYPOINT ["du" "-sh"]      0 B
    38e3ea5c1412        4 minutes ago       /bin/sh -c dd if=/dev/zero of=/test bs=1M cou   104.9 MB
    7efc0655e95d        4 minutes ago       /bin/sh -c rm /test                             0 B
    f3a606172d91        4 minutes ago       /bin/sh -c dd if=/dev/zero of=/test bs=1M cou   104.9 MB
    1e0c3dd64ccd        3 weeks ago         /bin/sh -c #(nop)  CMD ["/bin/bash"]            0 B
    <missing>           3 weeks ago         /bin/sh -c mkdir -p /run/systemd && echo 'doc   7 B
    <missing>           3 weeks ago         /bin/sh -c sed -i 's/^#\s*\(deb.*universe\)$/   1.895 kB
    <missing>           3 weeks ago         /bin/sh -c rm -rf /var/lib/apt/lists/*          0 B
    <missing>           3 weeks ago         /bin/sh -c set -xe   && echo '#!/bin/sh' > /u   194.6 kB
    <missing>           3 weeks ago         /bin/sh -c #(nop) ADD file:bc2e0eb31424a88aad   187.7 MB

注意到其中一些镜像层的SIZE为0，这是因为该镜像层执行的命令不会影响到镜像的文件系统大小，这些命令会单独记录在镜像Json文件中。由于镜像的层级原理，Docker在执行`RUN rm /test`指令时，并没有真正将其当前镜像f3a606172d91中的/test文件真正删掉，而是将rm操作记录在镜像Json文件中(容器只能在其上层的可读写层进行更改操作)，最终我们得到的镜像大小约为400M。

然后我们基于得到镜像启动容器：

    docker run --rm baec9103f182
    du: cannot access './proc/1/task/1/fd/4': No such file or directory
    du: cannot access './proc/1/task/1/fdinfo/4': No such file or directory
    du: cannot access './proc/1/fd/4': No such file or directory
    du: cannot access './proc/1/fdinfo/4': No such file or directory
    296M    .

我们的容器大小只是近300M，因此Docker镜像的大小和容器中文件系统内容的大小是两个概念。镜像的大小等于其包含的所有镜像层之和，并且由于镜像层共享技术的存在(比如我们再构建一个基于ubuntu14:04的镜像，将直接复用本地已有的ubuntu镜像层)，极大节省了磁盘空间。

1. [Dockerfile Best Practices][]
2. [Dockerfile Reference][]
3. [Docker run Reference][]
4. [Docker 从入门到实践][]

[Docker Hub]: http://hub.docker.com/
[Docker Store]: https://store.docker.com/
[Dockerfile Best Practices]: https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices
[Dockerfile Reference]: https://docs.docker.com/engine/reference/builder/
[Docker run Reference]: https://docs.docker.com/engine/reference/run/
[Docker 从入门到实践]: https://www.gitbook.com/book/yeasy/docker_practice/details
[Docker For Mac]: https://docs.docker.com/docker-for-mac/