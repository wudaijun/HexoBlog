### NODE.JS基本命令:

- node.js和npm 安装: https://nodejs.org/en/download/
- package.json: 位于每个项目根目录下，用于定义这个项目需要用到的各个模块及版本，以及项目本身的配置信息。`npm install`会自动根据package.json安装项目所需模块依赖（默认放在项目根目录的node_modules下）。[参考](http://javascript.ruanyifeng.com/nodejs/packagejson.html)。
- `NODE_PATH`: NODE中用来寻找模块所提供的路径注册环境变量。[参考](https://segmentfault.com/a/1190000002478924)。模块搜索顺序：当前目录向上递归，如果没有找到，则用NODE\_PATH下注册的路径。
- npm命令:

		npm install [包名 如果没有则安装当前目录package.json指定的所有依赖]
			-g --global: 全局安装，安装在path/to/gpm/../lib下，通常是/usr/local/lib。否则将安装下当前目录下(本地安装)
			--save --save-dev: 将包依赖写入到package.json的dependencies中
			
		参考: 	http://www.ruanyifeng.com/blog/2016/01/npm-install.html
				https://docs.npmjs.com/cli/install
				
		npm update 更新依赖
	
		
		