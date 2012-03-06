debug = nil

local socket=require "socket"
local ssl=require "ssl"
--require "profiler"

--config
wwwdir="www"
dbfile="db/data.db"
--set to nil if you don't want vhosts
defaultdomain="localhost"
usestatcache=true

buffersize=4096
mimetypes={
["js.gz"]="application/x-javascript",
js="application/x-javascript",
htm="text/html;charset=UTF-8",
["htm.gz"]="text/html;charset=UTF-8",
html="text/html;charset=UTF-8",
["html.gz"]="text/html;charset=UTF-8",
txt="text/plain;charset=UTF-8",
css="text/css",
["css.gz"]="text/css",
jpg="image/jpeg",
jpeg="image/jpeg",
ogv="video/ogg",
ico="image/vnd.microsoft.icon",
png="image/png"}


local httpsparams = {
	mode = "server",
	protocol = "tlsv1",
	key = "server.pem",
	certificate = "server.cert",
	verify = {},
	options = {"all", "no_sslv2"},
	ciphers = "ALL:!ADH:@STRENGTH",
}
httpport=8080
httpsport=8081
localtimeoffset=2*60*60
sessiontimeout=30*60
bytecachetimeout=24*60*60
local sockettimeout=5*60
rewriterules={}
--rewrite rule example
table.insert(rewriterules,function(req)
		local year,month,day,id=req.path:match("^/(%d%d%d%d)/(%d%d)/(%d%d)/([%w%-_]+)")
		if year then
			id=id:gsub("%-","_")
			req.path="/article.lua"
			req.get.year=year
			req.get.month=month
			req.get.day=day
			req.get.id=id
			return true
		end
		return false
	end)
--config


--global vars
os.setlocale("C","numeric");
os.setlocale("C","time");
os.setlocale("C","collate");
local rlist = {}
local slist = {}
local threads = {}
timestamp = os.time()
sessions={}
sessioncleanup=timestamp


--global vars

require "http"
require "handler"
require "db"

db.load()

local function removeByValue(list,value)
	for i,v in ipairs(list) do
		if value==v then
			table.remove(list,i)
			break
		end
	end
end

local function handleConnection(client)
	while true do
		timestamp=os.time()
		local req, res=http.receiveRequest(client)
		if req then
			handler.handleRequest(req,res)

			res:flush(true)

			if res.headers.CONNECTION~="keep-alive" then
				return
			end
		else
			return
		end
	end
end

local function initHttp(client)
	client:settimeout(0)
	table.insert(rlist,client)
	threads[client]=coroutine.create(function() handleConnection(client) end)
end

local function resumeInitHttps(client)
	local succ,msg = client:dohandshake()
	if succ then
		table.insert(rlist,client)
		threads[client]=coroutine.create(function() handleConnection(client) end)
	elseif msg=="wantread" then
		removeByValue(rlist,client)
		removeByValue(slist,client)
		table.insert(rlist,client)
	elseif msg=="wantwrite" then
		removeByValue(rlist,client)
		removeByValue(slist,client)
		table.insert(slist,client)
	else
		removeByValue(rlist,client)
		removeByValue(slist,client)
		client:close()
	end
end

local function initHttps(conn,context)
	conn:settimeout(0)
	client = ssl.wrap(conn, context)
	if client then
		client:settimeout(0)
		resumeInitHttps(client)
	else
		conn:close()
	end
end

local function resumeThread(client)
	local status,msg=coroutine.resume(threads[client])

	if msg=="wantread" then
		removeByValue(rlist,client)
		removeByValue(slist,client)
		table.insert(rlist,client)
	elseif msg=="wantwrite" or (status and not msg and coroutine.status(threads[client])~="dead")  then
		removeByValue(rlist,client)
		removeByValue(slist,client)
		table.insert(slist,client)
	else
		threads[client]=nil
		removeByValue(rlist,client)
		removeByValue(slist,client)
		client:close()
	end
end



function seedRandom()
	local function bytes_to_int(b1, b2, b3, b4)
		local n = b1 + b2*256 + b3*65536 + b4*16777216
		return n
	end

	local f=io.open("/dev/urandom","r")
	local t

	if f then
		t=bytes_to_int(f:read(4):byte(1,4))
	else
		t=os.time()
	end

	--t=2147483648
	t=(t > 2147483647) and (t - 4294967296) or t
	print(t)
	math.randomseed(t)

	--print(math.random(3)-1,math.random(3)-1,math.random(3)-1,math.random(3)-1)
end

local function mainLoop()
	local sock = socket.bind("*", httpport)
	local ssock = socket.bind("*", httpsport)
	local context=ssl.newcontext(httpsparams)

	local ip, port = sock:getsockname()
	print("Port: " .. port)
	print("Ip: " .. ip)

	local ip, port = ssock:getsockname()
	print("Port: " .. port)
	print("Ip: " .. ip)

	sock:settimeout(0)
	ssock:settimeout(0)
	table.insert(rlist,sock)
	table.insert(rlist,ssock)

	local timeoutcount=0

	--after timeoutcountlimit timeouts a cleanup is forced(for session and bytecode cleanup
	local timeoutcountlimit=sessiontimeout/5
	local timeoutdiff=sockettimeout/5

	seedRandom()	
	collectgarbage("setpause",500)

	--profiler.start()
	while true do
		--select blocks max for 5 secs, so lua is max for 5 secs unresponsive
		local r,s,err = socket.select(rlist,slist,5)
		if err=="timeout" then
			timeoutcount=timeoutcount+1
			--profiler.stop()
			--os.exit()
			--process is idle so do some cleanup
			if timeoutcount>timeoutcountlimit then
				timestamp=os.time()
				db.syncIfChanged()
				http.cleanupSessions()
				handler.cleanupCache()
				rlist = {sock,ssock}
				slist = {}
				threads = {}
				r=nil
				s=nil
				err=nil
				timeoutcount=0
				collectgarbage("collect")
			end
		else
			--force cleanup next sockettimeout
			timeoutcount=timeoutcountlimit-timeoutdiff
			if r then
				for _,v in ipairs(r) do
					if v==sock then
						--new client
						local client = sock:accept()
						if client then
							initHttp(client)
						end
					elseif v==ssock then
						local client = ssock:accept()
						if client then
							initHttps(client,context)
						end
					elseif threads[v] then
						resumeThread(v)
					elseif v.dohandshake then
						--https socket handshake not jet finished
						resumeInitHttps(v)
					end
				end
			end

			if s then
				for _,v in ipairs(s) do
					if threads[v] then
						resumeThread(v)
					elseif v.dohandshake then
						--https socket handshake not jet finished
						resumeInitHttps(v)
					end
				end
			end
		end
	end

end


mainLoop()

