---
title: Hexo使用mathjax渲染公式
layout: post
categories: tool
mathjax: true
tags:
- hexo
---

最近有在博客中嵌入公式的需求，目前主要有两个数学公式渲染引擎mathjax和KaTeX，前者应用更广泛，支持的语法更全面，因此这里简述将mathjax整合到hexo。

#### 1. 替换Markdown渲染器

	npm uninstall hexo-renderer-marked --save
	npm install hexo-renderer-kramed --save

hexo-renderer-karmed渲染器fork自hexo-renderer-marked，对mathjax的支持更友好，特别是下划线处理(marked会优先将`_`之间的内容斜体转义)
	
#### 2. 挂载mathjax脚本
	
在主题`layout/_partial/`目录下添加mathjax.ejs:

<!--more-->

	<!-- mathjax config similar to math.stackexchange -->
	<script type="text/x-mathjax-config">
	  MathJax.Hub.Config({
	    tex2jax: {
	      inlineMath: [ ['$','$'], ["\\(","\\)"] ],
	      processEscapes: true
	    }
	  });
	</script>
	
	<script type="text/x-mathjax-config">
	    MathJax.Hub.Config({
	      tex2jax: {
	        skipTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
	      }
	    });
	</script>
	
	<script type="text/x-mathjax-config">
	    MathJax.Hub.Queue(function() {
	        var all = MathJax.Hub.getAllJax(), i;
	        for(i=0; i < all.length; i += 1) {
	            all[i].SourceElement().parentNode.className += ' has-jax';
	        }
	    });
	</script>
	
	<script type="text/javascript" src=theme.cdn.mathjax + "/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML">
	</script>
	
如果用的是jade模板，则添加mathjax.jade:
	
	//mathjax config similar to math.stackexchange
	script(type="text/x-mathjax-config").
	  MathJax.Hub.Config({
	    tex2jax: {
	      inlineMath: [ ['$','$'], ["\\(","\\)"] ],
	      displayMath: [ ['$$','$$'], ["\\[","\\]"] ],
	      processEscapes: true
	    }
	  });
	script(type="text/x-mathjax-config").
	  MathJax.Hub.Config({
	    tex2jax: {
	      skipTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
	    }
	  });
	script(async, type="text/javascript", src=theme.cdn.mathjax + '/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML')

在`_partial/after_footer.ejs`中添加:

	<% if (page.mathjax){ %>
	<%- partial('mathjax') %>
	<% } %>
	
如果是jade模板，则在`_partial/after_footer.jade`中添加:
	
	if page.mathjax == true
	  include mathjax
	
#### 3. 配置

在主题_config.yml中配置mathjax cdn:
	
	cdn:
		mathjax: https://cdn.mathjax.org

当需要用到mathjax渲染器时，在文章头部添加`mathjax:true`:

	layout: post
	mathjax: true
	...
	
只有添加该选项的文章才会加载mathjax渲染器。
	
#### 4. 支持mathjax的Markdown编辑器:

- [Qute](www.inkcode.net/qute) 原生支持mathjax，界面有点Geek。
- [Macdown](https://macdown.uranusjr.com/): Macdown原生不支持mathjax，在md文件中添加(注意https，Macdown为了安全，只会加载https的远程脚本):

		<script type="text/javascript" src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS_HTML">
	    MathJax.Hub.Config({
	        tex2jax: {
	            inlineMath: [ ['$','$'], ["\\(","\\)"] ],
	            displayMath: [ ['$$','$$'], ["\\[","\\]"] ],},
	        TeX: {equationNumbers: {
	            autoNumber: "AMS"
	          },Augment: {  Definitions: {
	           macros: {
	             overbracket:  ['UnderOver','23B4',1],
	             underbracket: ['UnderOver','23B5',1],
	           }
	         }}},
	    });
		</script>
	
#### 5. 示例:

	行内公式: $$ a+b=c $$
	
	行间公式:
	
	$$
	\left( \begin{array}{ccc}
	a & b & c \\
	d & e & f \\
	g & h & i
	\end{array} \right)
	$$
	

得到:

行内公式: $ a+b=c $
	
行间公式:
	
$$
\left( \begin{array}{ccc}
a & b & c \\
d & e & f \\
g & h & i
\end{array} \right)
$$
	
具体mathjax语法，这里有一篇不错的[博客](http://jzqt.github.io/2015/06/30/Markdown%E4%B8%AD%E5%86%99%E6%95%B0%E5%AD%A6%E5%85%AC%E5%BC%8F/)。