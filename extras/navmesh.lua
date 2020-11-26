local function dbg(...)
	Msg"[navmesh.lua] " print(...)
end

dbg"Loaded..."
local navmeshregen
pcall(require,'landmark')
if not landmark or not landmark.get then
	system.FlashWindow()
	dbg"UNABLE TO LOAD LANDMARK MODULE"
end

if GetConVar("con_nprint_bgalpha"):GetString()=="quit" then
	dbg "quitting..."
	RunConsoleCommand("exitgame")
	if game.ConsoleCommand then
		game.ConsoleCommand( "exitgame\n" )
	end
	if CLIENT then
		FindMetaTable"Player".ConCommand(NULL,'exitgame',true)
	end
	
	timer.Simple(5,function()
	
		RunConsoleCommand("exitgame")
		if game.ConsoleCommand then
			game.ConsoleCommand( "exitgame\n" )
		end
		if CLIENT then
			FindMetaTable"Player".ConCommand(NULL,'exitgame',true)
		end
	
	end)
	
	return
end

if GetConVar("con_nprint_bgalpha"):GetString()~="navmesh" then
	navmeshregen=true
	if GetConVar("con_nprint_bgalpha"):GetString()~="navmeshregen" then
		return 
	end
end

RunConsoleCommand("con_nprint_bgalpha","quit")

local i=68
hook.Add("Think","agwegwegg",function()
	i=i-1
	if i>0 then return end
	hook.Remove("Think","agwegwegg")
	
	dbg"\n!!!!!BUILDING NAVMESH!!!!!!!!\n"
	if not navmeshregen then
		if not navmesh.IsLoaded() then 
			navmesh.Load() 
		end
		
		if navmesh.IsLoaded() then
			dbg"navmesh.IsLoaded()==true?"
			if (file.Size("maps/"..game.GetMap()..'.nav','GAME') or -1) > 1 then
				dbg"navmesh found, leaving..."
				RunConsoleCommand("exitgame")
				return
			else
				dbg"navmesh oversmall, regenerating"
			end
		end
	end
	
	if not file.Exists("navmesh_landmarks.txt", 'DATA') then
		dbg "navmesh_landmarks.txt MISSING"
		system.FlashWindow()
		return
	end
	
	--TODO
	for lm in file.Read("navmesh_landmarks.txt", 'DATA'):gmatch'[^\r\n]+' do
		local name, offset = lm:match'^([^%,]+)%,?(.*)$'
		local err="unknown error"
		if name then
			local offset = offset and #offset > 3 and offset:Trim():find"^%d+ %d+ %d+$" and Vector(offset:Trim()) or Vector(0,0,0)
			local pos = landmark.get(name:Trim())

			if pos then
				pos = pos + offset
				local tr = util.TraceLine{
					start = pos+Vector(0,0,16),
					endpos = pos + Vector(0, 0, -2048)
				}
				if tr.Hit and util.IsInWorld(tr.HitPos)and util.IsInWorld(tr.HitPos+Vector(0,0,70)) then 
					navmesh.AddWalkableSeed(tr.HitPos, tr.HitNormal)
					dbg("AddWalkableSeed(Vector('"..tostring(tr.HitPos).."'), Vector('"..tostring(tr.HitNormal).."'))")
					debugoverlay.Cross(tr.HitPos,128,120,Color(255,255,255),true)
					err=false
				else err="trace did not hit: "..tostring(lm) end

			else err="landmark missing or invalid: "..tostring(lm) end
		else err="could not parse name: "..tostring(lm) end
		if err then
			system.FlashWindow = system.FlashWindow or function() dbg("WTF?",SERVER,CLIENT,MENU) end
			dbg(("Adding seed did not succeed: %s %q"):format(err,lm))
		end
	end
	
	local last = SysTime()
	local start = SysTime()
	hook.Add("Think","elapseprint",function()
		local now = SysTime()
		if now-last > 10 then
			last = now
			dbg("Elapsed:",string.NiceTime(now-start))
		end
	end)
	dbg("begin",navmesh.BeginGeneration())
	
	hook.Add("ShutDown","agwegwegg",function()
		dbg"Attempting to exit (feel free to close the window after 30 seconds)"
		system.FlashWindow = system.FlashWindow or function() dbg("WTF?",SERVER,CLIENT,MENU) end
		system.FlashWindow()
		RunConsoleCommand("exitgame")
		if CLIENT then
			LocalPlayer():ConCommand('exitgame',true)
		else
			player.GetHumans()[1]:ConCommand('exitgame',true)
		end
		if game.ConsoleCommand then
			game.ConsoleCommand( "exitgame\n" )
		end
	end)
	timer.Simple(1,function() dbg"Testing if built" end)
	timer.Simple(60*2,function()
		hook.Add("Think",'agwegwegg',function()
			if navmesh.IsGenerating() then return end
			hook.Remove("Think","agwegwegg")
			dbg("save",navmesh.Save())
			RunConsoleCommand("exitgame")
		end)
		
	end)
end)
