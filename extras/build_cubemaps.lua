if GetConVar("con_nprint_bgalpha"):GetString()=="cubemaps" then
	local i=120
	hook.Add("Think","agwegwegg",function()
		i=i-1
		if i>0 then return end
		
		hook.Remove("Think","agwegwegg")
		RunConsoleCommand"buildcubemaps"
		hook.Add("ShutDown","agwegwegg",function()
			print"Quitting..."
			
			FindMetaTable"Player".ConCommand(nil,"exitgame",true)
		end)
	end)
end