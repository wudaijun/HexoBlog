---
title: WordPress搭建历程
layout: post
tag: tool
categories: tool
---

记录一下搭建wordpress博客的过程，做备忘之用，仅供参考。

### 一. 前期准备

一台云服务器和一个域名(可选)。国内的服务器搭建网站需要备案，国外的话推荐linode，目前linode tokyo服务器应该是国内访问最快的，但是已经缺货了，而新开的singapore服务器线路优化又不是很好(ping 300+)，后来又换成了fremont，速度总算稳定了一些，ping值 210 左右。

<!--more-->

### 二. 部署wordpress

我的环境是 Ubuntu 14.04 LTS。

#### 1.安装 apache2 + php5 + mysql-server

	// apache
	sudo apt-get install apache2 // 安装完成后，在本地打开浏览器 http://云服务器IP地址 测试
	
	// php5
	sudo apt-get install php5	  
	sudo apt-get install libapache2-mod-php5
	
	// mysql
	sudo apt-get install mysql-server
	sudo apt-get install libapache2-mod-auth-mysql
	sudo apt-get install php5-mysql
	
	// 重启apache 如果遇到 ServerName 警告，可在/etc/apache2/apache2.conf 中，
	// 添加一行: ServerName localhost
	/etc/init.d/apache2 restart 
	
#### 2.下载解压 wordpress

	wget https://cn.wordpress.org/wordpress-4.2-zh_CN.tar.gz // 可去cn.wordpress.org获取最新版
	tar zxvf wordpress-4.2-zh_CN.tar.gz
	
#### 3.为wordpress 准备 mysql
	
	mysql -uroot -p
	mysql> CREATE DATABASE 网站数据库名
	mysql> GRANT ALL PRIVILEGES ON 网站数据库名.* to 用户名@localhost identified by '密码'
	mysql> exit
	
#### 4.配置 wordpress

	// 配置前面为wordpress准备的mysql数据库和用户
	cd wordpress
	mv wp-config-sample.php wp-config.php
	vim wp-config.php #在配置文件中，配置DB_NAME DB_USER DB_PASSWORD三项
	
#### 5.添加 wordpress 到 apache

	// 将wordpress中所有内容移动到 /var/www/html下
	// /var/www/html是apache的默认根目录
	sudo mv wordpress/* /var/www/html	
	
#### 6. 安装wordpress

本地浏览器中，输入 http://云服务器地址/wp-admin/install.php

安装向导提供网站管理的用户名密码等信息。即可完成安装

### 三. 完善wordpress

#### 1. 修改网站根目录

apache2默认目录为 /var/www/html，如果要更改到/var/www:

	1. 修改/etc/apache2/sites-available/000-default.conf，将其中的 DocumentRoot 改为 /var/www
	2. 执行: sudo mv /var/www/html/* /var/www/
	3. 重启: service apache2 restart
	

#### 2. 制作固定链接

要求: 
	
	1. Apache web server，安装了mod_rewrite模块:
	操作:
		sudo a2enmod rewrite
		或: sudo ln -s /etc/apache2/mods-available/rewrite.load /etc/apache2/mods-enabled/rewrite.load
		 
	2. 在WordPress的home目录:
	 	FollowSymLinks option enabled 
	 	FileInfo directives允许 (如 AllowOverride FileInfo 或 AllowOverride All) 
	操作:
		在/etc/apache2/apache2.conf中，找到<Directory /var/www/>标签，将其改为:
		<Directory /var/www/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
		</Directory>
		
	3. .htaccess文件 (如果找不到，当你激活漂亮固定链接时WordPress会尝试创建它) 如果你希望WordPress自动更新.htaccess，WordPress需要有这个文件的写权限。
	操作:
		在你的网站根目录(wordpress文件目录)中:
		sudo touch .htaccess
		sudo chmod 777 .htaccess //最粗暴的方式，方便wordpress自动写入

准备就绪后，在wordpress `管理页面->设置->固定链接`中可设置固定链接格式，地址为`http://xxx/wp-admin/options-permalink.php`。选定固定链接后，wordpress会自动尝试写入规则，如果写入失败，则会在最下方给出提示，让你尝试手动添加规则。

完成之后，固定连接就生效了。

#### 3. 更换主题

在wordpress中自带更换主题的功能，但默认需要FTP用户名和密码，因为web访问的用户不具有对服务器wordpress文件夹的相关操作权限。由于安装方式不一样，解决方案不一样。我最后找到比较有用的是[这里](http://www.piaoyi.org/php/Wordpress-To-perform-the-requested-action.html)提供的一些思路：

	// 先将wordpress相关文件全部改为 777
	sudo chmod 777 -R /var/www/wp*
	// 然后通过wordpress管理界面，主题能够安装成功了
	// 此时观察 wp-content/themes的写入者为www-data
	// 改回权限:
	sudo chmod 755 -R /var/www/wp*
	chown -R www-data /var/www/wp*
	
另外，推荐一个wordpress中文主题下载网站: http://www.wopus.org
	
#### 4. 关于主页

到目前为止，如果在本地浏览器直接输入`http://云服务器地址` 得到的将是apache的it works页面，这也是服务器上/var/www/index.html页面。而我们想使用的是/var/www/index.php作为我们的主页。此时删掉/var/www/index.html即可。

#### 5. 域名绑定

这个比较简单，在你的域名提供商中修改DNS指向为你的云服务器IP地址，然后在wordpress管理->设置 中修改站点地址为你的域名，就可以了。
	

###四. 参考文档:

1. [官方安装教程](http://codex.wordpress.org/zh-cn:%E5%AE%89%E8%A3%85WordPress)
2. [网友安装教程](http://blog.csdn.net/shineflowers/article/details/40979927)
3. [官方使用文档](https://codex.wordpress.org/zh-cn:Main_Page)
	
	
