if GetConVar("con_nprint_bgalpha"):GetString()~="writemissing" then return end
local function retry()

	local function bsp_writevmts()
		if file.Exists("mapoverrides",'DATA') then
			error"data/mapoverrides folder exists already!!"
			return
		end
		
		local a=file.Read("addlist_src.txt",'DATA')
		if not  a or #a<10 then
			error"data/addlist_src.txt missing. run bsp_findmissing first"
			return
		end
		
		local dat={}
		local i=1
		for line in a:gmatch"[^\r\n]+" do dat[i]=line i=i+1 end
		
		local addlist=file.Open("addlist.txt",'wb','DATA')
		local first=true
		local function Addlist(a,b)
			assert(#a>1)
			assert(#b>1)
			if not first then
				addlist:Write"\n"
			else
				first=false
			end
			addlist:Write(a.."\n"..b)
		end
		
		file.CreateDir("mapoverrides")
		file.CreateDir("mapoverrides/materials")
		for k,path in next,dat do
			assert(path:sub(-4,-4):lower()~='.','invalid format maybe')
			local realpath='materials/'..path..'.vmt' -- materials/wood/INFDOORC.vmt
			
			local relativepath='mapoverrides/'..realpath  -- mapoverrides/materials/wood/INFDOORC.vmt
			local relativepath_txt=relativepath:sub(1,-5)..'.txt' -- mapoverrides/materials/wood/INFDOORC.txt
			

			local dat = file.Read(realpath,'GAME')
			assert(dat,"Missing: "..realpath)
			
			file.CreateDir(string.GetPathFromFilename(relativepath_txt),'DATA')
			
			local f=file.Open(relativepath_txt,'wb','DATA')
			f:Write(dat)
			f:Close()
			Addlist(realpath,relativepath_txt)
		end
		
		addlist:Close()
		print"VMTs written to data/mapoverrides..."
	end


	concommand.Add("bsp_writevmts",bsp_writevmts ,nil,"make sure you now have everything mounted")





	local function int(str,endian,signed) -- use length of string to determine 8,16,32,64 bits
		local t={str:byte(1,-1)}
		if endian==true then --reverse bytes
			local tt={}
			for k=1,#t do
				tt[#t-k+1]=t[k]
			end
			t=tt
		end
		local n=0
		for k=1,#t do
			n=n+t[k]*2^((k-1)*8)
		end
		if signed then
			n = (n > 2^(#t*8-1) -1) and (n - 2^(#t*8)) or n -- if last bit set, negative.
		end
		return n
	end

	local function ismissing(txt)
	   
		-- no use adding fallbacks even if cstrike overwrites
		if file.Exists(txt,'hl2') then return false end
		
		local cs=file.Exists(txt,'cstrike')
		--print(cs,txt)
		if cs then return 'cstrike' end
		
		if file.Exists(txt,'tf') then return 'tf' end
		
		if file.Exists(txt,'episodic') then return 'episodic' end
		if file.Exists(txt,'ep2') then return 'ep2' end
		return false
	end
	local function bsp_findmissing()
		
		local name = 'maps/'..game.GetMap()..'.bsp'
		print("Finding from "..name..'...')
		
		local f = file.Open(name,"rb","GAME")
		
		assert(f:Read(4)=='VBSP',"not a bsp") -- ident
		
		local version        = int(f:Read(4),false,false)
		assert(version==20,"new version?")
		
		local out=file.Open("addlist_src.txt",'wb','DATA')
		local first=true
		local function Out(path)
			
			out:Write((first and "" or "\n")..path)
			
			first=false
			
		end
		
		local ded=0
		local a=file
		local paths={}
		local total_count=0
		local function texinfo(len)
			local endpos=f:Tell()+len
			local pos
			for i=1,2048*2 do
				pos   =f:Tell()
				
				local dat=f:Read(129)
				local l,r=dat:find("\0",1,true)
				assert(l,r)
				local path=dat:sub(1,l-1)
				
				total_count=total_count+1
				if not path:find"^maps/" and not path:find"^decals/" then
					paths[#paths+1]=path
				end
				
				local np=pos+r
				if np>=endpos then break end
				f:Seek(np)
				
				
			end
		end
		
		
		for i=0,63 do
			local tell=f:Tell()
			local pos = int(f:Read(4))
			local len = int(f:Read(4))
			local ver = int(f:Read(4))
			local fourCC = f:Read(4)
			--print(("%-35s: Pos %8d Len %8d Ver %d fourCC %s"):format(lumps[i] or "???",pos,len,ver,fourCC))
			if i==43 then
				f:Seek(pos)
				texinfo(len)
				f:Seek(tell)
				break
			end
		end

		print("Found in total "..total_count.." materials from the map")

		print"Finding missing using cstrike/tf/episodic/ep2..."
		-- speed me up maybe
		
		table.sort(paths)
		--co.waittick()
		
		local pc=#paths
		--for k,v in next,paths do
		--    print(v)
		--end
		--
		--error"out"
		
		for k,path in next,paths do
			
			--if k%10==0 then co.waittick()  end
			--if k%20==0 then Msg(("\n%4d/%4d done "):format(k,pc)) end
			local ret = ismissing('materials/'..path..'.vmt')
				
				if ret then
				   --print("Adding: "..path..' - '..tostring(ret))
					Msg"!"
					Out(path)
					ded=ded+1
				end
		end
		MsgN""
		--local dat = f:Read(len)
		
		f:Close()
		out:Close()
		
		print("Missing textures written: "..ded)

		bsp_writevmts()
		
		FindMetaTable"Player".ConCommand(nil,"exitgame",true)
	end

	concommand.Add("bsp_findmissing", bsp_findmissing ,nil,"make sure you have everything mounted")


	hook.Add("Think","agwegweg",function()
		hook.Remove("Think","agwegweg")
		bsp_findmissing()
	end)

end

concommand.Add("retry_command",function()
	retry()
end,nil,"retry missing writing command")

local ok,err=pcall(retry)
if not ok then
	print("FAILED: ",err)
	print"To retry run command retry_command"
end