---
title: 聊聊Golang服务器热修复
layout: post
categories: gameserver
tags:
- golang
- gameserver
---

SLG游戏大量的运算和逻辑都在服务器，线上较易出现各种BUG，而热更是在各种防御和容错措施后的最后一道屏障(再往后就是停服维护导致不可用了)，Golang具备非常好的开发效率和运行效率，但和大部分的静态语言一样，它本身并不支持热更，能找到的关于Golang服务器热更的成熟实践不多，能想到的方案大概有以下几种:

1. 改造或剥离为无状态服务器灰度部署。对游戏服务器而言，说了又好像没说...
2. AB服切换方案，这里面还分为: 不停服(部分跨服服务可能降级)和半停服(缩小停服窗口)，切大服(整个集群)切小服(部分节点)等
3. 代码热修复方案，更适合有状态服务器体质的线上bugfix方案

前两种方案与语言无关，且与具体架构和业务强相关，不在这里展开，本文主要介绍两种基于[Go Plugin](https://pkg.go.dev/plugin)的Golang代码热修复技术。

<!--more-->

#### plugin package swap

该方案的思路是，将业务package编译为plugin，动态加载和替换，再通过`plugin.Lookup`来动态查找和使用函数。Go Plugin从2016年发布以来一直不温不火，Go官方对Plugin的维护升级更谈不上上心(两者互为因果)，对于大部分开发者而言，面临Plugin的诸多限制，还是要花一些时间踩坑的:

1. Plugin本身的编译链接机制(如何整合到已有CI/CD流程中)
2. 被swap的Plugin内存永远不会被释放 (那么如何确保内存和引用安全性)
3. 不同版本Plugin中的数据类型(哪怕没改)会被认为是不同类型(相当于来自不同的package)，无法相互赋值和转换 (如何限制或者检查宿主代码对plugin package的不安全依赖)

有些开源库能解决部分问题，如[hotswap](https://github.com/edwingeng/hotswap)能解决问题1，以及部分解决23。不过对于游戏服务器而言，要真正将Plugin应用于生产环境热更，需要更完备的解决方案:

1. 安全性问题: 
	- 如何确保plugin package是可被安全替换的，包括全局符号、内部数据状态、回调注册等，理论上说，不应该有宿主代码对插件代码和数据的引用，即使有，也应该确保被记录下来并统一动态替换，那么如何确保这些依赖不被遗漏？
	- 如果执行动态替换失败，比如前后函数签名不一致(如何检查)，或者宿主代码仍有对old plugin的引用(如何检查)，如何控制其负面影响或安全回滚，避免因为热更失败导致更严重的问题
2. 易用性问题:
	- 热更即修复: 如何做到一份bugfix代码，既可用于热更也可用于正常修复，减少热更对开发方式的侵入性(比如通过代码生成器生成热更相关胶水代码)，简化CICD以及开发和QA负担
	- 重启即原生: 服务器每次重启后，都应该自动以原生编译(而非plugin lookup)的方式运行，提供更好的一致性和运行时性能，并且提供一个安全边界

也就是说除了热更流程本身，可能还需要编译期检查工具、运行时检查工具、运行时失败回滚机制、胶水代码生成工具等一整套工具链来提升易用性和安全性。不过相比这些机制，更大的前置成本可能还在于业务代码层需要使用合适的维度和粒度来划分和组织pacakge，事实上，我们是由于在之前领域驱动设计实践中，借助洋葱架构和子领域模型等理念，已经对完成了对业务代码的拆分和隔离(出于可维护、可测试、可扩展考量)，才开始考虑使用plugin package swap方案的。按照我们自己的实践，这套机制能覆盖70%以上的业务代码，并且其间为提升热更安全性和易用性所付出的成本可能会高于热更机制本身。具体的实现细节和框架实现以及领域模型设计强相关，这里不展开。

#### plugin function patch

另一种热更方案也是基于Plugin，但不是将Plugin作为整个package的可替换实现，而是只通过Plugin实现要替换的函数补丁:

```
func GetPatchFuncs() map[string]string {
	//map的key是新函数在本补丁文件中的名称(以便通过plugin.Lookup找到该函数地址)
	//map的value是旧函数在旧可执行文件中的名称(应该用nm来查，以便通过CGO dlsym找到该函数地址) 
	list := map[string]string{
		"TestHandlerHotFix": "main.TestHandler",
	}
	return list
}
```

在加载Plugin后，借助`plugin.Lookup("GetPatchFuncs")`拿到Patch映射，再通过`plugin.Lookup`和`CGO dlsym`分别找到新旧函数地址，最后借助`mprotect`+`memcpy`+`hardcode asm`修改旧函数地址入口内容为: `jmpq 新函数地址`。

这套方案借鉴经典的C函数补丁热更方案，它的好处是，业务代码不需要大的调整，缺点也有不少:

1. 相较package swap，函数补丁灵活性没有那么高
2. 需要为了热更，暴露package过多的类型和函数，对代码设计有很强的侵入性
3. Patch函数修复后，还需要在业务逻辑中再修复一次
4. 由于是函数地址替换，因此还会受到编译器内联优化的影响
5. 由于用了C和汇编，与底层耦合过重，跨平台和跨系统可移植性只能自己保证

#### 谨慎评估

一个比较有意思的论题是，如果线上服务器频繁出现BUG，那么是应该先整一套热修复方案，还是先增强代码交付质量？毕竟，热修复这种机制，属于"最好不用，但好像又最好得有"。以上两种热修复方案从实现机制上来说都不难，但涉及的前置业务代码重构、安全性和易用性相关工具链、CICD流程调整等引入的成本和风险性要谨慎评估，不能由于提升可用性的机制引入的风险和开发负担导致反而降低了服务器稳定性。

#### 非代码热修复

一个完整的有状态游戏服务器主要包含三部分: 代码、数据和配置，因此除了代码热修复之外，这里也提一下配置热更和数据热修复。

配置问题是游戏服务器线上问题的主要来源之一，大部分的游戏服务器都会提供一定的配置热更能力，这个实现起来不难，比如我们使用全容器部署，为了做到宿主机隔离，配置热更是通过将配置导入到DB然后Reload来实现的，并借助`atomic.Value`保证配置的并发读写安全性。对于逻辑层而言，尽可能不要缓存配置，而是每次都从配置中读取最新值。

至于数据热修复，SLG游戏服务器基于性能、响应延迟、逻辑耦合强等各种原因，通常都是有状态+定时落地的，尽管我们尽可能从防御性编程、架构可靠性、线上监控、快速部署恢复等手段来尽可能提升服务器可用性，但各种预期之外的错误和故障仍然可能导致处理流程中断，引发各种数据不一致性问题。而按照经验，处理这些故障导致的数据修复，往往比服务恢复更可能成为"可用性瓶颈"。因此，为了最大程度提升玩家体验，一种或多种不停服修复数据方案是需要被考虑并长期维护的。按照我们的经验，大概可以从以下几个维度来考虑:

- Lazy Fix: 对于常见的数据不一致，做一套Fix流程，并且手动(如通过GM)或者自动(如服务器启动、玩家上线时)开启
- Lua Fix: 接入Lua(如[gopher-lua](https://github.com/yuin/gopher-lua))并暴露核心的数据API以便通过Lua做一些临时的数据诊断和修复
- Reflect Fix: 基于Go Reflect实现一套简单的DSL，支持结构体嵌套字段的读取和赋值
- DB Fix: 强制带LRU的数据刷盘，修改DB，最后Reload

这些都和业务框架耦合较重，不展开，仅仅提供一些思路。


