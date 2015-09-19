deploy:
	hexo generate
	hexo deploy
	cp -r source/assets public/

theme:
	git clone https://github.com/wudaijun/Hexo-theme-light_cn themes/light_cn
