---
title: Docker 容器管理
layout: post
categories: tool
tags: docker
---

### 一. 容器资源限制

Docker资源限制主要靠Linux cgroups技术实现，简单说，cgroups是一个个的进程组(实际上是进程树)，这些进程树通过挂接 subsystem(事实上是挂接到 cgroup 上层的hierarchy)来实现对各种资源的限制和追踪，subsystem是内核附加在程序上的一系列钩子（hooks），通过程序运行时对资源的调度触发相应的钩子以达到资源追踪和限制的目的。cgroups 技术的具体介绍和实现参考文末链接。

<!--more-->

#### 1. CPU

默认情况下，Docker容器对 CPU 资源的访问是无限制的，可使用如下参数控制容器的 CPU 访问:

`--cpus`: 控制容器能够使用的最大 CPU 核数，参数为一个精度为两位小数的浮点数(默认值为0，即不限制 CPU)，不能超出物理机的 CPU 核数。

    # 通过 stress 开启三个 worker 跑满 CPU 的 worker，并设置容器能访问的 cpus 为1.5
    > docker run --rm -it --cpus 1.5 progrium/stress --cpu 3
    stress: info: [1] dispatching hogs: 3 cpu, 0 io, 0 vm, 0 hdd
    stress: dbug: [1] using backoff sleep of 9000us
    stress: dbug: [1] --> hogcpu worker 3 [7] forked
    stress: dbug: [1] using backoff sleep of 6000us
    stress: dbug: [1] --> hogcpu worker 2 [8] forked
    stress: dbug: [1] using backoff sleep of 3000us
    stress: dbug: [1] --> hogcpu worker 1 [9] forked
    
    # 开启另一个窗口查看 CPU 占用情况
    top
    # ...
      PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
     4296 root      20   0    7316    100      0 R  51.8  0.0   0:07.04 stress
     4294 root      20   0    7316    100      0 R  51.5  0.0   0:07.02 stress
     4295 root      20   0    7316    100      0 R  46.5  0.0   0:06.42 stress
        
三个 worker 进程各自占用了50%的 CPU，共计150%，符合`--cpus`指定的1.5核约束。

`--cpu-shares`: 通过权重来控制同一物理机上的各容器的 CPU 占用，默认值为1024(该值应该是起源于 Linux2.6+中 CFS 调度算法的默认进程优先级)，它是一个软限制，仅在物理机 CPU 不够用时生效，当 CPU 够用时，容器总是尽可能多地占用 CPU。

    # 开启8个 cpu worker 跑满所有核 默认 cpu-shares 为1024
    > docker run --rm -it  progrium/stress --cpu 8
    # 开新窗口查看 CPU 状态
    > top
    # ...
      PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
     4477 root      20   0    7316     96      0 R 100.0  0.0   0:08.51 stress
     4481 root      20   0    7316     96      0 R 100.0  0.0   0:08.52 stress
     4474 root      20   0    7316     96      0 R  99.7  0.0   0:08.50 stress
     4476 root      20   0    7316     96      0 R  99.7  0.0   0:08.50 stress
     4478 root      20   0    7316     96      0 R  99.7  0.0   0:08.50 stress
     4479 root      20   0    7316     96      0 R  99.7  0.0   0:08.50 stress
     4480 root      20   0    7316     96      0 R  99.7  0.0   0:08.50 stress
     4475 root      20   0    7316     96      0 R  99.3  0.0   0:08.48 stress
    # 再开8个 cpu worker，设置 cpu-shares 为 512
    docker run --rm -it  --cpu-shares 512 progrium/stress --cpu 8
    # 再次查看 CPU 占用
    > top
    # ...
      PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
     4815 root      20   0    7316     96      0 R  67.0  0.0   0:28.56 stress
     4816 root      20   0    7316     96      0 R  67.0  0.0   0:28.30 stress
     4820 root      20   0    7316     96      0 R  67.0  0.0   0:28.13 stress
     4821 root      20   0    7316     96      0 R  67.0  0.0   0:28.31 stress
     4817 root      20   0    7316     96      0 R  66.7  0.0   0:28.04 stress
     4818 root      20   0    7316     96      0 R  66.7  0.0   0:28.42 stress
     4819 root      20   0    7316     96      0 R  66.7  0.0   0:28.24 stress
     4822 root      20   0    7316     96      0 R  66.7  0.0   0:28.38 stress
     4961 root      20   0    7316     96      0 R  33.3  0.0   0:03.93 stress
     4962 root      20   0    7316     96      0 R  33.3  0.0   0:03.96 stress
     4965 root      20   0    7316     96      0 R  33.3  0.0   0:03.95 stress
     4966 root      20   0    7316     96      0 R  33.3  0.0   0:04.02 stress
     4968 root      20   0    7316     96      0 R  33.3  0.0   0:03.90 stress
     4963 root      20   0    7316     96      0 R  33.0  0.0   0:04.01 stress
     4964 root      20   0    7316     96      0 R  33.0  0.0   0:03.97 stress
     4967 root      20   0    7316     96      0 R  33.0  0.0   0:03.94 stress
    
可以看到最开始的8个 worker CPU 占用由100%降到67%左右，而新启动的 worker CPU 占用为32%左右，大致满足2/3和1/3的权重占比。

除此之外，Docker还可以通过`--cpuset-cpus`参数限制容器运行在某些核上，但环境依赖太强(需要知道主机上有几个CPU核)，有违容器初衷，并且通常都不需要这样做。在 Docker1.13之后，还支持容器的实时调度配置(realtime scheduler)，就应用层而言，基本用不到这项配置，参考: https://docs.docker.com/config/containers/resource_constraints/#configure-the-realtime-scheduler。

#### 2. 内存

同 CPU 一样，默认情况下，Docker没有对容器内存进行限制。内存相关的几个概念:

memory: 即容器可用的物理内存(RES)，包含 kernel-memory 和 user-memory，即内核内存和用户内存。
kernel-memory: 内核内存，每个进程都会占用一部分内核内存，和user-memory 的最大区别是不能被换入换出，因此进程的内核内存占用过大可能导致阻塞系统服务。
swap: 容器可用的交换区大小，会swap+memory限制着进程最大能够分配的虚拟页，也是进程理论上能够使用的最大"内存"(虚拟内存)。

以下大部分配置的参数为正数，加上内存单位，如"4m", "128k"。

- `-m` or `--memory`: 容器可以使用的最大内存限制，最小为4m
- `--memory-swap`: 容器使用的内存和交换区的总大小
- `--memory-swappiness`: 默认情况下，主机可以把容器使用的匿名页(anonymous page) swap 出来，这个参数可以配置可被swap的比例(0-100)
- `--memory-reservation`: 内存软限制，每次系统内存回收时，都会尝试将进程的内存占用降到该限制以下(尽可能换出)。该参数的主要作用是避免容器长时间占用大量内存。
- `--kernel-memory`: 内核内存的大小
- `--memory-swappiness`: 设置容器可被置换的匿名页的百分比，值为[0,100]，为0则关闭匿名页交换，容器的工作集都在内存中活跃，默认值从父进程继承
- `--oom-kill-disable`: 当发生内存不够用(OOM) 时，内核默认会向容器中的进程发送 kill 信号，添加该参数将避免发送 kill 信号。该参数一般与`-m` 一起使用，因为如果没有限制内存，而又启用了 oom-kill-disable，OS 将尝试 kill 其它系统进程。(PS: 该参数我在 Ubuntu 16.04 LTS/Docker17.09.0-ce环境下，没有测试成功，仍然会直接 kill)
- `--oom-score-adj`: 当发生 OOM 时，进程被 kill 掉的优先级，取值[-1000,1000]，值越大，越可能被 kill 掉

`--memory`和`--memory-swap`:

    1. 当 memory-swap > memory > 0: 此时容器可使用的 swap 大小为: swap = memory-swap - memory
    2. memory-swap == 0 或 < memory: 相当于没有设置(如果< memory, docker 会错误提示)，使用默认值，此时容器可使用的 swap 大小为: swap == memory，即 memory-swap = = 2*memory
    3. memory-swap == memory > 0: 容器不能使用交换空间: swap = memory-swap - memory = 0
    4. memory-swap == -1: 容器可使用主机上所有可用的 swap 空间，即无限制
    
在配置`--memory-swap` 参数时，可能遇到如下提示:

    WARNING: Your kernel does not support swap limit capabilities or the cgroup is not mounted. Memory limited without swap.

解决方案为:
    
    To enable memory and swap on system using GNU GRUB (GNU GRand Unified Bootloader), do the following:
    1. Log into Ubuntu as a user with sudo privileges.
    2. Edit the /etc/default/grub file.
    3. Set the GRUB_CMDLINE_LINUX value as follows:
        GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"
    4. Save and close the file.
    5. Update GRUB.
        $ sudo update-grub
    Reboot your system.

示例:

我们通过一个 带有 stress 命令的 ubuntu 镜像来进行测试:

    > cat Dockerfile
    FROM ubuntu:latest
    
    RUN apt-get update && \
    apt-get install stress
    
    > docker build -t ubuntu-stress:latest .

    # 示例一:
    # memory 限制为100M，swap 空间无限制，分配1000M 内存
    > docker run -it --rm -m 100M --memory-swap -1 ubuntu-stress:latest /bin/bash
    root@e618f1fc6ff9:/# stress --vm 1 --vm-bytes 1000M
    # docker stats 查看容器内存占用，此时容器物理内存已经达到100M 限制
    > docker stats e618f1fc6ff9
    CONTAINER           CPU %               MEM USAGE / LIMIT   MEM %               NET I/O             BLOCK I/O           PIDS
    e618f1fc6ff9        15.62%              98.25MiB / 100MiB   98.25%              3.39kB / 0B         22GB / 22.4GB       3
    > pgrep stress
    27158
    27159 # stress worker 子进程 PID
    # 通过 top 可以看到进程物理内存占用为100M，虚拟内存占用为1000M
    > top -p 27159
    top - 19:30:08 up 31 days,  1:55,  3 users,  load average: 1.63, 1.43, 1.03
    Tasks:   1 total,   0 running,   1 sleeping,   0 stopped,   0 zombie
    %Cpu(s):  1.8 us,  4.3 sy,  2.1 ni, 81.2 id, 10.3 wa,  0.0 hi,  0.3 si,  0.0 st
    KiB Mem : 16361616 total,   840852 free,  3206616 used, 12314148 buff/cache
    KiB Swap: 16705532 total, 15459856 free,  1245676 used. 12681868 avail Mem
    
      PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
    27159 root      20   0 1031484  98844    212 D  14.3  0.6   0:53.11 stress
    
    # 示例二:
    # memory 限制为100M，swap 比例为 50%
    > docker run -it --rm -m 100M --memory-swappiness 50 ubuntu-stress:latest /bin/bash
    root@e3fdd8b75f1d:/# stress --vm 1 --vm-bytes 190M # 分配190M 内存
    # 190M 内存正常分配，因为190M*50%的页面可以被 swap，剩下50%的页面放在内存中
    > top -p 29655
    # ...
      PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
    29655 root      20   0  202044  98296    212 D   9.7  0.6   0:17.52 stress
    # 停止 stress，重新尝试分配210M 内存，210M*50%>100M，内存不够，进程被 kill 掉
    > root@e3fdd8b75f1d:/# stress --vm 1 --vm-bytes 210M
    stress: info: [13] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
    stress: FAIL: [13] (415) <-- worker 14 got signal 9
    stress: WARN: [13] (417) now reaping child worker processes
    stress: FAIL: [13] (451) failed run completed in 4s
    
    # 示例三:
    # memory 限制为100M, swap 比例为60%, memory-swap 为130M
    # 可以得到，容器能使用的最大虚拟内存为 min(100/(1-60%), 130) = 130M，现在来简单验证
    docker run -it --rm -m 100M --memory-swappiness 50 --memory-swap 30M ubuntu-stress:latest /bin/bash
    # 分配120M 内存, OK
    root@b54444b40706:/# stress --vm 1 --vm-bytes 120M
    stress: info: [11] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
    ^C
    # 分配140M 内存，Error
    root@b54444b40706:/# stress --vm 1 --vm-bytes 140M
    stress: info: [13] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
    stress: FAIL: [13] (415) <-- worker 14 got signal 9
    stress: WARN: [13] (417) now reaping child worker processes
    stress: FAIL: [13] (451) failed run completed in 1s
    

### 二. 容器监控

#### 1. docker inspect

`docker inspect`用于查看容器的静态配置，容器几乎所有的配置信息都在里面:

    > docker inspect 5c004516ee59 0e9300806926
    [
        {
            "Id": "5c004516ee592b53e3e83cdee69fc93713471d4ce06778e1c6a9f783a576531b",
            "Created": "2018-03-27T16:44:27.521434182Z",
            "Path": "game",
            "Args": [],
            "State": {
                "Status": "running",
                "Running": true,
            ...
    
`docker inspect`接收一个容器 ID 列表，返回一个 json 数组，包含容器的各项参数，可以通过 docker format 过滤输出:

    # 显示容器 IP
    > docker inspect --format '{{ .NetworkSettings.IPAddress }}' 5c004516ee59
    172.17.0.2

#### 2. docker stats

`docker stats`可实时地显示容器的资源使用(内存, CPU, 网络等):

    # 查看指定容器
    > docker stats ngs-game-1
    CONTAINER           CPU %               MEM USAGE / LIMIT    MEM %               NET I/O             BLOCK I/O           PIDS
    ngs-game-1          0.55%               127.4MiB / 15.6GiB   0.80%               0B / 0B             0B / 0B             18

    # 以容器名代替容器ID查看所有运行中的容器状态
    > docker stats $(docker ps --format={{.Names}})
    CONTAINER           CPU %               MEM USAGE / LIMIT    MEM %               NET I/O             BLOCK I/O           PIDS
    ngs-game-1          0.74%               127.4MiB / 15.6GiB   0.80%               0B / 0B             0B / 0B             18
    ngs-game-4          0.54%               21.99MiB / 15.6GiB   0.14%               0B / 0B             0B / 0B             20
    ngs-auth-1          0.01%               11.11MiB / 15.6GiB   0.07%               0B / 0B             0B / 0B             20

#### 3. docker attach

将本地的标准输入/输出以及错误输出 attach 到运行中的container 上。

	> docker run -d -it --name ubuntu1 ubuntu-stress /bin/bash
	da01f119000f7370780eea0220a0fbf6e7b6d8d0dac1d635fc5dd480a64e4f68
	> docker attach ubuntu1
	root@da01f119000f:/#
	# 开启另一个 terminal，再次 attach，此时两个 terminal 的输入输出会自动同步
	> docker attach ubuntu1

由于本地输入完全重定向到容器，因此输入 exit 或`CTRL-d`会退出容器，要 dettach 会话，输入`CTRL-p` `CTRL-q`。

### 三. 容器停止

- docker stop: 分为两个阶段，第一个阶段向容器主进程(Pid==1)发送SIGTERM信号，容器主进程可以捕获这个信号并进入退出处理流程，以便优雅地停止容器。第一阶段是有时间限制的(通过`-t`参数指明，默认为10s)，如果超过这个时间容器仍然没有停止，则进入第二阶段: 向容器主进程发送SIGKILL信号强行终止容器(SIGKILL无法被忽略或捕获)。
- docker kill: 不带参数则相当于直接进入docker stop的第二阶段，可通过`-s`参数指定要发送的信号(默认是SIGKILL)。

docker stop/kill仅向容器主进程(Pid==1)发送信号，因此对于ENTRYPOINT/CMD的Shell格式来说，可能导致应用无法接收的信号，Docker命令文档也提到了这一点:

>> Note: ENTRYPOINT and CMD in the shell form run as a subcommand of /bin/sh -c, which does not pass signals. This means that the executable is not the container’s PID 1 and does not receive Unix signals.


参考:

1. https://docs.docker.com/config/containers/resource_constraints/
2. https://docs.docker.com/engine/reference/run/#runtime-constraints-on-resources
3. [DOCKER基础技术：LINUX CGROUP](https://coolshell.cn/articles/17049.html)
4. [Docker背后的内核知识——cgroups资源限制](http://www.infoq.com/cn/articles/docker-kernel-knowledge-cgroups-resource-isolation)