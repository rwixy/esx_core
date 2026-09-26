-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local Whitelist <const> = xLib.require "@esx_whitelist.server.module.whitelist.main"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Connection <const> = xLib.require "@esx_whitelist.server.module.whitelist.connection"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

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
        local fallbackReason = "Whitelist authorization failed."
        local translated, reason = pcall(Util.Translate, State.translations, "system_error")
        if not translated or type(reason) ~= "string" then reason = fallbackReason end

        local completed = pcall(function()
            deferrals.done("~r~" .. reason)
        end)
        if not completed and reason ~= fallbackReason then
            pcall(function() deferrals.done("~r~" .. fallbackReason) end)
        end
    end
end)

AddEventHandler("playerJoining", function(previousPlayerId)
    Whitelist.OnPlayerJoining(source, previousPlayerId)
end)

AddEventHandler("playerDropped", function(reason)
    Whitelist.OnPlayerDropped(source, reason)
end)

AddEventHandler("esx:playerLoaded", function(playerId, xPlayer)
    Whitelist.OnPlayerLoaded(playerId, xPlayer)
end)

AddEventHandler("esx:playerDropped", function(playerId, reason)
    Whitelist.OnPlayerDropped(playerId, reason)
end)
