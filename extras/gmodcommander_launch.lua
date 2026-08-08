local Tag= 'gmodcommander_launch'

local function doprint()
    local cvar = GetConVar("con_nprint_bgalpha")
    local mode = cvar and cvar:GetString()
    if not mode or mode:Trim()=="" or tonumber(mode or "") then return end

    if chat and chat.AddText then
        chat.AddText(Color(255, 200, 0), "[gmodcommander] ", Color(255, 255, 255), "launch mode (", Color(255, 200, 0),
            mode, Color(255, 255, 255), ")")
    end
    print("[gmodcommander] launch mode (" .. mode .. ")")
end
if CLIENT then
    hook.Add("InitPostEntity", Tag, function()
        timer.Simple(1, function()
            doprint()
        end)
    end)
end
