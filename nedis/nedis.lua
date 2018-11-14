local cjson = require("cjson")
local redis = require "resty.redis"
local ngx_balancer = require "ngx.balancer"
local utils = require "nedis.utils.util"

-- 加载配置文件
local conf_loader = require "nedis.conf_loader"
local sentinel_list = conf_loader.sentinel_list
local sentinel_master_name_list = conf_loader.sentinel_master_name_list

local Nedis = {}

local timer_at = ngx.timer.at
local ngx_log = ngx.log
local CRIT = ngx.CRIT
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local DEBUG = ngx.DEBUG

-- 重试时间 每次*2
local retry_time = 1
-- 最大重试时间
local MAX_RETRY_TIME = 64

local set_current_peer = ngx_balancer.set_current_peer

-- 日志包装
local function log(lvl, ...)
  ngx_log(lvl, "[nedis] ", ...)
end

-- 创建定时器
local function create_timer(...)
  local ok, err = timer_at(...)
  if not ok then
    log(ERR, "nedis not create timer: ", err)
  end
end

-- 处理订阅
local function handle_sub(premature, host, port)
	-- 判断是否计时器提前执行,一般为重载配置或者关闭退出,在delay 0的时候 false
	if premature then
		return
	end

	local red = redis:new()
	local ok, err = red:connect(host, port)
	if err then
		log(ngx.DEBUG,"redis sentinel lost connection! err:", err, " host =>"..host..":", port," retry_time:",retry_time)
		-- 处理sentinel连接掉线错误 1秒 2秒 4秒 8秒 16秒 32秒 64秒
		create_timer(retry_time, handle_sub, host, port)
		-- 动态增长
		if retry_time < MAX_RETRY_TIME then
			retry_time = retry_time * 2
		end
		return
	end

	-- 加随机值,防止消息出错
	red:set_timeout (300000 + math.random(2000,4000))

	local res,err = red:subscribe("+switch-master")
	if not res then
		log(ERR,"redis sentinel subscribe [+switch-master] failed! err:",err,"host: ",host..":", port)
	end

	local function do_read_func(do_read)
		if do_read ~= false then
			log(DEBUG,"start read sentinel subscribe.","host: ",host..":", port)
			res, err = red:read_reply()
			if err then
				return nil, err
			end
			return res, nil
		end
	    -- 取消订阅
	    red:unsubscribe("+switch-master")
	    -- 回连接池
	    red:set_keepalive(1000,10)
	    return
	end

	-- 循环阻塞接收订阅消息
	while true do
		local res, err = do_read_func()
		if err == "timeout" then
			-- 处理timeout错误,判断下是否reload
			log(DEBUG,"lua tcp socket read timed out.")
		elseif err == "closed" then

			log(ERR,"sentinel nodes is lost.", host..":", port)
		    create_timer(1, handle_sub, host, port)
			break
		elseif err then
			-- 处理其他错误
			log(ngx.CRIT,"do_read_fun;read_reply error! message:",err,"host: ",host..":", port)
			do_read_func(false)
			break
		end
		if res then
			-- 取到master变化通知
			log(DEBUG,"host: ",host..":", port, " received sentinel +switch-master message:",cjson.encode(res))
			-- 结果长度一定为3
			local master_info = utils.split(res[3]," ")
			-- 判断ip端口和之前是否一致
			local backend = master_info[4]..":"..master_info[5]
			if backend ~= ngx.shared.nedis:get(master_name[1]) then
				ngx.shared.nedis:set(master_info[1], backend, 0)
				log(DEBUG, master_info[1].." success failover current addr:", ngx.shared.nedis:get(master_info[1]))			
			else
				log(DEBUG, master_info[1].."Has been failover by other threads, current addr:", ngx.shared.nedis:get(master_info[1]))	
			end
		end
		-- 检测下是否reload或者退出，防止worker进程出现down
		local exit_sign = ngx.worker.exiting()
		if exit_sign then
			log(DEBUG,"exit signal detected,break while!")
			-- worker退出跳出循环
			do_read_func(false)
			break
		end

	end  --while

end

local function get_sentinel_master_addr(red, name )
	local res, err = red:sentinel("get-master-addr-by-name",name)
	if err then
		ngx.log(ngx.ERR,"redis get-master-addr-by-name ["..name.."] error :",err)
		return
	end	
	return res
end

-- 获取sentinel下所有的master
local function get_all_curr_master()
	local red = redis:new()
	red:set_timeout(1000) -- 1 sec

	-- 这可以随机连一个,考虑第一次连不上的情况
	for i,v in ipairs(sentinel_list) do
	    local ok, err = red:connect(v[1], v[2])
	    if err then
			-- failed
			log(ERR,"redis connect failed: ", err)
			if #(sentinel_list) == i then
				return false
			end
	    else
			-- 成功则跳出
			break
	    end
    end

	-- 获取当前sentinel_list内的所有master_name
	local res, err = red:sentinel("masters")
	if err then
		ngx.log(ngx.ERR,"redis execution [sentinel masters] error :",err)
		return false
	end
	if res then
		for idx,value in ipairs(res) do
			-- 1.name 3.ip 5.port 9.flags[s_down,master,disconnected]
			local name = value[2]
			local ip = value[4]
			local port = value[6]
			local flags = value[10]
			
			log(DEBUG,"init worker,"..name.." current master:", cjson.encode(value))
			ngx.shared.nedis:set(name,ip..":"..port,0)
			log(NOTICE,name.." init route :",ngx.shared.nedis:get(name))
		end
	end

	local ok, err = red:close()
	if not ok then
		log(ERR,"failed to close: ", err)
		return false
	end		
	
	return true
end

-- redis链路初始化
local function init_redis_link()

	local ok = get_all_curr_master()
	if not ok then
		-- 抛异常
		log(CRIT,"fail to get master from the sentinel.")
		return
	end
	
	-- 创建定时任务订aaaaa阅sentinel failover消息
	-- 有几个sentinel 就建立几个订阅
	for i, v in ipairs(sentinel_list) do
		create_timer(0, handle_sub, v[1], v[2])
	end

	--create_timer(0, handle_sub, "127.0.0.1", 6403)
	--create_timer(0, handle_sub, "127.0.0.1", 6404)
	--create_timer(0, handle_sub, "127.0.0.1", 6405)
end

-- master 进程初始化
function Nedis.init()
	local pl_path = require "luarocks.path"
	-- ngx.conf.prefix 前缀路径 -p指定
	
	--local conf_path = pl_path.join(ngx.config.prefix(), "nedis.conf")
	--local config = assert(conf_loader.load(conf_path))
	--log(DEBUG,"conf :", cjson.encode(config))
end

function Nedis.init_worker()
	-- 从sentinel初始化当前链路信息
	if 0 == ngx.worker.id() then
		create_timer(0, init_redis_link)
	end
end

-- 设置动态负载
function Nedis.balancer(master_name)
	-- local port = ngx.var.server_port
	-- local remote_ip = ngx.var.remote_addr
	 local backend = utils.split(ngx.shared.nedis:get(master_name),":")
	 local ok,err = set_current_peer(backend[1],tonumber(backend[2]))
	 if not ok then
	     log(ERR,"failed to set the current peer sentinel-test err message:",err)
	     return
	 end
	 log(DEBUG, "init redis link,current peer ",backend[1],":",backend[2])
end

return Nedis
