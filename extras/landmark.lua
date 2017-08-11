local _M = {}
local landmark=_M
local _MM = {}
setmetatable(_M,_MM)
function _MM.__call(self,id)
	return _M.get(id)
end

--- Parse landmarks ---
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


local landmarks
local function getlandmarks()
	if landmarks then return landmarks end
	
	local name = 'maps/'..game.GetMap()..'.bsp'


	local f = file.Open(name,"rb","GAME")

	assert(f:Read(4)=='VBSP',"not a bsp") -- ident

	local version        = int(f:Read(4),false,false)
	assert(version==20,"new version?")

	-- entity info
	local pos = int(f:Read(4))
	local len = int(f:Read(4))
	local ver = int(f:Read(4))
	local fourCC = f:Read(4)
	f:Seek(pos)
	local dat = f:Read(len)

	f:Close()

	local lastfindpos=30
	for _=1,10000 do
		local l,r=dat:find('"info_landmark"\n',lastfindpos,true)
		if l==nil then
			break
		end
		
		--print(l,r,dat:sub(l-100,r+100))
			
		local L
		for i=l,l-1000,-1 do
			local char = dat:sub(i,i)
			if char=='{' then
				if dat:sub(i-1,i-1)~="\n" then error"eek" end
				 
				L=i
				break
			end
		end

		local R=dat:find("}\n",r,true)
		R=R and R+1
		
		if L and R then
			landmarks = landmarks or {}
			local t = util.KeyValuesToTable('"x"\n'..dat:sub(L,R))
			if not t or not t.classname then continue end
			local name = t and t.targetname
			local classname=name and t.classname=="info_landmark"
			if classname and name then
				landmarks[name]=Vector(t.origin)
			end
			
			lastfindpos=R+4
			--return
		else
			lastfindpos=r+1
		end
		
	end
	if not landmarks then
		landmarks = {}
	end

	return landmarks

end

_M.getlandmarks=getlandmarks

_M.getall=getlandmarks
local get get = function(id)
	if landmarks==nil then
		getlandmarks()
		get = function(id) return landmarks[id] end
		_M.get = get
	end
	return landmarks[id]
end
_M.get = get

function _M.toworld(id,vec)
	if landmarks==nil then
		getlandmarks()
	end
	local lmvec = landmarks[id]
	if not lmvec then return end
	return lmvec+vec
end
function _M.fromworld(id,vec)
	if landmarks==nil then
		getlandmarks()
	end
	local lmvec = landmarks[id]
	if not lmvec then return end
	return vec-lmvec
end

local added
function _M.needcs()
	if added then return end
	added = true
	
	if SERVER then
		AddCSLuaFile("includes/modules/landmark.lua") -- just () does not work!?
	end
	
end

local function nearest(start_pos)
	local closest,closest_pos,closest_dist=nil,nil,math.huge
	
	for name,pos in next,getlandmarks() do
		local dist = start_pos:DistToSqr(pos)
		if dist<closest_dist then
			closest	,closest_pos,closest_dist =
			name	,pos		,dist
		end
	end
	return closest,closest_pos,math.sqrt(closest_dist)
end
_M.nearest = nearest

_G.landmark=_M


local new_LMVector = {  }

_G.LMVector = new_LMVector
_M.LMVector = new_LMVector

-- LMVector(worldpos) -- closest landmark
-- LMVector(worldpos,lmname) -- landmark name
-- lvec:vec() -- local
-- lvec:pos() -- world
-- lvec:inworld()

local meta = {}
local static = {}

-- DEPRECIATED
function static:fromtable(tbl)
	return landmark.get(tbl[2])
		and setmetatable({tbl[1]*1,tbl[2]}, nt)
end
	
local mt = {__index = meta}
setmetatable(new_LMVector, {
	__call = function(_,worldpos,landmark_name,from_local,b,c)
		if istable(worldpos) then
			local t = worldpos
			worldpos = Vector(t[1],t[2],t[3])
			landmark_name = t[4]
			from_local=true
		end
		
		if isnumber(worldpos) then
			worldpos = Vector(worldpos,landmark_name,from_local)
			landmark_name = b
			from_local = c
		end
		
		
		if not landmark_name then error("LMVector(no landmark specified)",2) end
		local landmark_pos
		if landmark_name == true then
			if from_local then
				error("LMVector(Invalid call: local and no landmark)",2)
			end
			landmark_name,landmark_pos = nearest(worldpos)
		else
			landmark_pos = landmark.get(landmark_name)
		end
		if not landmark_pos then
			if from_local then return nil,'missing landmark' end -- local landmarks just return nothing
			error("Landmark not found",2)
		end
		
		local pos = from_local and worldpos or (worldpos - landmark_pos)
		return setmetatable({ pos, landmark_name
							}, mt)
	end,
	__index=static
})

function meta:vec()
	return self[1]
end
function meta:table()
	local v = self[1]
	return {v[1],v[2],v[3],self[2]}
end
meta.ToTable=meta.table

function meta:pos()
	return self[1]+get(self[2])
end
meta.ToWorld=meta.pos
meta.LocalToWorld=meta.pos
meta.toworld=meta.pos
meta.World=meta.pos

local pos = Vector(0,0,0)
function meta:tpos()
	pos:Set(self[1])
	pos:Add(get(self[2]))
	return self[1]+get(self[2])
end

if SERVER then
	function meta:inworld()
		return util.IsInWorld(self:tpos())
	end
else
	function meta:inworld()
		return util.PointContents(self:tpos())~=1
	end
end
meta.InWorld = meta.inworld
meta.IsInWorld = meta.inworld

function mt:__call(s) return self[1] end
function mt:__tostring()
	local v = self[1]
	return ("LMVector(%s, %s, %s, %q, true)"):format(v[1],v[2],v[3],self[2])
end

return _M