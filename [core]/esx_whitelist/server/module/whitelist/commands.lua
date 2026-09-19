local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Auth <const> = xLib.require "@esx_whitelist.server.module.whitelist.auth"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local ConfigService <const> = xLib.require "@esx_whitelist.server.module.whitelist.config"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Connection <const> = xLib.require "@esx_whitelist.server.module.whitelist.connection"

---@class Commands
---@description In-game commands for whitelist management (wl_add, wl_remove, wl_check, wl_on, wl_off, wl_sync).
local Commands = {}

---@description Adds a connected player to the database whitelist by identifier or player ID.
---@param xPlayer table ESX player object
---@param targetId number Target player ID
local function addTarget(xPlayer, targetId)
    local target = targetId and ESX.GetPlayerFromId(targetId)
        if not target then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "player_not_found")) end

    local identifiers = Cache.SetIdentifiers(targetId, Util.GetPlayerIdentifiersFiltered(targetId))
    if #identifiers == 0 then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "no_identifiers_found")) end

    Database.FindByIdentifiers(identifiers, function(existing)
        if existing and tonumber(existing.whitelisted) == 1 then
            return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "player_already_wl"))
        end

        local function done(success, id)
            if not success or not id then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "failed_to_update")) end
            Cache.SetWhitelistBatch(identifiers, id)
            xPlayer.showNotification("~g~" .. Util.Translate(State.translations, "player_added"))
            target.showNotification("~g~" .. Util.Translate(State.translations, "added_to_whitelist"))
            if State.gracePlayers[targetId] then
                State.gracePlayers[targetId] = nil
                TriggerClientEvent("esx_whitelist:cancelGracePeriod", targetId)
            end
        end

        if existing then
            Database.AddIdentifiers(existing.id, identifiers, function(success)
                if not success then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "identifier_conflict")) end
                Database.SetStatus(existing.id, 1, xPlayer.getIdentifier(), function(affected)
                    done(affected and affected > 0, existing.id)
                end)
            end)
        else
            Database.InsertPlayer(target.getName(), identifiers, true, xPlayer.getIdentifier(), function(id)
                done(id ~= nil, id)
            end)
        end
    end)
end

---@description Registers all whitelist commands.
function Commands.Register()
    if not Config.InGameCommands then return end

    ESX.RegisterCommand(Config.Commands.Add, Auth.Groups(), function(xPlayer, args)
        addTarget(xPlayer, tonumber(args.id))
    end, false, {
        help = "Add player to whitelist",
        validate = true,
        arguments = {{ name = "id", help = "Player ID", type = "number" }}
    })

    ESX.RegisterCommand(Config.Commands.Remove, Auth.Groups(), function(xPlayer, args)
        local targetId = tonumber(args.id)
        local target = targetId and ESX.GetPlayerFromId(targetId)
        local identifiers = target and Cache.GetIdentifiers(targetId) or nil

        local function enforceTarget()
            if targetId then Connection.Enforce(targetId, State.translations) end
        end

        local function removeByIdentifiers(ids)
            Database.FindByIdentifiers(ids, function(existing)
                if not existing or tonumber(existing.whitelisted) ~= 1 then
                    return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "player_not_in_wl"))
                end

                Database.GetIdentifierList(existing.id, function(identifiers)
                    Database.SetStatus(existing.id, 0, xPlayer.getIdentifier(), function(affected)
                        if not affected or affected < 1 then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "failed_to_update")) end
                        Cache.RemoveWhitelistBatch(identifiers)
                        xPlayer.showNotification("~g~" .. Util.Translate(State.translations, "player_removed"))
                        enforceTarget()
                    end)
                end)
            end)
        end

        if identifiers and #identifiers > 0 then
            removeByIdentifiers(identifiers)
        else
            xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "player_not_found"))
        end
    end, false, {
        help = "Remove player from whitelist",
        validate = true,
        arguments = {{ name = "id", help = "Player ID", type = "number" }}
    })

    ESX.RegisterCommand(Config.Commands.Check, Auth.Groups(), function(xPlayer, args)
        local targetId = tonumber(args.id)
        local target = targetId and ESX.GetPlayerFromId(targetId)
    if not target then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "player_not_found")) end

        Connection.Authorize(targetId, function(allow, reason)
            local status = allow and ("~g~" .. Util.Translate(State.translations, "authorized")) or ("~r~" .. Util.Translate(State.translations, "not_authorized"))
            xPlayer.showNotification(("%s~s~ %s (%s)"):format(status, target.getName(), reason or "unknown"))
        end)
    end, false, {
        help = "Check player whitelist status",
        validate = true,
        arguments = {{ name = "id", help = "Player ID", type = "number" }}
    })

    ESX.RegisterCommand(Config.Commands.On, Auth.Groups(), function(xPlayer)
        if State.config.enabled then return xPlayer.showNotification("~y~" .. Util.Translate(State.translations, "whitelist_already_enabled")) end
        local ok = ConfigService.SetEnabled(true)
        if not ok then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "failed_to_save_state")) end
        xPlayer.showNotification("~g~" .. Util.Translate(State.translations, "whitelist_enabled_notification"))
        TriggerClientEvent("esx_whitelist:stateChanged", -1, true)
        Connection.KickNonWhitelisted(State.translations)
    end, false, { help = "Enable whitelist" })

    ESX.RegisterCommand(Config.Commands.Off, Auth.Groups(), function(xPlayer)
        if not State.config.enabled then return xPlayer.showNotification("~y~" .. Util.Translate(State.translations, "whitelist_already_disabled")) end
        local ok = ConfigService.SetEnabled(false)
        if not ok then return xPlayer.showNotification("~r~" .. Util.Translate(State.translations, "failed_to_save_state")) end
        xPlayer.showNotification("~g~" .. Util.Translate(State.translations, "whitelist_disabled_notification"))
        TriggerClientEvent("esx_whitelist:stateChanged", -1, false)
    end, false, { help = "Disable whitelist" })

    ESX.RegisterCommand(Config.Commands.Sync, Auth.Groups(), function(xPlayer)
        Database.RefreshCache(function(ok)
            if xPlayer then
                xPlayer.showNotification(ok and ("~g~" .. Util.Translate(State.translations, "cache_synced")) or ("~r~" .. Util.Translate(State.translations, "cache_sync_failed")))
            end
        end)
    end, false, { help = "Sync whitelist cache with database" })
end

return Commands
