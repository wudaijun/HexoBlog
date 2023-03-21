# 第一次Clone下来，需要在当前目录执行该命令
init:
	# 参见: https://hexo.io/zh-cn/docs/index.html
	# 尽量通过教程方式安装 nvm npm hexo 工具链
	npm install
	npm install hexo-server --save
	npm install hexo --save
	# 初始化主题
	mkdir themes
	git clone https://github.com/theme-next/hexo-theme-next themes/next 
	cp _config.next.yml themes/next/_config.yml

# 如果init Error:
# xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory ....
# 执行该条命令 修改xcode-select 指向 注意自己的Xcode版本 有可能在Xcode-beta目录下
fix:
	sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

deploy:
	hexo generate
	cp -r source/assets public/
	cp source/CNAME public/
	cp source/favicon.png public/
	cp source/favicon.ico public/
	hexo deploy

server:
	export NODE_PATH=/usr/local/lib/node_modules
	hexo generate
	cp -r source/assets public/
	hexo server -p 4444

gen:
	hexo generate

clean:
	hexo clean
