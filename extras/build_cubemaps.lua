if GetConVar("con_nprint_bgalpha"):GetString()=="cubemaps" then
	
	local i=120
	hook.Add("Think","agwegwegg",function()
		i=i-1
		if i>0 then return end
		
		hook.Remove("Think","agwegwegg")
		RunConsoleCommand"bcmaps"
		print"\n!!!!!BUILDING CUBEMAPS!!!!!!!!\n"
		hook.Add("ShutDown","agwegwegg",function()
			print"Quitting..."
			
			FindMetaTable"Player".ConCommand(nil,"exitgame",true)
		end)
		timer.Simple(1,function() print"cubemaps built test?" end)
		timer.Simple(60*2,function()
			FindMetaTable"Player".ConCommand(nil,"exitgame",true)
		end)
	end)
end