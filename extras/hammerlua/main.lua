local w = require'winapi'
socket = require("socket")
local wx = require'wx'
local Hammer = require'hammer'
local svn = require'svn'
local Point = wx.wxPoint
local Size = wx.wxSize
local ffi = require'ffi'
print"\nStarting luahammer"
local Path=require'path'


local ID = setmetatable({}, {
	__index = function(self, k)
		local val = wx.wxNewId()
		self[k] = val

		return val
	end
})

local process = winapi.get_current_process()
local winapi_us_window

function window()
	if winapi_us_window then return winapi_us_window end
	winapi_us_window = winapi.window_from_handle(tonumber(ffi.cast('uintptr_t', ffi.cast('void *', frame:GetHandle()))))

	return winapi_us_window
end

function sleep(sec)
	wx.wxMilliSleep(sec * 1000)
end

local dbg = print
local printerr = print
local lx, ly, lw, lh = 0, 0, 0, 0

function doresize(hammer, frame)
	local x, y = hammer:get_position()
	local w, h = hammer:get_bounds()
	local mod

	if lx ~= x then
		mod = true
		lx = x
	end

	if ly ~= y then
		mod = true
		ly = y
	end

	if lw ~= w then
		mod = true
		lw = w
	end

	if lh ~= h then
		mod = true
		lh = h
	end

	if mod then
		local bw, bh = frame:GetSize()
		bw, bh = bw:GetWidth(), bw:GetHeight()
		frame:SetPosition(wx.wxPoint(x + w * .6 - bw * .5, y))
	end
end

local think_hook
frameheight = 50

function main()
	frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "Hammer Lua", wx.wxDefaultPosition, Size(500, frameheight), bit.bor(wx.wxSTAY_ON_TOP, wx.wxFRAME_TOOL_WINDOW))
	think_hook = wx.wxTimer(frame)
	frame:SetCanFocus(false)
	frame:SetBackgroundColour(wx.wxBLACK)
	toolBar = frame:CreateToolBar(wx.wxNO_BORDER + wx.wxTB_FLAT + wx.wxTB_DOCKABLE)
	local toolBmpSize = toolBar:GetToolBitmapSize()
	local bmp = wx.wxArtProvider.GetBitmap(wx.wxART_NEW_DIR, wx.wxART_MENU, toolBmpSize)
	toolBar:AddTool(ID.update, "Update Repo", bmp, "Update repository")
	local bmp = wx.wxArtProvider.GetBitmap(wx.wxART_FILE_SAVE, wx.wxART_MENU, toolBmpSize)
	toolBar:AddTool(ID.commit, "Commit map", bmp, "Commit map")
	toolBar:AddSeparator()
	local bmp = wx.wxArtProvider.GetBitmap(wx.wxART_FILE_OPEN, wx.wxART_MENU, toolBmpSize)
	toolBar:AddTool(ID.lock, "Lock This Map", bmp, "Lock This Map")
	local bmp = wx.wxArtProvider.GetBitmap(wx.wxART_UNDO, wx.wxART_MENU, toolBmpSize)
	toolBar:AddTool(ID.unlock, "Unlock this Map", bmp, "Unlock this Map")
	toolBar:AddSeparator()
	local bmp = wx.wxArtProvider.GetBitmap(wx.wxART_QUIT, wx.wxART_MENU, toolBmpSize)
	toolBar:AddTool(ID.exit, "Close", bmp, "Close")
	toolBar:Realize()
	frame:CreateStatusBar(1)

	frame:Connect(wx.wxID_ANY, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
		local id = event:GetId()

		if id == ID.lock then
			svn.lock()
		elseif id == ID.unlock then
			svn.unlock()
		elseif id == ID.commit then
			svn.commit()
		elseif id == ID.update then
			svn.update()
		elseif id == ID.exit then
			os.exit(0)
		else
			print("INVALID", evt, id)
		end
	end)

	frame:Connect(wx.wxEVT_TIMER, function(event)
		local ok, err = xpcall(OnThink, debug.traceback)

		if err then
			printerr(err)
			os.exit(1)
			think_hook:Start(1500)
		end
	end)

	think_hook:Start(100)
	frame:Show(true)
	frame:Show(false)
end

local showing = nil

function ShowMain(yes)
	yes = not not yes

	if yes ~= showing then
		showing = yes
		if showing==nil then frame:Show(true) end
		local w = winapi.get_foreground_window()
		frame:Show(yes)
		w:set_foreground()

		return true
	end
end

local lspeed

local function setspeed(n)
	if lspeed ~= n then
		lspeed = n
		think_hook:Start(n * 1000)
	end
end

do
	function mapchange(map, lmap)
	end
end

local ltxt

function status(txt)
	if txt == ltxt then return end
	ltxt = txt
	dbg("Status: ",txt)
	frame:SetStatusText(txt)
end

local lmap
local wtf=true
OnThink = function()
	if wtf then wtf=nil frame:Show(true)frame:Show(false) end
	local hammer, err = Hammer.get()

	if not hammer then
		if ShowMain(false) then
			dbg("Hiding, no hammer")
		end

		setspeed(1)

		return
	end

	local inhammer = Hammer.ontop()

	if not inhammer then
		inhammer = winapi.get_foreground_window() == window()
	end

	local refresh = ShowMain(inhammer)
	refresh = refresh and inhammer

	if refresh then
		print("Refresh", inhammer)
	end

	if inhammer then
		doresize(hammer, frame)
	end

	local map = Hammer.map(hammer)

	if map ~= lmap then
		lmap = map
		mapchange(map, lmap)
	end

	status(map)
	if not map then return end
	setspeed(1 / 60)
end

main()

wx.wxGetApp():MainLoop()