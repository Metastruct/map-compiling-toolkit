if GetConVar("con_nprint_bgalpha"):GetString()~="navmesh" then return end

local i=68
hook.Add("Think","agwegwegg",function()
	i=i-1
	if i>0 then return end
	hook.Remove("Think","agwegwegg")
	
	print"\n!!!!!BUILDING NAVMESH!!!!!!!!\n"
		
	if not navmesh.IsLoaded() then navmesh.Load() end
	
	if navmesh.IsLoaded() then
		print"navmesh found, leaving..."
		RunConsoleCommand("exitgame")
		return 
	end

	--TODO
	local f = file.Read("navmesh_seed.txt",'DATA')
	for v in (f or ""):gmatch'[^\r\n]+' do
		if v and v:find"%d %d" then
			print("seeding",v,navmesh.AddWalkableSeed(Vector(v),Vector(0,0,1)))
		end
	end
	print("begin",navmesh.BeginGeneration())
	
	hook.Add("ShutDown","agwegwegg",function()
		print"Quitting...?"
		
		RunConsoleCommand("exitgame")
		
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
