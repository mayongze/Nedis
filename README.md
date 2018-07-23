# Nedis

基于Nginx的lua拓展模块实现Redis 节点的动态路由代理，从而达到主从单机模式redis高可用的目的。

需要至少3台sentinel监控节点，以及一个主从节点，当主节点宕机，sentinel检测到主节点宕机会自动把从节点提成主，从而通知到nedis模块，nedis模块修改全局的路由信息，将负载指向新选举出来的主节点上。

## 安装

1. 重新编译Nginx增加以下依赖模块

   - [stream-lua-nginx-module](https://github.com/openresty/stream-lua-nginx-module#installation)
   - [lua-resty-redis](https://github.com/openresty/lua-resty-redis#installation)
   - [lua-resty-core](https://github.com/openresty/lua-resty-core#synopsis)
   - [ngx_devel_kit(NDK)](https://github.com/simpl/ngx_devel_kit/archive/v0.2.19.tar.gz)

   **安装LuaJIT2.1**

   ```
   cd /usr/local/src
   wget http://luajit.org/download/LuaJIT-2.1.0-beta2.tar.gz
   tar zxf LuaJIT-2.1.0-beta2.tar.gz
   cd LuaJIT-2.1.0-beta2
   make PREFIX=/usr/local/luajit
   make install PREFIX=/usr/local/luajit
   ```

   **Nginx参考编译参数**

   ```
   ./configure --prefix=/export/servers/nginx --with-stream --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_stub_status_module --with-stream_ssl_module --with-pcre --with-ld-opt=-ljemalloc --with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib --add-module=/export/software/ngx_devel_kit-0.3.1rc1 --add-module=/export/software/lua-nginx-module-0.10.13 --add-module=/export/software/stream-lua-nginx-module-0.0.5
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