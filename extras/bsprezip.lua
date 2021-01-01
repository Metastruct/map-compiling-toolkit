
if SERVER then 
	return 
end

if GetConVar("con_nprint_bgalpha") and GetConVar("con_nprint_bgalpha"):GetString() ~= "bsprezip" then return end

local function dbg(...)
	Msg"[bsprezip.lua] "
	print(...)
end

if not GetConVar("con_nprint_bgalpha") then
	dbg("debug mode?")
end

RunConsoleCommand("con_nprint_bgalpha", "quit")
print"\n\n\n"
dbg"Loaded..."
print"\n\n\n"
local Tag = "bsprezip"



require('map_manipulation_tool_api')
local MAP = game.GetMap()
--MAP="gm_construct_m3_240"

local map_fucked = "maps/"..MAP..'.bsp'
local map_nozip = "maps/"..MAP..'_prezip.bsp'
assert(file.Exists(map_nozip,'MOD'),"File "..map_nozip.." does not exist")
local map_unfucked = MAP..'.bsp.dat'
local zip_full = MAP..'.zip.dat'

print("Extracting the zip from ",map_fucked,"to","data/"..zip_full,"and adding it to ",map_nozip," at ","data/"..map_unfucked)

-- do the transplant
local api = assert(map_manipulation_tool_api)
local packLumpId = 41
local map_fucked_api = api.BspContext:new(map_fucked)
		for k,v in pairs(map_fucked_api:getInfoLumps()) do
			if v.id==40 then
				packLumpId = v.luaId or v.id
				assert(packLumpId==41,"update, something else may have broken also, if not just remove this assert")
			end
		end
		map_fucked_api:extractLumpAsHeaderlessFile(false,packLumpId,false,zip_full,false)
		map_fucked_api:close()

api = assert(map_manipulation_tool_api)
local map_nozip_api = api.BspContext:new(map_nozip)
		map_nozip_api:setupLumpFromHeaderlessFile(false,packLumpId,"data/"..zip_full)
		map_nozip_api:writeNewBsp(map_unfucked)
		map_nozip_api:close()

assert(file.Exists(map_unfucked,'DATA'))

local function close()
	-- todo: RunString
	system.FlashWindow = system.FlashWindow or function()
		--dbg("WTF?", SERVER, CLIENT, MENU)
	end

	system.FlashWindow()

	if debugmode then
		dbg("debugmode, not exiting")

		return
	end

	print"done"
	RunConsoleCommand("exitgame")

	if CLIENT then
		LocalPlayer():ConCommand('exitgame', true)
	else
		player.GetHumans()[1]:ConCommand('exitgame', true)
	end

	if game.ConsoleCommand then
		game.ConsoleCommand("exitgame\n")
	end
end

hook.Add("InitPostEntity", Tag, close)
