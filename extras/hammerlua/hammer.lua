local _M = {}
local w = require'winapi'
local prevw

do
	local prevp,prevp_w
	function _M.process()
		if prevp_w ~= prevw then
			prevp_w = prevw
			if prevp then prevp:close() end
			prevp = prevw and prevw:get_process()
		end
		return prevp
	end
end

-- returns hammer only if it is ontop
local function gethammer()
	if prevw then
		local proc = prevw:get_process()
		local pid = proc:get_pid()
		proc:close()
		if pid~= 1 then return prevw end
	end
	
	if prevw then
		print("hammer died")
		prevw = nil
	end

	local hammer = winapi.get_foreground_window()
	local proc = hammer and hammer:get_process()
	local procname = proc and proc:get_process_name()

	if proc then
		proc:close()
	end

	if procname ~= "hammer.exe" then


		return nil, "not hammer"
	end

	for i = 1, 10 do
		local newhammer = hammer:get_parent()

		if not newhammer or not newhammer:get_text() then


			break
		end

		print("parent", newhammer:get_text())

		hammer = newhammer
	end

	prevw = hammer
	print("Found hammer", hammer)

	return hammer
end

local function inhammer()
	if not prevw or not prevw:is_visible() then return false end
	local fg = winapi.get_foreground_window()
	local isok = fg == prevw
	if isok then return true end

	return false, fg
end

local function getmap(hammer)
	local txt = hammer:get_text()
	txt, n = txt:gsub('^Hammer %- %[', '')
	if n ~= 1 then return end
	txt, n = txt:gsub('(%.vmf) %- [^%-]+%]$', '%1')
	if n ~= 1 then return end

	return txt
end

_M.map = getmap
_M.ontop = inhammer
_M.get = gethammer
_M.process = getproc
return _M