---
title: Docker容器编排工具
layout: post
categories: tool
tags: docker
---

### 一. Docker Machine

通常我们使用的Docker都是直接在物理机上安装Docker Engine，docker-machine是一个在虚拟机上安装Docker Engine的工具，使用起来很方便:

    # 创建一个docker machine，命名为abc
    > docker-machine create abc
    # 列出当前主机上所有的docker machine
    > docker-machine ls
    # 通过ssh连接到abc
    > docker-machine ssh abc
    # 现在就已经在abc machine上，可以像使用Docker Engine一样正常使用
    docker@abc:~$ docker ps
    # 退出machine
    docker@abc:~$ exit

docker-machine可以用来在本机部署Docker集群，或者在云上部署Docker。docker-machine支持多种虚拟方案，virtualbox，xhyve，hyperv等等。具体使用比较简单，命令参考附录文档。


### 二. Docker Swarm

Docker Swarm是docker原生的集群管理工具，之前是个独立的项目，于 Docker 1.12 被整合到 Docker Engine 中,作为swarm model存在，因此Docker Swarm实际上有两种：独立的swarm和整合后swarm model。官方显然推荐后者，本文也使用swarm model。相较于kubernetes，Mesos等工具，swarm最大的优势是轻量，原生和易于配置。它使得原本单主机的应用可以方便地部署到集群中。

#### 相关术语

- task: 任务，集群的最小单位，对应单容器实例
- service: 服务，由一个或多个task构成，可以统一配置，部署，收缩
- node: 机器节点，代表一台物理机    

#### 相关命令

- docker service: 提供了service创建，更新，回滚，task扩展收缩等功能
- docker node: 提供对机器节点的管理
- docker swarm: 用于配置机器集群，包括管理manager和worker两类机器节点的增删

#### 1. 初始化 swarm

    [n1-common]> docker swarm init
    Swarm initialized: current node (b3a3avned864im04d7veyw06t) is now a manager.
    
    To add a worker to this swarm, run the following command:
    
        docker swarm join --token SWMTKN-1-4mptgs751hcyh3ddlqwvv2aumo5j5mu1qllva52ciim6bun51d-eausald3qqtae604doj639mck 192.168.65.2:2377
    
    To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

执行该条命令的node将会成为manager node，该命令会生成两个token: manager token和worker token，通过`docker swarm join --token TOKEN MANAGER_NODE_IP`提供不同的token来将当前node以不同身份加入到集群。

现在我们尝试加入一个worker node，在另一台机器上执行:
    
    [moby]> docker swarm join --token SWMTKN-1-2w53lkm9h1l5u6yb4hh0k2t8yayub2zx0sidpvcr9nicqwafzx-9jm5zix2041rhfrf7e07oh4l2 172.20.140.39:2377
    This node joined a swarm as a worker.

#### 2. 配置节点

通过 `docker node ls` 可以查看当前swarm集群中的所有节点(只能在manager节点上运行):

    [n1-common]> sudo docker node ls
    ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
    yozazaogirhpj8skccfwqtl8f     moby                Ready               Active
    rx03hnmwx6z9jc9x9velz46if *   n1-common           Ready               Active              Leader

PS: swarm的service和node管理命令的规范和container管理类似:

    docker node|service ls: 查看集群中所有的节点(服务)
    docker node|service ps: 查看指定节点(服务)的容器信息
    docker node|service inspect: 查看指定节点(服务)的内部配置和状态信息
    docker node|service update: 更新节点(服务)配置信息
    docker node|service rm: 从集群中移除节点(服务)
    
以上命令都只能在manager节点上运行。

在这里，我们通过docker node update为节点设置标签:

    n1-common:~$ docker node update --label-add type=db moby
    moby

#### 3. 创建服务

服务有两种模式(mode): 

- 复制集模式(--mode replicas): 默认模式，该方式会将指定的(通过--replicas) M个task按照指定方式部署在N个机器节点上(N <= 集群机器节点数)。
- 全局模式(--mode global): 将服务在每个机器节点上部署一份，因此无需指定任务数量，也不能进行任务扩展和收缩。

我们尝试创建一个名为redis的服务，该服务包含5个任务的复制集:

    [n1-common]> docker service create \
    --replicas 5 \
    --name redis \
    --constraint 'node.labels.type=db' \
    --update-delay 10s \
    --update-parallelism 2 \
    --env MYVAR=foo \
    -p 6379:6379 \
    redis

`--update-xxx`指定了服务更新策略，这里为redis服务指定最多同时更新2个task，并且每批次更新之间间隔10s，在更新失败时，执行回滚操作，回滚到更新前的配置。更新操作通过`docker service update`命令完成，可以更新`docker service create`中指定的几乎所有配置，如task数量。`docker service create`除了更新策略外，还可以为service指定回滚策略(`--rollback-xxx`)，重启策略(`--restart-xxx`)等。

`--constraint`指定服务约束，限制服务的任务能够部署的节点，在这里，redis服务的5个任务只能部署在集群中labels.type==db的节点上。除了constraint参数外，还可以通过`--placement-pref`更进一步地配置部署优先级，如`--placement-pref 'spread=node.labels.type'`将task平均分配到不同的type上，哪怕各个type的node数量不一致。

`--env MYVAR=foo`指定服务环境变量，当然，这里并没有实际意义。

关于服务创建的更多选项参考官方文档。运行以上命令后，服务默认将在后台创建(--detach=false)，通过`docker service ps redis`可查看服务状态，确保服务的任务都以正常启动:

    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
    fegu7p341u58        redis.1             redis:latest        moby                Running             Running 9 seconds ago
    hoghsnnamv56        redis.2             redis:latest        moby                Running             Running 9 seconds ago
    0klozd8zkz0d        redis.3             redis:latest        moby                Running             Running 10 seconds ago
    jpcik7w3hpjx        redis.4             redis:latest        moby                Running             Running 10 seconds ago
    29jrofbwfi13        redis.5             redis:latest        moby                Running             Running 8 seconds ago

可以看到，由于只有moby节点的labels.type==db，因此所有的task都被部署在moby节点上。现在整个服务已经部署完成，那么如何访问这个服务呢？事实上，我们通过moby或者n1-common两台主机IP:6379均可访问Redis服务，**Swarm向用户屏蔽了服务的具体部署位置，让用户使用集群就像使用单主机一样**，这也为部署策略，负载均衡以及故障转移提供基础。

#### 4. 平滑更新

通过`docker service update`可以完成对服务的更新，可更新的配置很多，包括`docker service create`中指定的参数，自定义标签等，服务的更新策略由`--update-xxx`选项配置，只有部分更新需要重启任务，可通过`--force`参数强制更新。

现在我们尝试限制redis服务能够使用的cpu个数:

    [n1-common]> docker service update --limit-cpu 2 redis
    redis
    Since --detach=false was not specified, tasks will be updated in the background.
    In a future release, --detach=false will become the default.
    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE             ERROR               PORTS
    fegu7p341u58        redis.1             redis:latest        moby                Running             Running 13 minutes ago
    hoghsnnamv56        redis.2             redis:latest        moby                Running             Running 13 minutes ago
    mgblj8v97al1        redis.3             redis:latest        moby                Running             Running 9 seconds ago
    0klozd8zkz0d         \_ redis.3         redis:latest        moby                Shutdown            Shutdown 11 seconds ago
    jpcik7w3hpjx        redis.4             redis:latest        moby                Running             Running 13 minutes ago
    49mvisd0zbtj        redis.5             redis:latest        moby                Running             Running 8 seconds ago
    29jrofbwfi13         \_ redis.5         redis:latest        moby                Shutdown            Shutdown 11 seconds ago
    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE             ERROR               PORTS
    9396e3x8gp5m        redis.1             redis:latest        moby                Ready               Ready 2 seconds ago
    fegu7p341u58         \_ redis.1         redis:latest        moby                Shutdown            Running 2 seconds ago
    msugiubez60a        redis.2             redis:latest        moby                Ready               Ready 2 seconds ago
    hoghsnnamv56         \_ redis.2         redis:latest        moby                Shutdown            Running 2 seconds ago
    mgblj8v97al1        redis.3             redis:latest        moby                Running             Running 13 seconds ago
    0klozd8zkz0d         \_ redis.3         redis:latest        moby                Shutdown            Shutdown 15 seconds ago
    jpcik7w3hpjx        redis.4             redis:latest        moby                Running             Running 13 minutes ago
    49mvisd0zbtj        redis.5             redis:latest        moby                Running             Running 12 seconds ago
    29jrofbwfi13         \_ redis.5         redis:latest        moby                Shutdown            Shutdown 15 seconds ago

由于限制服务所使用的CPU数量需要重启任务，通过前后两次的`docker service ps`可以看到，docker service的更新策略与我们在`docker service create`中指定的一致: 每两个一组，每组间隔10s，直至更新完成，通过指定`--detach=false`能同步地看到这个平滑更新过程。这种平滑更新重启使得服务在升级过程中，仍然能够正常对外提供服务。docker swarm会保存每个任务的升级历史及对应的容器ID和容器状态，以便在更新失败时正确回滚(如果指定了更新失败的行为为回滚)，`docker service rollback`命令可强制将任务回滚到上一个版本。

现在我们通过`docker service scale`来伸缩服务任务数量，在这里我们使用`--detach=false`选项:

    [n1-common]> docker service scale redis=3
    redis scaled to 3
    overall progress: 3 out of 3 tasks
    1/3: running   [==================================================>]
    2/3: running   [==================================================>]
    3/3: running   [==================================================>]
    verify: Service converged
    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE             ERROR               PORTS
    9396e3x8gp5m         redis.1            redis:latest        moby                Running             Running 10 minutes ago
    fegu7p341u58         \_ redis.1         redis:latest        moby                Shutdown            Shutdown 10 minutes ago
    8urov9089x6c         redis.4            redis:latest        moby                Running             Running 9 minutes ago
    jpcik7w3hpjx         \_ redis.4         redis:latest        moby                Shutdown            Shutdown 9 minutes ago
    49mvisd0zbtj         redis.5            redis:latest        moby                Running             Running 10 minutes ago
    29jrofbwfi13         \_ redis.5         redis:latest        moby                Shutdown            Shutdown 10 minutes ago

服务的任务规模被收缩，现在只剩下redis.1,redis.4,redis.5三个任务。

#### 5. 故障转移

现在我们将redis服务停掉，重新创建一个redis服务:

    [n1-common]> docker service rm redis
    redis
    [n1-common]> docker service create --replicas 5 --name redis  -p 6379:6379 redis
    fvcwpsmbscxhsmg04vf5zhmbf
    Since --detach=false was not specified, tasks will be created in the background.
    In a future release, --detach=false will become the default.
    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE           ERROR               PORTS
    n1dd790efq36        redis.1             redis:latest        moby                Running             Running 2 minutes ago
    5fvqbozb7bpr        redis.2             redis:latest        n1-common           Running             Running 2 minutes ago
    ma533n5ce09c        redis.3             redis:latest        moby                Running             Running 2 minutes ago
    j1f18j2yaqhc        redis.4             redis:latest        n1-common           Running             Running 2 minutes ago
    p2kf7ftrexam        redis.5             redis:latest        moby                Running             Running 2 minutes ago
    
由于我们没有指定部署约束，因此redis服务的5个任务将被自动负载到集群节点中，在这里，redis.2,redis.4部署在n1-common上，其余三个部署在moby，现在我们将moby节点退出集群，观察服务任务状态变化:

    [moby]>  docker swarm leave
    Node left the swarm.
    [n1-common]> service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE                     ERROR               PORTS
    8c5py5p9pcgz        redis.1             redis:latest        n1-common           Ready               Accepted less than a second ago
    n1dd790efq36         \_ redis.1         redis:latest        moby                Shutdown            Running 12 seconds ago
    5fvqbozb7bpr        redis.2             redis:latest        n1-common           Running             Running 8 minutes ago
    ml546ziyey4r        redis.3             redis:latest        n1-common           Ready               Accepted less than a second ago
    ma533n5ce09c         \_ redis.3         redis:latest        moby                Shutdown            Running 8 minutes ago
    j1f18j2yaqhc        redis.4             redis:latest        n1-common           Running             Running 8 minutes ago
    kfu6jeddkvwu        redis.5             redis:latest        n1-common           Ready               Accepted less than a second ago
    p2kf7ftrexam         \_ redis.5         redis:latest        moby                Shutdown            Running 12 seconds ago
    [n1-common]> docker service ps redis
    ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
    8c5py5p9pcgz        redis.1             redis:latest        n1-common           Running             Running 3 seconds ago
    n1dd790efq36         \_ redis.1         redis:latest        moby                Shutdown            Running 23 seconds ago
    5fvqbozb7bpr        redis.2             redis:latest        n1-common           Running             Running 8 minutes ago
    ml546ziyey4r        redis.3             redis:latest        n1-common           Running             Running 3 seconds ago
    ma533n5ce09c         \_ redis.3         redis:latest        moby                Shutdown            Running 8 minutes ago
    j1f18j2yaqhc        redis.4             redis:latest        n1-common           Running             Running 8 minutes ago
    kfu6jeddkvwu        redis.5             redis:latest        n1-common           Running             Running 3 seconds ago
    p2kf7ftrexam         \_ redis.5         redis:latest        moby                Shutdown            Running 23 seconds ago

故障节点moby上面的1,3,5任务已经被自动重新部署在其它可用节点(当前只有n1-common)上，并记录了每个任务的版本和迁移历史。现在如果尝试再将moby节点加入集群，会发现5个task仍然都在n1-common上，没有立即进行任务转移，而是等下一步重启升级或者扩展服务任务时再进行动态负载均衡。

#### 6. 再看Swarm集群

再来回顾一下Docker Swarm，在我们初始化或加入Swarm集群时，通过`docker network ls`可以看到，Docker做了如下事情:

1. 创建了一个叫ingress的overlay网络，用于Swarm集群容器跨主机通信，在创建服务时，如果没有为其指定网络，将默认接入到ingress网络中
2. 创建一个docker\_gwbridge虚拟网桥，用于连接集群各节点(Docker Deamon)的物理网络到到ingress网络

网络细节暂时不谈(也没怎么搞清楚)，总之，Swarm集群构建了一个跨主机的网络，可以允许集群中多个容器自由访问。Swarm集群有如下几个比较重要的特性:

1. 服务的多个任务可以监听同一端口(通过iptables透明转发)。
2. 屏蔽掉服务的具体物理位置，通过任意集群节点IP:Port均能访问服务(无论这个服务是否跑在这个节点上)，Docker会将请求正确路由到运行服务的节点(称为routing mesh)。在routine mesh下，服务运行在虚拟IP环境(virtual IP mode, vip)，即使服务运行在global模式(每个节点都运行有任务)，用户仍然不能假设指定IP:Port节点上的服务会处理请求。
3. 如果不想用Docker Swarm自带的routing mesh负载均衡器，可以在服务创建或更新时使用`--endpoint-mode = dnsrr`，dnsrr为dns round robin简写，另一种模式即为vip，dnsrr允许应用向Docker通过服务名得到服务IP:Port列表，然后应用负责从其中选择一个地址进行服务访问。

综上，Swarm通过虚拟网桥和NATP等技术，搭建了一个跨主机的虚拟网络，通过Swarm Manager让这个跨主机网络用起来像单主机一样方便，并且集成了服务发现(服务名->服务地址)，负载均衡(routing mesh)，这些都是Swarm能够透明协调转移任务的根本保障，应用不再关心服务有几个任务，部署在何处，只需要知道服务在这个集群中，端口是多少，然后这个服务就可以动态的扩展，收缩和容灾。当然，Swarm中的服务是理想状态的微服务，亦即是无状态的。

### 三. Docker Compose & Stack

docker-compose 是一个用于定义和运行多容器应用的工具。使用compose，你可以通过一份docker-compose.yml配置文件，然后运行`docker-compose up`即可启动整个应用所配置的服务。一个docker-compose.yml文件定义如下:

    version: '3'  # docker-compose.yml格式版本号，版本3为官方推荐版本，支持swarm model和deploy选项
    services:     # 定义引用所需服务
      web:        # 服务名字
        build: .  # 服务基于当前目录的Dockerfile构建
        ports:    # 服务导出端口配置
        - "5000:5000"
        volumes:  # 服务目录挂载配置
        - .:/code
        - logvolume01:/var/log
        links:    # 网络链接
        - redis
        deploy:   # 部署配置 和 docker service create中的参数对应 只有版本>3支持
          replicas: 5
          resources:
            limits:
              cpus: "0.1"
              memory: 50M
          restart_policy:
            condition: on-failure
      redis:      # redis 服务
        image: redis # 服务基于镜像构建

docker-compose设计之初是单机的，docker-compose中也有服务的概念，但只是相当于一个或多个容器(version>2.2 scale参数)，并且只能部署在单台主机上。版本3的docker-compose.yml开始支持swarm model，可以进行集群部署配置，这里的服务才是swarm model中的服务。但version 3的docker-compose.yml本身已经不能算是docker-compose的配置文件了，因为docker-compose不支持swarm model，用以上配置文件执行`docker-compose up`将得到警告:

    WARNING: Some services (web) use the 'deploy' key, which will be ignored. Compose does not support 'deploy' configuration - use `docker stack deploy` to deploy to a swarm.
    WARNING: The Docker Engine you're using is running in swarm mode.
    
    Compose does not use swarm mode to deploy services to multiple nodes in a swarm. All containers will be scheduled on the current node.

那么`docker stack`又是什么？`docker stack`是基于`docker swarm`之上的应用构建工具，前面介绍的`docker swarm`只能以服务为方式构建，而docker-compose虽然能以应用为单位构建，但本身是单机版的，Docker本身并没有基于docker-compose进行改造，而是另起炉灶，创建了`docker stack`命令，同时又复用了docker-compose.yml配置方案(同时也支持另一种bundle file配置方案)，因此就造成了docker-compose能使用compose配置的version 1, version 2,和部分version 3(不支持swarm model和deploy选项)，而`docker stack`仅支持version 3的compose配置。

总的来说，如果应用是单机版的，或者说不打算使用docker swarm集群功能，那么就通过docker-compose管理应用构建，否则使用docker stack，毕竟后者才是亲生的。

参考:

1. [Docker Machine](https://docs.docker.com/machine/reference/)
2. [Docker Swarm](https://docs.docker.com/get-started/part4/)
3. [Docker Compose](https://docs.docker.com/compose/gettingstarted/)
4. [Docker Services](https://docs.docker.com/get-started/part3/)
5. [Docker overlay网络](https://docs.docker.com/network/overlay/)
