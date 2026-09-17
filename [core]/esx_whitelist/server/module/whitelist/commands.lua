local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Auth <const> = xLib.require "@esx_whitelist.server.module.whitelist.auth"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local Validation <const> = xLib.require "@esx_whitelist.server.module.whitelist.validation"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

local Commands = {}

function Commands.Register(onChanged)
    if not Config.InGameCommands then return end

    ESX.RegisterCommand("wl_add", Auth.Groups(), function(xPlayer, args)
        local targetId = tonumber(args.id)
        local target = targetId and ESX.GetPlayerFromId(targetId)
        if not target then return xPlayer.showNotification("~r~Player not found") end

        local identifiers = Cache.SetIdentifiers(targetId, Util.GetPlayerIdentifiersFiltered(targetId))
        if #identifiers == 0 then return xPlayer.showNotification("~r~No identifiers found for player") end
        Database.FindByIdentifiers(identifiers, function(existing)
            if existing and existing.whitelisted == 1 then return xPlayer.showNotification("~r~Player already whitelisted") end
            local function success(id)
                if not id then return xPlayer.showNotification("~r~Failed to update whitelist") end
                for i = 1, #identifiers do Cache.SetWhitelist(identifiers[i], id) end
                xPlayer.showNotification("~g~Player added to whitelist")
                target.showNotification("~g~You have been added to the whitelist")
                if State.gracePlayers[targetId] then
                    State.gracePlayers[targetId] = nil
                    TriggerClientEvent("esx_whitelist:cancelGracePeriod", targetId)
                end
                if onChanged then onChanged() end
            end
            if existing then
                Database.SetStatus(existing.id, 1, xPlayer.getIdentifier(), function() Database.AddIdentifiers(existing.id, identifiers, function() success(existing.id) end) end)
            else
                Database.InsertPlayer(target.getName(), identifiers, true, xPlayer.getIdentifier(), success)
            end
        end)
    end, false, { help = "Add player to whitelist", validate = true, arguments = {{ name = "id", help = "Player ID", type = "number" }} })

    ESX.RegisterCommand("wl_check", Auth.Groups(), function(xPlayer, args)
        local targetId = tonumber(args.id)
        local target = targetId and ESX.GetPlayerFromId(targetId)
        if not target then return xPlayer.showNotification("~r~Player not found") end
        local whitelisted = Cache.IsWhitelisted(Cache.GetIdentifiers(targetId))
        xPlayer.showNotification((whitelisted and "~g~" or "~r~") .. target.getName() .. (whitelisted and " is whitelisted" or " is NOT whitelisted"))
    end, false, { help = "Check player whitelist status", validate = true, arguments = {{ name = "id", help = "Player ID", type = "number" }} })

    ESX.RegisterCommand("wl_sync", Auth.Groups(), function(xPlayer)
        Database.RefreshCache(function() if xPlayer then xPlayer.showNotification("~g~Whitelist cache synchronized with database") end end)
    end, false, { help = "Sync whitelist cache with database" })
end

return Commands
