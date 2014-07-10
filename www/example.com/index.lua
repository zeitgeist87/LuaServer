local db = require "common.db"
local log = require "common.log"
local lfs = require "lfs"

-- the templates can only see global variables
articles = db.get("articles") or {}
welcomeMessage = db.get("welcomeMessage")
dependencies = db.get("dependencies") or {}



post, files = req:getPost()

if files then
	lfs.mkdir(req.cwd .. "/uploads/")
	for _, file in pairs(files) do
		local path=req.cwd .. "/uploads/" .. file.name
		local fd=io.open(path,"w")
		if fd then
			local t=file:read()
			while t do
				fd:write(t)
				t=file:read()
			end
			fd:close()
		end
	end
end

if post and post.title and post.text
		and post.title ~= "" and post.text ~= "" then
	articles[#articles + 1] = {
		title = post.title,
		text = post.text,
		date = os.time()
	}
	db.put("articles", articles)
	db.sync()
end

table.sort(dependencies, function(a,b) return a.name < b.name end)
table.sort(articles, function(a,b) return a.date > b.date end)

printTemplate("templates/index.lsp")
