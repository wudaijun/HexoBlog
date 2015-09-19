deploy:
	hexo generate
	cp -r source/assets public/
	cp source/CNAME public/
	hexo deploy

server:
	hexo generate
	cp -r source/assets public/
	hexo server

theme:
	git clone https://github.com/wudaijun/Hexo-theme-light_cn themes/light-cn
