if CLIENT then
    hook.Add("InitPostEntity", "GModCommanderLaunchMode", function()
        timer.Simple(1, function()
            local mode = "launch"
            local cvar = GetConVar("con_nprint_bgalpha")
            if cvar then
                local value = cvar:GetString()
                if value and value ~= "" then
                    mode = value
                end
            end
            if chat and chat.AddText then
                chat.AddText(Color(255, 200, 0), "[gmodcommander] ", Color(255, 255, 255), "launch mode (", Color(255, 200, 0), mode, Color(255, 255, 255), ")")
            end
            print("[gmodcommander] launch mode (" .. mode .. ")")
        end)
    end)
end
