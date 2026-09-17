local Whitelist <const> = xLib.require "@esx_whitelist.server.module.whitelist.main"

AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Whitelist.Init()
    end
end)

AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    Whitelist.OnPlayerConnecting(playerName, setKickReason, deferrals)
end)

AddEventHandler("esx:playerLoaded", function(playerId, xPlayer)
    Whitelist.OnPlayerLoaded(playerId, xPlayer)
end)

AddEventHandler("esx:playerDropped", function(playerId, reason)
    Whitelist.OnPlayerDropped(playerId, reason)
end)
