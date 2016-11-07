### Docker 使用

我们将结合Erlang和Docker，探索一下Docker的功能和使用方法。

下面是一个简单的TCP Server：

 {% codeblock lang:erlang %}
-module(server_tcp).
-export([start/1]).

start([Response]) ->
    io:format("SERVER Trying to bind to port 2345\n"),
    {ok, Listen} = gen_tcp:listen(2345, [ binary
                                        , {packet, 0}
                                        , {reuseaddr, true}
                                        , {active, true}
                                        ]),
    io:format("SERVER Listening on port 2345\n"),
    accept(Listen, Response).

accept(Listen, Response) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    WorkerPid = spawn(fun() -> respond(Socket, Response) end),
    gen_tcp:controlling_process(Socket, WorkerPid),
    accept(Listen, Response).

respond(Socket, Response) ->
    receive
        {tcp, Socket, Bin} ->
            io:format("SERVER Received: ~p\n", [Bin]),
            gen_tcp:send(Socket, Response),
            respond(Socket, Response);
        {tcp_closed, Socket} ->
            io:format("SERVER: The client closed the connection\n")
    end.
{% endcodeblock %}

服务器只是每次返回指定的Reponse，这是客户端代码：

{% codeblock lang:erlang %}
-module(client_tcp).
-export([send/3]).

send(Host, Port, Request) ->
    {ok, Socket} = gen_tcp:connect(Host, Port, [binary, {packet, 0}]),
    ok = gen_tcp:send(Socket, Request),
    io:format("CLIENT Sent: ~p\n", [Request]),
    receive
        {tcp, Socket, Bin} ->
            io:format("CLIENT Received: ~p\n", [Bin]),
            gen_tcp:close(Socket)
    end.
{% endcodeblock %}

现在，我们尝试将代码放到Docker容器中运行：

    docker run -it -v ~/Docker/erltest:/code erlang erl
    Erlang/OTP 19 [erts-8.1] [source] [64-bit] [smp:2:2] [async-threads:10] [hipe] [kernel-poll:false]
    Eshell V8.1  (abort with ^G)
    1>  cd("code").  
    2> c(server_tcp).
    {ok,server_tcp}
    3> c(client_tcp).
    {ok,client_tcp}
    4> spawn(server_tcp, start, [["Hi"]]).
    SERVER Trying to bind to port 2345
    <0.69.0>
    SERVER Listening on port 2345
    5>
    5> client_tcp:send("localhost",2345,"Request").
    CLIENT Sent: "Request"
    SERVER Received: <<"Request">>
    CLIENT Received: <<"Hi">>
    ok
    SERVER: The client closed the connection
    6>

我们通过docker run启动Docker容器，并指定了容器运行的镜像erlang，docker会查看这个镜像是否存在于docker主机上，如果没有发现，docker就会在镜像仓库[Docker Hub][]下载公共镜像，启动容器，并且在容器中执行`erl`命令进入erl shell。

可通过`docker run --help`查看run子命令所支持的所有选项，直接运行`docker`可查看docker支持的所有子命令。

在容器中，默认我们的当前目录是在根目录(可通过-w选项指定容器的工作目录)，因此需要先进入/code目录，此时/code目录已经映射到我们的宿主机代码目录，再编译，运行。注意我们这里是在同一个erl shell中运行服务器和客户端，而如果我们是在宿主机或者另一个容器中访问2345端口，是访问不到的，因为各个容器和宿主机，是完全隔离的，我们打开的是容器的2345端口，而不是宿主机的。我们要在其它容器访问该容器端口，需要用到容器链接：

    docker run -it -v ~/Docker/erltest/:/code -w /code --name server erlang
    Erlang/OTP 19 [erts-8.1] [source] [64-bit] [smp:2:2] [async-threads:10] [hipe] [kernel-poll:false]
    Eshell V8.1  (abort with ^G)
    1> server_tcp:start(["BiuBiuBiu"]).
    SERVER Trying to bind to port 2345
    SERVER Listening on port 2345
    SERVER Received: <<"PiuPiuPiu">>
    SERVER: The client closed the connection

通过`--name`选项为容器指定名字，这个名字可用于其它容器与其交互，并且通过`-w`指定了容器的工作目录，因此无需再手动进入/code目录，直接运行之前编译好的服务器即可。

然后我们再启动一个容器，用于运行客户端：

    docker run -it -v ~/Docker/erltest/:/code -w /code --name client --link server erlang erl
    Erlang/OTP 19 [erts-8.1] [source] [64-bit] [smp:2:2] [async-threads:10] [hipe] [kernel-poll:false]
    Eshell V8.1  (abort with ^G)
    1> client_tcp:send("server",2345,"PiuPiuPiu").
    CLIENT Sent: "PiuPiuPiu"
    CLIENT Received: <<"BiuBiuBiu">>
    ok
    2>

在这里我们通过`--link`选项链接了server容器，因此在client容器中，可直接通过将容器名作为HostName传入来与其交互，这就形成了一个小型的集群，

