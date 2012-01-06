Response = {}
Response_mt = { __index = Response }

function Response:create(request)
	local new_inst = {request=request,status=200,statusmsg="OK",headers={TRANSFER_ENCODING="chunked"},buffer={},len=0,
			headerssent=false,headerssending=false,headerslen=0,headersindex=1,firstchunk=true}
	if request.headers.CONNECTION=="keep-alive" then
		new_inst.headers.CONNECTION="keep-alive"
	end

	if request.version~="1.1" then
		new_inst.headers.TRANSFER_ENCODING=nil
	end


	setmetatable( new_inst, Response_mt ) -- all instances share the same metatable
	return new_inst
end

function Response:flush(lastchunk)
	local chunked=self.headers.TRANSFER_ENCODING == "chunked" and self.headerssent
	local buffer=self.buffer

	if chunked and lastchunk then
		table.insert(buffer,"\r\n0\r\n\r\n")
		if self.len<=0 then
			chunked=false
			self.len=7
		end
	end

	if self.len>0 then
		if chunked then
			local pattern = "%X"
			table.insert(buffer,self.headersindex,"\r\n")
			table.insert(buffer,self.headersindex,pattern:format(self.len-self.headerslen))
			if not self.firstchunk then
				table.insert(buffer,self.headersindex,"\r\n")
			end
			self.firstchunk=false
			self.headersindex=1
			self.headerslen=0
		end

		local data=nil
		if #buffer==1 then
			data=buffer[1]
		else
			data=table.concat(buffer)
		end

		local pos=0
		local client=self.request.client
		buffer=nil
		self.buffer={}
		self.len=0

		while true do
			local i, status, p = client:send(data,pos+1)
			if i then
				return
			elseif status == "timeout" or status=="wantwrite" then
				coroutine.yield("wantwrite")
			elseif status == "wantread" then
				coroutine.yield("wantread")
			elseif status == "closed" then
				--close connection and exit
				coroutine.yield("close")
			end
			pos=p
		end
	end
end



function Response:redirect(location)
	self.headers.LOCATION=location
	self.status=302
	self.statusmsg="Found"
	self:sendHeaders()
end

function Response:send_with_headers(...)
	-- headers have been sent, send only data
	self.send = self.send_data
	self:sendHeaders()
	self.headerssent=true
	self:send_data(...)
end

function Response:send_data(...)
	local buffer=self.buffer
	local len=self.len
	for n=1,select('#',...) do
		local v = tostring(select(n,...))
		table.insert(buffer,v)
		len = len + v:len()
	end

	self.len=len
	if len>=buffersize then
		self:flush()
	end
end

-- initially "send" also includes headers
Response.send = Response.send_with_headers


function Response:sendHeaders()
	if not self.headerssending then
		local headers=self.headers
		local buffer=self.buffer

		self.headerssending=true
		-- headers have been sent, send only data
		self.send = self.send_data
		self:send("HTTP/",self.request.version," ",self.status," ",self.statusmsg,"\r\n")

		if headers.CONTENT_LENGTH then
			headers.TRANSFER_ENCODING=nil
		end

		for k,v in pairs(headers) do
			self:send(k:gsub("_", "%-"),": ",v,"\r\n")
		end
		self:send("\r\n")
		self.headerssent=true
		self.headerssending=false
		self.headerslen=self.len
		self.headersindex=#buffer+1
	end
end

function Response:sendFile(fd)
	local ret=fd:read(buffersize)
	local count=0
	while ret do
		count=count+1
		if count==50 then
			--let others do something
			count=0
			coroutine.yield()
		end
		self:send(ret)
		ret=fd:read(buffersize)
	end
end

function Response:setCookie(k,v,s,h)
	local cookie=k .. "=" .. v

	if s then
		cookie=cookie .. "; secure"
	end

	if h then
		cookie=cookie .. "; HttpOnly"
	end

	local headers=self.headers
	if headers.SET_COOKIE then
		headers.SET_COOKIE=headers.SET_COOKIE .. "; " .. cookie
	else
		headers.SET_COOKIE=cookie
	end
end
