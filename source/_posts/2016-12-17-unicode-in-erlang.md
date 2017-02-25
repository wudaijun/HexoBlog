---
title: Erlang Unicode编码
layout: post
categories: erlang
tags: erlang

---

## Unicode基础

### 编码方式

定义字符集中每个字符的**codepoint(数字编码)**

- ASCII: 不用多说，编码空间为7位(0-127)
- [ISO 8859-1][]: 又称Latin-1，以ASCII为基础，在空置的0xA0-0xFF的范围内，加入96个字母及符号。编码空间为8位(0-255)
- UCS-2: 16位编码空间 又称基本多文种平面或零平面
- UCS-4: 32位编码空间 在UCS-2基本上，加入辅助平面(目前有16个辅助平面，至少需要21位)
- 注1: UCS(Universal Character Set, [通用字符集][])
- 注2: 以上四种编码都是向前兼容的，通常我们所说的Unicode编码指UCS-2和UCS-4，目前广泛运用的是UCS-2

<!--more-->
			
### 实现方式

实现方式将字符的数字编码存储在计算机字节中，由于节省空间和平台差异性等，衍生不同的实现方式

- [UTF-8][]: 一种变长编码，使用1-3个字节编码UCS-2字符集，1-6个字节可编码UCS-4字符集(目前只用最多四个字节即可表示UCS-4所定义的17个平面)。优点是兼容ASCII，节省空间，并且不存在字节序的问题
- [UTF-16][]: 和UTF-8类似，使用2个字节来编码UCS-2字符集(UCS-2中有预留的位用于实现UTF-16扩展多字节)，使用4个字节来编码UCS-4字符集。由于使用两个字节作为基本编码单位，UTF-16存在字节序的问题，通常使用BOM来解决
- [UTF-32][]: 32位定长编码，能够表示UCS-4字符集所有字符，但空间占用大，因此很少见
- 注1: UTF(Unicode Transformation Format, Unicode转换格式)
- 注2: BOM(byte-order mark, [字节顺序标记])

## Erlang中的Unicode

### Unicode表示

	%% 环境 Mac OSX Yosemite & Erlang OTP/19
	Eshell V8.1  (abort with ^G)
	1> L = "中文".
	[20013,25991] % Erlang lists存放的是字符的Unicode编码
	2> B = <<"中文">>.
	<<45,135>> % Erlang只知"中文"的Unicode编码[20013,25991]，并不知应该用何种实现方式(UTF8或其他)，默认它会将Unicode编码 rem 256，产生0-255间的编码(并按照Lantin-1解码)
	
	% 下面我们将考虑将"中文"转换为binary
	% 方案一. erlang:list_to_binary -> error
	3> list_to_binary(L). % 该函数支持的list只能是iolist(见后面术语参考)，否则Erlang并不知道你想将字符串转换为何种编码格式的binary
	** exception error: bad argument
	     in function  list_to_binary/1
	        called as list_to_binary([20013,25991])
	        
	% 方案二. unicode:characters_to_binary -> ok
	4> UTF8 = unicode:characters_to_binary(L).% 将L中的unicode编码转换为UTF8 binary
	<228,184,173,230,150,135>>
	5> UTF16Big = unicode:characters_to_binary(UTF8,utf8,utf16).
	<<78,45,101,135>> % 默认为Big Endian
	6> UTF16Little = unicode:characters_to_binary(UTF8,utf8,{utf16,little}).
	<<45,78,135,101>>
	
	% 方案三. 利用binary构造语法构建
	7> UTF8 = <<"中文"/utf8>>.
	<<228,184,173,230,150,135>>
	8> UTF8 = <<L/utf8>>. % Why ?
	** exception error: bad argument
	
在Erlang中，字符串就是整数列表，并且这个整数可以无限大，lists将保存其中每个字符的Unicode编码，只要lists中的整数是有效的Unicode codepoint，就可以找到对应的字符。因此也就不存在UTF8/UTF16格式的lists字符串一说。而binary的处理则要麻烦一些，Erlang用UTF8作为Unicode在binary上的实现方式，unicode模块提供了这方面丰富的unicode编码处理接口。

### Unicode使用
 
	8> io:format("~s", [L]).
	** exception error: bad argument
     in function  io:format/3
        called as io:format(<0.50.0>,"~s",[[20013,25991]])
	9> io:format("~p", [L]).
	[20013,25991]ok
	10> io:format("~ts", [L]).
	中文ok
	11> io:format("~s", [UTF8]).
	ä¸­æok
	12> io:format("~p", [UTF8]).
	<<228,184,173,230,150,135>>ok
	13> io:format("~ts", [UTF8]).
	中文ok
	
先解释几个Erlang术语：

- [iolist][]: 0-255编码(Latin-1)的lists，binary，或它们的嵌套，如`[["123",<<"456">>],<<"789">>]`
- unicode binary: UTF8编码的binary(Erlang默认使用UTF8 binary编码unicode)
- charlist: UTF8编码的binary，或包含有效unicode codepoint的lists，或它们的嵌套，如`[<<"hello">>, "中国"]`


`~s`只能打印iolist，binary，或atom，因此不能直接打印中文lists(无法解码超过255的codepoint)或UTF8 binary(会按字节解释，出现乱码)。

`~ts`则可打印charlist和unicode binary。

`~p`如果不能打印出ASCII(0-127)字符，则直接打印出原生Term，不会对Unicode编码进行处理。


参考：

1. http://erlang.org/doc/man/unicode.html
2. http://erlang.org/doc/apps/stdlib/unicode_usage.html


			
[通用字符集]: https://zh.wikipedia.org/wiki/%E9%80%9A%E7%94%A8%E5%AD%97%E7%AC%A6%E9%9B%86
[UTF-8]: https://zh.wikipedia.org/wiki/UTF-8
[UTF-16]: https://zh.wikipedia.org/wiki/UTF-16
[UTF-32]: https://zh.wikipedia.org/wiki/UTF-32
[字节顺序标记]: https://zh.wikipedia.org/wiki/%E4%BD%8D%E5%85%83%E7%B5%84%E9%A0%86%E5%BA%8F%E8%A8%98%E8%99%9F
[iolist]: http://www.cnblogs.com/me-sa/archive/2012/01/31/erlang0034.html
[ISO 8859-1]: https://zh.wikipedia.org/wiki/ISO/IEC_8859-1
