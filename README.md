# Nedis

基于Nginx的lua拓展模块实现Redis 节点的动态路由代理，从而达到主从单机模式redis高可用的目的。

需要至少3台sentinel监控节点，以及一个主从节点，当主节点宕机，sentinel检测到主节点宕机会自动把从节点提成主，从而通知到nedis模块，nedis模块修改全局的路由信息，将负载指向新选举出来的主节点上。

## 安装

1. 重新编译Nginx增加以下依赖模块

   - [stream-lua-nginx-module](https://github.com/openresty/stream-lua-nginx-module#installation)
     将Lua的强大功能嵌入到Nginx流/ TCP服务器中
   - [lua-nginx-module](https://github.com/openresty/lua-nginx-module)
     将Lua的强大功能嵌入到Nginx HTTP服务器中
   - [lua-resty-redis](https://github.com/openresty/lua-resty-redis#installation)
     基于cosocket API的ngx_lua的Lua redis客户端驱动程序
   - [lua-resty-core](https://github.com/openresty/lua-resty-core#synopsis)
     OpenResty 组件的一部分,提供了对 lua-nginx-module Lua 接口的替换实现,和一些新接口
   - [ngx_devel_kit(NDK)](https://github.com/simpl/ngx_devel_kit/archive/v0.2.19.tar.gz)
     NDK（nginx development kit）模块是一个拓展nginx服务器核心功能的模块，第三方模块开发可以基于它来快速实现
     NDK提供函数和宏处理一些基本任务，减轻第三方模块开发的代码量
   - [luarocks](https://github.com/luarocks/luarocks)
     管理lua的插件和软件包
   - cjson.so
     lua的json库
   
   **编译安装**

   ```bash
   # 安装LuaJIT2.1
   wget http://luajit.org/download/LuaJIT-2.1.0-beta2.tar.gz
   tar zxf LuaJIT-2.1.0-beta2.tar.gz
   cd LuaJIT-2.1.0-beta2
   make PREFIX=/usr/local/luajit
   make install PREFIX=/usr/local/luajit
   # 如果 luajit安装到了自定义目录下面还需要添加一个软链接
   # ln -s /export/servers/nginx/openresty/luajit/lib/libluajit-5.1.so.2 /lib64/libluajit-5.1.so.2
   
   # 下载nginx
   wget 'http://nginx.org/download/nginx-1.14.0.tar.gz'
   tar -xzvf nginx-1.14.0.tar.gz
   cd nginx-1.14.0/
   
   export LUAJIT_LIB=/usr/local/luajit/lib
   export LUAJIT_INC=/usr/local/luajit/include/luajit-2.1
   
   # /export/software 目录里放置依赖的拓展模块 ngx_devel_kit-0.3.1rc1 lua-nginx-module-0.10.13 stream-lua-nginx-module-0.0.5
   ./configure --prefix=/export/servers/nginx \
   --with-stream \
   --with-http_ssl_module \
   --with-http_v2_module \
   --with-http_realip_module \
   --with-http_stub_status_module \
   --with-stream_ssl_module \
   --with-pcre \
   --with-ld-opt=-ljemalloc \
   --with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib \
   --add-module=/export/software/ngx_devel_kit-0.3.1rc1 \
   --add-module=/export/software/lua-nginx-module-0.10.13 \
   --add-module=/export/software/stream-lua-nginx-module-0.0.5
   
   # 使用4核心CPU编译
   make -j4
   make install
   ```

2. Nginx配置文件nginx.conf 文件下面添加 `include nginx-nedis.conf` 

3. 添加redis节点，nginx-nedis.conf文件新增

   ```
       server {
       	#代理监听端口
           listen 16401;
           proxy_pass sentinel-10.237.40.208-6401;
       }
   
       upstream sentinel-10.237.40.208-6401 {
           server 127.0.0.0:1;
           
           balancer_by_lua_block {
           # sentinel里的master name
   	    nedis.balancer("sentinel-10.237.40.208-6401")
          }
       }
   ```