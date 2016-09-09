---
title: Rebar3 Erlang/OTP构建利器
layout: post
categories: erlang
tags: erlang

---

### 一. 依赖管理

#### 1. 包依赖和源码依赖

Rebar3支持两种依赖：

	{deps,[
	  %% 包依赖
	  rebar,
	  {rebar,"1.0.0"},
	  {rebar, {pkg, rebar_fork}}, % rebar app under a different pkg name
	  {rebar, "1.0.0", {pkg, rebar_fork}},
	  %% 源码依赖
	  {rebar, {git, "git://github.com/erlang/rebar3.git"}},
	  {rebar, {git, "http://github.com/erlang/rebar3.git"}},
	  {rebar, {git, "https://github.com/erlang/rebar3.git"}},
	  {rebar, {git, "git@github.com:erlang/rebar3.git"}},
	  {rebar, {hg, "https://othersite.com/erlang/rebar3"}},
	  {rebar, {git, "git://github.com/erlang/rebar3.git", {ref, "aef728"}}},
	  {rebar, {git, "git://github.com/erlang/rebar3.git", {branch, "master"}}},
	  {rebar, {git, "git://github.com/erlang/rebar3.git", {tag, "3.0.0"}}}
	  ]}
<!--more-->

Rebar3通过[hex.pm](https://hex.pm)来管理包依赖，在使用之前，需要通过`rebar3 update`从hex.pm更新包索引，并将包索引信息缓存到本地(`~/.cache/rebar3/`)。之后Rebar3便能正确解析包依赖，对应用程序使用上来说，两者没有明显区别。

#### 2. 升级依赖

在使用Rebar2的时候，如果项目依赖一个指向分支的dep，就会出现这种情况：

- 这个dep有远程分支更新时，rebar get-deps不会自动拉取更新，通常你只能进入dep目录执行`git pull`，或者删除该dep重新执行rebar get-deps。
- 项目成员各自的工作目录deps版本可能不一致，并且一些很久没更新的依赖可能在你部署新环境时(此时所有依赖都指向最新)出现问题。

所以在Rebar2的reabr.config中定义deps，都应该尽量使用tag, commitid来指定，而不是直接指向分支。那么Rebar3是如何解决这个问题的呢？

Rebar3解决此问题的核心在rebar.lock文件，该文件内容如下：

	{"1.1.0",
	[{<<"goldrush">>,{pkg,<<"goldrush">>,<<"0.1.8">>},1},
	 {<<"lager">>,{pkg,<<"lager">>,<<"3.2.1">>},0}]}.
	[
	{pkg_hash,[
	 {<<"goldrush">>, <<"2024BA375CEEA47E27EA70E14D2C483B2D8610101B4E852EF7F89163CDB6E649">>},
	 {<<"lager">>, <<"EEF4E18B39E4195D37606D9088EA05BF1B745986CF8EC84F01D332456FE88D17">>}]}
	].

该文件是项目当前使用依赖库的一个版本快照。当一个依赖被获取和锁定，Rebar3将从依赖中提取版本信息并写入rebar.lock文件中，该文件应该加入GIt仓库，并且由专人维护，这样只要rebar.lock一致，各本地仓库的依赖库版本就是一致的。

依赖升级分为两种，一种是直接通过`rebar upgrade [dep]`进行源码更新或包更新(只能更新Top Level依赖)。另一种是rebar.config发生变动，比如去除了某个依赖，此时需要`rebar unlock [dep]`命令来清理rebar.lock文件。


相关命令：

	rebar3 update  // 更新包索引
	rebar3 pkgs // 列出所有可用的包
	rebar3 deps  // 列出所有一级(Top Level)依赖
	rebar3 tree  // 以树形结构查看依赖
	rebar3 compile // 获取并编译依赖
	rebar3 upgrade [dep] // 升级依赖
	rebar3 lock [dep] // 锁定依赖
	rebar3 unlock [dep] // 解锁依赖
	
### 二. 构建

	rebar3 new app [appname]
	rebar3 new lib [libname]
	
Rebar3建议应用程序按照OTP规范目录进行组织：

	├── LICENSE
	├── README.md
	├── apps
	│   └── myapp
	│       └── src
	│           ├── myapp.app.src
	│           ├── myapp_app.erl
	│           └── myapp_sup.erl
	├── config
	│   ├── sys.config
	│   └── vm.args
	├── lib
	│   └── mylib
	│       ├── LICENSE
	│       ├── README.md
	│       ├── rebar.config
	│       └── src
	│           ├── mylib.app.src
	│           └── mylib.erl
	└── rebar.config

这样无需在rebar.config中指定sub_dirs，Rebar3会自动将lib和apps作为搜索路径。

Rebar3没有get-deps命令，通过`rebar3 compile`即可编译项目，并自动获取和编译不存在的依赖，Rebar3将所有编译文件和Release信息都置于`_build`目录下。默认apps，deps和lib下的应用都被编译到`_build/default/lib`中。要指定应用目录和输出目录等选项，请参考：[Rebar3配置][rebar3_configuration]。

### 三. 发布

#### 1. 发布环境

Rebar3放弃了[reltool][reltool]而使用[relx][relx]作为发布工具。并且将relx.config内容集成到rebar.config当中，通过`rebar new release [appname]`可创建一个发布，rebar.config内容如下：

	{erl_opts, [debug_info]}.
	{deps, []}.
	
	%% 定义默认发布环境(default环境)
	{relx, [{release, { myapp, "0.1.0" },
	         [myapp,
	          sasl]},
	
	        {sys_config, "./config/sys.config"},
	        {vm_args, "./config/vm.args"},
	
		%% 当dev_mode==true时 _build/default/rel/myapp/lib/目录下的库其实是_build/default/lib目录下对应lib的软链接，这样重新编译后，无需重新发布，重启或热加载代码即可
	        {dev_mode, true},
	        %% 是否在发布目录中包含虚拟机 即为一个独立的运行环境
	        {include_erts, false},
	
	        {extended_start_script, true}]
	}.

	%% 定义其它发布环境
	%% 参数使用覆盖(override)机制，即这里面没有定义的参数，将使用默认发布环境(default)配置
	{profiles, [{prod, [{relx, [{dev_mode, false},
	                            {include_erts, true}]}]
	            }]
	}

Rebar3中有发布环境(profiles)的概念，如开发环境(default)，生产环境(prod)，它们可以独立定义编译参数(erl_opts)，发布参数(dev_mode, include_erts)，甚至依赖应用(deps)。目前Rebar3支持四种环境定义：

- default：默认环境，也就是rebar.config中最外部定义的环境
- prod：生产环境，通常在此环境下将使用库的完整发布包(而不是软链接)，有更严格的编译选项，并且可能还要包含Erlang运行时所需要的所有环境
- native：原生环境，强制使用[HiPE][HiPE]编译，从而得到更快的编译速度
- test：测试环境，将加载一些额外的库(如[meck][meck])，打开调试信息，用于跑测试代码

不同发布环境将发布在不同的目录下，如prod环境默认将生成在`_build/prod/`下，无论顶层应用采用何种发布环境，依赖将始终只能使用prod环境发布。并且只有顶层依赖的default环境，可以被保存到rebar.lock中。

`rebar3 release`将按照default环境发布应用，通过`rebar3 as prod release`可以将应用在生产环境发布。具体环境配置及命令参考[Rebar3环境][rebar3_profiles]。

#### 2. 发布多个应用

Rebar3支持在rebar.config中定义多个应用的发布，多个应用可以共享配置：

	{relx, [{release, {myapp1, "0.0.1"},
         [myapp1]},
        {release, {myapp2, "0.1.0"},
         [myapp2]},
         
         % 共用配置
	{sys_config, "config/sys.config"},
	{vm_args, "config/vm.args"},
	
        {dev_mode, true},
        {include_erts, false},
        {extended_start_script, true}]}.
        
也可以独立配置：

	{relx, [
		{release, {myapp1, "0.0.1"},
         		[myapp1],
         		% 注意配置顺序和格式 各应用的独立配置是一个PropList
         		[{sys_config, "config/sys1.config"},
			{vm_args, "config/vm1.args"}]
		},
        	{release, {myapp2, "0.1.0"},
         		[myapp2],
         		[{sys_config, "config/sys1.config"},
			{vm_args, "config/vm1.args"},
			{overlay}]
		},	
	
        {dev_mode, true},
        {include_erts, false},

        {extended_start_script, true}]}.
        
#### 3. 应用依赖

定义于rebar.config deps中的依赖被获取后放在`_build/default/lib`目录下，默认并不会打包到应用的发布目录`_build/default/rel/myapp/lib`中，你需要在relbar.config的relx中指定应用依赖：

	{relx, [{release, { myapp, "0.1.0" },
	         [
	         % 指定应用依赖 mylib会先于myapp被启动
	         mylib, 
	         myapp]
	         },
	
	        {sys_config, "./config/sys.config"},
	        {vm_args, "./config/vm.args"},
	
	        {dev_mode, true},
	        {include_erts, false},
	
	        {extended_start_script, true}]
	}.


那么对于一些辅助lib呢，我们希望它被打包在应用发布目录中，但不希望它们被启动(它们可能根本不能启动)，一种方法是将mylib指定为`{mylib, load}`(参见[Issue1][], [Issue2])，列表中的依赖项默认被relx解释为`{mylib, permanent}`，即以常驻的方式启动应用。

#### 4. Overlays

Overlay允许用户定义一些文件模板和部署准备工作，如拷贝文件，创建文件夹等：

	{relx, [
	    {overlay_vars, "vars.config"},
	    {overlay, [{mkdir, "log/sasl"},
	               {template, "priv/app.config", "etc/app.config"}，
	               % root_dir是relx提供的变量 代表项目根目录
	               {copy, "\{\{root_dir\}\}/configures", "./"}]}
	]}.
	
Overlay可以如sys_config和vm_config一样，放在各应用的独立发布配置中。

更多关于Rebar3发布流程，发布配置，以及库升级等，参考[Rebar3发布][rebar3_releases]。

### 四. 总结

Rebar3无疑是个好东西，更先进的依赖管理，多节点发布，发布环境的概念，都是Rebar2 + Reltool所不能实现的，当前我们项目就使用的Rebar2.x，用于部署一个多节点的集群，遇到的问题：

- 依赖管理：各本地版本不一致问题，Rebar3的lock为依赖的一致性提供了保证。
- 多节点部署：Rebar2.x需要为每个节点创建release(create-node)，需要维护N份reltool.config和一份rebar.config。在Rebar3中只需一个rebar.config文件。并且可以灵活定义各节点配置文件(vm.args, sys.config)路径，更有利于项目结构管理和可读性。
- 开发模式：在本地开发时，Rebar2.x的generate和upgrade太慢了，前者可用二进制发布自己写脚本替代(用erl_call和节点通信)，后者可用reloader实现热更，这样提高了部署速度，却要自己维护节点交互脚本。Rebar3的dev_mode完美解决了这个问题。
- 环境管理：这一块的用处还有待挖掘和摸索。

Rebar3目前主要的缺点，在于relx文档匮乏，提供了很多好东西，但能传达到用户让用户理解和用上的很少。翻遍了[relx wiki][]，也没有找到应用独立配置环境(sys_config, vm_args等)的方法，最后是看了其配置解析模块[rlx_config.erl]才猜出来的格式= =。

### 五. 参考：

1. [Rebar3文档](http://www.rebar3.org/docs/getting-started)
2. [Rebar3文档中文翻译(部分)](https://github.com/zyuyou/rebar3_docs)
3. [relx wiki][]
4. [OTP Release 结构](http://erlang.org/doc/design_principles/release_structure.html)

[reltool]: http://erlang.org/doc/man/reltool.html
[relx]: https://github.com/erlware/relx
[rebar3_configuration]: http://www.rebar3.org/docs/configuration
[rebar3_profiles]: http://www.rebar3.org/docs/profiles
[rebar3_releases]: http://www.rebar3.org/v3/docs/releases
[HiPE]: http://erlang.org/doc/man/HiPE_app.html
[meck]: https://github.com/eproxus/meck
[relx wiki]: https://github.com/erlware/relx/wiki
[rlx_config.erl]: hub.com/erlware/relx/blob/master/src/rlx_config.erl
[Issue1]: https://github.com/erlware/relx/issues/483
[Issue2]: https://github.com/erlware/relx/issues/149

	