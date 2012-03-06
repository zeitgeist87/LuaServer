local decode = require("socket.url")

Request = {}
Request_mt = { __index = Request }

--local function filterNullBytes(s)
--	for i=1,s:len() do
--		if s:byte(i) == 0 then
--			return s:sub(1,i-1)
--		end
--	end
--	return s
--end

local function parseUrl(url)
	local params={}

	--shortcut
	if url=="/" or url=="/index.lua" then
		return url,params
	end

	local path=url:match("^(/[%a%d/%.%-_%%%+]*)")
	if not path then
		return nil
	end

	local query=url:match("%?([%%&%a%d=_%+]+)$")


	if query then
		for k,v in query:gmatch("([%a_]+)=([^&]+)") do
			--always check for null bytes (white lists gsub("\0","") does not work)
			params[k]=decode.unescape(v:gsub("%+"," "):gsub("%%00",""))
		end
	end
	--do not allow null bytes in path
	--/index.lua%00.jpg downloads the source code of index.lua
	--because null bytes are allowed in lua but not in the c functions underneath
	--http://en.wikipedia.org/wiki/Directory_traversal_attack
	--UTF8 Directory Traversal Vulnerability?
	--path=decode.unescape(path:gsub("%+"," "):gsub("%%00",""))
	path=path:gsub("%.+%s*/","")
	return path,params
end

function Request:create(client,method,url,version,headers,rest)
	local path,params=parseUrl(url)
	if not path then
		return nil
	end

	local new_inst = {response=true,client=client,sent=0,rest=rest,method=method,url=url,path=path,get=params,version=version,headers=headers}    -- the new instance
	headers.CONTENT_LENGTH = (headers.CONTENT_LENGTH and tonumber(headers.CONTENT_LENGTH)) or 0

	setmetatable( new_inst, Request_mt ) -- all instances share the same metatable
	return new_inst
end

function Request:receive()
	if self.method == "POST" and self.headers.CONTENT_LENGTH > 0 and self.sent<self.headers.CONTENT_LENGTH  then
		if self.rest then
			self.sent = self.sent + self.rest:len()
			local ret=self.rest
			self.rest=nil
			return ret
		else
			while true do
				local s, status, p = self.client:receive(buffersize)
				if s then
					self.sent = self.sent + s:len()
					return s
				elseif p then
					self.sent = self.sent + p:len()
					return p
				elseif status == "timeout" or status == "wantread" then
					coroutine.yield("wantread")
				elseif status == "wantwrite" then
					coroutine.yield("wantwrite")
				elseif status == "closed" then
					--close connection and exit
					coroutine.yield("close")
				end
			end
		end
	end
	return
end

function Request:receiveAll()
	if self.method == "POST" and self.headers.CONTENT_LENGTH > 0  then
		local buffer={}
		local ret=self:receive()
		while ret do
			table.insert(buffer,ret)
			ret=self:receive()
		end

		if #buffer==0 then
			--close connection and exit
			coroutine.yield("close")
		elseif #buffer==1 then
			return buffer[1]
		else
			return table.concat(buffer)
		end
	end
end



function Request:getPost()
	local params=self.post
	local headers=self.headers
	if not params and self.method == "POST" and headers.CONTENT_LENGTH > 0 and headers.CONTENT_LENGTH < 1048576 and headers.CONTENT_TYPE =="application/x-www-form-urlencoded"  then
		local query=self:receiveAll()
		params={}
		for k,v in query:gmatch("([%a_]+)=([%a%d%%%+_%-%.%*]+)") do
			--always check for null bytes (white lists gsub("\0","") does not work!)
			params[k]=decode.unescape(v:gsub("%+"," "):gsub("%%00",""))
		end
		self.post=params
	end

	if not params then
		params={}
		self.post=params
	end

	return params
end

function Request:getCookies()
	local params=self.cookie
	if not params and self.headers.COOKIE then
		local query=self.headers.COOKIE
		params={}
		for k,v in query:gmatch("(%$?%a+)%s*=%s*([%a%d%%%+_%-%.%*]+)") do
			if k:sub(1,1)~="$" then
				params[k]=v
			end
		end
		self.cookie=params
	end

	if not params then
		params={}
		self.cookie=params
	end

	return params
end

function Request.htmlspecialchars(s)
	if s then
		s=s:gsub("&","&amp;"):gsub("\"","&quot;"):gsub("'","&#039;"):gsub("<","&lt;"):gsub(">","&gt;")
	end
	return s
end


--seeded in server.lua
--math.randomseed(os.time())
--math.randomseed(socket.gettime() * 1e6)
local idcount=0

local function uniqueId()
	idcount=idcount+1
	if idcount>1000 then
		idcount=0
		seedRandom()
	end

	--TODO revert local alias for luajit?
	local random = math.random
	local buffer = {random(65536)-1,random(65536)-1,random(65536)-1,random(65536)-1,
	random(65536)-1,random(65536)-1,random(65536)-1,random(65536)-1}

	return table.concat(buffer)
end

function Request:getExistingSession()
	if self.session then
		return self.session
	end

	local cookies=self:getCookies()
	local sid=cookies.sid
	local sessions=sessions

	if sid then
		local session=sessions[sid]
		if session then
			if timestamp-session.timestamp<sessiontimeout then
				session.timestamp=timestamp
				self.session=session
				return session
			else
				sessions[sid]=nil
			end
		end
	end
	return
end

function Request:getSession()
	local s=self:getExistingSession()
	if s then
		return s
	end

	--create new session
	local sid
	local sessions=sessions
	repeat
		sid=uniqueId()
	until not sessions[sid]

	--TODO revert local alias for luajit?
	s={}
	sessions[sid]=s
	s.timestamp=timestamp
	s.sid=sid
	local cookies=self:getCookies()
	cookies.sid=sid
	self.response:setCookie("sid",sid,self:isSecure(),true)
	return s
end

function Request:changeSessionId()
	local s=self:getExistingSession()
	if s then
		self:killSession()

		--create new sid
		local sid
		local sessions=sessions
		repeat
			sid=uniqueId()
		until not sessions[sid]

		--TODO revert local alias for luajit?
		sessions[sid]=s
		s.timestamp=timestamp
		s.sid=sid
		self.cookie.sid=sid
		self.response:setCookie("sid",sid,self:isSecure(),true)
		return s
	end
end

function Request:killSession(sid)
	local cookies=self:getCookies()
	if not sid then
		sid=cookies.sid
	end

	if sid then
		sessions[sid]=nil
		cookies.sid=nil
		self.response.headers.SET_COOKIE=nil
		self.session=nil
	end
end


function Request:isSecure()
	return self.client.dohandshake ~= nil
end
