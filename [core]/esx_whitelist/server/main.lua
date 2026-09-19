local Whitelist <const> = xLib.require "@esx_whitelist.server.module.whitelist.main"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Connection <const> = xLib.require "@esx_whitelist.server.module.whitelist.connection"

AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Whitelist.Init()
    end
end)

AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    local playerSource = source

    local ok, err = xpcall(function()
        Connection.Verify(
            playerSource,
            playerName,
            setKickReason,
            deferrals,
            State.translations
        )
    end, debug.traceback)

    if not ok then
        if Config.Debug then
            print("^1[esx_whitelist] Connection error:^7 " .. tostring(err))
        end
        pcall(function()
            deferrals.done("~r~" .. Util.Translate(State.translations, "system_error"))
        end)
    end
end)

AddEventHandler("esx:playerLoaded", function(playerId, xPlayer)
    Whitelist.OnPlayerLoaded(playerId, xPlayer)
end)

AddEventHandler("esx:playerDropped", function(playerId, reason)
    Whitelist.OnPlayerDropped(playerId, reason)
end)
