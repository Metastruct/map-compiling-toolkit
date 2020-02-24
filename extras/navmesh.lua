print"navmesh.lua running..."
local navmeshregen
pcall(require,'landmark')
if not landmark or not landmark.get then
	system.FlashWindow()
	print"UNABLE TO LOAD LANDMARK MODULE"
end

if GetConVar("con_nprint_bgalpha"):GetString()=="quit" then
	print "quitting..."
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
	
	print"\n!!!!!BUILDING NAVMESH!!!!!!!!\n"
	if not navmeshregen then
		if not navmesh.IsLoaded() then navmesh.Load() end
		
		if navmesh.IsLoaded() then
			if (file.Size("maps/"..game.GetMap()..'.nav','GAME') or -1) > 1 then
				print"navmesh found, leaving..."
				RunConsoleCommand("exitgame")
				return
			else
				print"navmesh oversmall, regenerating"
			end
		end
	end
	
	if not file.Exists("navmesh_landmarks.txt", 'DATA') then
		print "navmesh_landmarks.txt MISSING"
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
					start = pos,
					endpos = pos - Vector(0, 0, 512)
				}
				if tr.Hit then 
					navmesh.AddWalkableSeed(tr.HitPos, tr.HitNormal)
					debugoverlay.Cross(tr.HitPos,128,120,Color(255,255,255),true)
					err=false
				else err="trace did not hit" end

			else err="landmark missing or invalid" end
		else err="could not parse name" end
		if err then
		system.FlashWindow = system.FlashWindow or function() print("WTF?",SERVER,CLIENT,MENU) end
			print(("Adding seed did not succeed: %s %q"):format(err,lm))
		end
	end
	print("begin",navmesh.BeginGeneration())
	
	hook.Add("ShutDown","agwegwegg",function()
		print"Quitting...?"
		system.FlashWindow = system.FlashWindow or function() print("WTF?",SERVER,CLIENT,MENU) end
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
	timer.Simple(1,function() print"built test?" end)
	timer.Simple(60*2,function()
		hook.Add("Think",'agwegwegg',function()
			if navmesh.IsGenerating() then return end
			hook.Remove("Think","agwegwegg")
			print("save",navmesh.Save())
			RunConsoleCommand("exitgame")
		end)
		
	end)
end)
