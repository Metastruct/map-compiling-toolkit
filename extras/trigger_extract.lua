if CLIENT then return end
if GetConVar("con_nprint_bgalpha") and GetConVar("con_nprint_bgalpha"):GetString() ~= "trigger_extract" then return end

local function dbg(...)
	Msg"[trigger_extract.lua] "
	print(...)
end

if not GetConVar("con_nprint_bgalpha") then
	dbg("debug mode?")
end

RunConsoleCommand("con_nprint_bgalpha", "quit")
print"\n\n\n"
dbg"Loaded..."
print"\n\n\n"
local Tag = "trigger_extract"
local ENT = {}
ENT.Base = "base_brush"
ENT.Type = "brush"

function ENT:Initialize()
	self:SetSolid(SOLID_BBOX)
	self:SetTrigger(true)
	self:SetNotSolid(true)
	self:SetNoDraw(true)
end

local Alias = {
	rpdm = "rpland",
	breen_trigger = "breen"
}

function ENT:KeyValue(key, value)
	if key == "place" then
		self.place = Alias[value] or value
	end
end

function ENT:GetPlace()
	if not self.place then
		local name = self:GetName()

		if name and #name > 0 then
			self.place = name
		end

		if not self.place then
			print(self, "noplace")

			return
		end
	end
end

scripted_ents.Register(ENT, 'lua_trigger')

local function WriteTriggers(debugmode)
	debugmode = debugmode == "debug" or debugmode == "debugmode"

	timer.Simple(debugmode and 0 or 3, function()
		local triggers_in = ents.FindByClass"lua_trigger"
		local models = {}
		local triggers = {}
		local dummy = ents.Create'prop_physics'
		SafeRemoveEntityDelayed(dummy, 5)

		for _, ent in next, triggers_in do
			dummy:SetModel(ent:GetModel())
			dummy:Spawn()
			local modelbrushmeshes = dummy:GetPhysicsObject():GetMeshConvexes()

			for _, brushmesh in next, modelbrushmeshes do
				for idx, data in next, brushmesh do
					brushmesh[idx] = assert(data.pos)
				end
			end

			models[ent:GetModel()] = modelbrushmeshes

			table.insert(triggers, {
				pos = ent:GetPos(),
				ang = ent:GetAngles(),
				model = ent:GetModel(),
				place = ent.place or (ent.GetPlace and ent:GetPlace()) or ent:GetName()
			})

			local a = ent:GetAngles()

			if a[1] ~= 0 or a[2] ~= 0 or a[3] ~= 0 then
				print(ent, "has rotated angles??", a)
			end
		end

		file.CreateDir"bspdata"
		file.CreateDir("bspdata/" .. game.GetMap())
		file.Write("bspdata/" .. game.GetMap() .. "/trigmesh.json", util.TableToJSON(models))
		file.Write("bspdata/" .. game.GetMap() .. "/triggers.json", util.TableToJSON(triggers))
		dbg"Attempting to exit (feel free to close the window)"

		-- todo: RunString
		system.FlashWindow = system.FlashWindow or function()
			--dbg("WTF?", SERVER, CLIENT, MENU)
		end

		system.FlashWindow()

		if debugmode then
			dbg("debugmode, not exiting")

			return
		end

		RunConsoleCommand("exitgame")

		if CLIENT then
			LocalPlayer():ConCommand('exitgame', true)
		else
			player.GetHumans()[1]:ConCommand('exitgame', true)
		end

		if game.ConsoleCommand then
			game.ConsoleCommand("exitgame\n")
		end
	end)
end

hook.Add("InitPostEntity", Tag, WriteTriggers)
local e = ents.FindByClass"lua_trigger"

if e and e[1] then
	WriteTriggers("debug")
end