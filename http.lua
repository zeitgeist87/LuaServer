module(..., package.seeall)
require "request"
require "response"


function cleanupSessions()
	if timestamp-sessioncleanup>sessiontimeout then
		--cleanup old sessions every 20 minutes or so
		for k,v in pairs(sessions) do
			if timestamp-v.timestamp>sessiontimeout then
				--cleanup session
				sessions[k]=nil
			end
		end
		sessioncleanup=timestamp
	end
end

local function findEndOfHeader(buffer)
	local start,stop=buffer[#buffer]:find("\r\n\r\n",1,true)
	if start then
		return stop
	elseif #buffer>1 then
		local first=buffer[#buffer-1]:sub(-3)
		local second=buffer[#buffer]:sub(1,3)
		local start,stop = (first .. second):find("\r\n\r\n",1,true)
		if start then
			return stop - first:len()
		elseif #buffer>2 and buffer[#buffer-1]:len()<3 then
			local first=buffer[#buffer-2]:sub(-2)
			local second=buffer[#buffer-1]
			local third=buffer[#buffer]:sub(1,2)
			local start,stop = (first .. second .. third):find("\r\n\r\n",1,true)
			if start then
				return stop - first:len() - second:len()
			elseif #buffer>3 and buffer[#buffer-1]:len()==1 and buffer[#buffer-2]:len()==1 then
				if buffer[#buffer-3]:sub(-1)=="\r" and buffer[#buffer-2]=="\n" and buffer[#buffer-1]=="\r" and buffer[#buffer]:sub(1,1)=="\n" then
					return 1
				end
			end
		end
	end
	return nil
end

function receiveRequest(client)
	local buffer={}
	local len=0

	while len<=buffersize do
		local s, status, p = client:receive(buffersize)
		if status == "closed" then
			--needs to stay open
			return nil
		elseif p and p:len()>0 then
			table.insert(buffer,p)
			len = len + p:len()
		elseif s and s:len()>0 then
			table.insert(buffer,s)
			len = len + s:len()
		end

		if ((s and s:len()>0) or (p and p:len()>0)) and len>17 then
			local stop=findEndOfHeader(buffer)
			if stop then
				s=buffer[#buffer]
				--found end of header
				local msg=nil
				if stop ~= s:len() then
					msg=s:sub(stop+1)
					s=s:sub(1,stop)
					buffer[#buffer]=s
				end
				if #buffer==1 then
					s=buffer[#buffer]
				else
					s=table.concat(buffer)
				end
				--free buffer for gc
				buffer=nil

				local p1,p2,method,url,version =s:find("^(%a%a%a%a?) ([^%s]+) HTTP/(%d%.%d)\r\n")
				if method == "GET" or method == "POST" then
					headers={}
					local key,value
					while p1 do
						p1,p2,key,value =s:find("^([%a%-%.]+):%s+([^\r]+)\r\n",p2+1)
						if p1 then
							headers[key:upper():gsub("%-", "_")]=value:lower()
						end
					end
					--free buffer for gc
					s=nil


					local request=Request:create(client,method,url,version,headers,msg)
					if not request then
						return
					end

					local response=Response:create(request)
					request.response=response

					return request, response
				else
					--unsupported method bad request
					return nil
				end
			end
		end

		if status == "timeout" or status == "wantread" then
			coroutine.yield("wantread")
		elseif status == "wantwrite" then
			coroutine.yield("wantwrite")
		end
	end
	--request too big
	return nil
end


