
local shell = {}

function shell.escape(args)
	local ret = {}
	for _,a in pairs(args) do
		s = tostring(a)
		if s:match("[^A-Za-z0-9_/:=-]") then
			s = '"'..s:gsub('"', "\\\"")..'"'
		end
		table.insert(ret,s)
	end
	return table.concat(ret, " ")
end

function shell.run(args)
	local h = io.popen(shell.escape(args))
	local outstr = h:read("*a")
	return h:close(), outstr
end

function shell.execute(args)
	return os.execute(shell.escape(args))
end

return shell

