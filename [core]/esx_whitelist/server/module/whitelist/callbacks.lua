local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Auth <const> = xLib.require "@esx_whitelist.server.module.whitelist.auth"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local ConfigService <const> = xLib.require "@esx_whitelist.server.module.whitelist.config"
local Validation <const> = xLib.require "@esx_whitelist.server.module.whitelist.validation"
local Discord <const> = xLib.require "@esx_whitelist.server.module.whitelist.discord"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"

local Callbacks = {}
local function allowed(source) return source and source > 0 and Auth.IsAdmin(source) end
local function adminName(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and xPlayer.getName() or "Admin"
end

local function getAllIdentifiers(identifier, cb)
    local online = Cache.FindOnline(identifier)
    if online then
        local xPlayer = ESX.GetPlayerFromId(online)
        return cb(Cache.GetIdentifiers(online), GetPlayerName(online) or (xPlayer and xPlayer.getName()) or "Unknown", true)
    end
    Database.FindByIdentifier(identifier, function(row)
        if not row then return cb({ identifier }, nil, false) end
        Database.GetIdentifiers(row.id, function(rows)
            local identifiers = {}
            for i = 1, #(rows or {}) do identifiers[#identifiers + 1] = rows[i].identifier end
            cb(identifiers, row.player_name, false)
        end)
    end)
end

function Callbacks.Register(translations, onStateChanged, onCacheChanged)
    ESX.RegisterServerCallback("esx_whitelist:getConfig", function(source, cb)
        if not allowed(source) then return cb(nil) end
        cb({
            whitelistEnabled = State.config.enabled,
            gracePeriod = State.config.gracePeriod,
            kickConnected = State.config.kickConnected,
            discordWebhook = State.config.discordWebhook ~= "" and "***CONFIGURED***" or "",
            discordEnabled = State.config.discordEnabled,
            discordGuildId = State.config.discordGuildId,
            discordRoleId = State.config.discordRoleId,
            rules = State.config.rules,
            locale = Config.Locale,
            translations = translations,
            hasBotToken = State.config.discordEnabled and Discord.HasValidToken()
        })
    end)

    ESX.RegisterServerCallback("esx_whitelist:getWhitelistEntries", function(source, cb, request)
        if not allowed(source) then return cb({ entries = {}, page = 1, limit = 50, total = 0, totalPages = 0 }) end
        Database.Search(type(request) == "table" and request or {}, cb)
    end)

    ESX.RegisterServerCallback("esx_whitelist:updateConfig", function(source, cb, data)
        if not allowed(source) or type(data) ~= "table" then return cb(false) end
        if data.discordEnabled and not Discord.HasValidToken() then
            TriggerClientEvent("esx:showNotification", source, "~r~Discord bot token not configured")
            return cb(false)
        end
        local ok, err, oldEnabled = ConfigService.Apply(data)
        if not ok then
            TriggerClientEvent("esx:showNotification", source, "~r~" .. (err or "Invalid configuration"))
            return cb(false)
        end
        if State.config.enabled and not oldEnabled then
            onStateChanged(true, true, adminName(source))
        elseif not State.config.enabled and oldEnabled then
            onStateChanged(false, true, adminName(source))
        else
            TriggerClientEvent("esx_whitelist:stateChanged", -1, State.config.enabled)
        end
        TriggerClientEvent("esx:showNotification", source, "~g~" .. Util.Translate(translations, "config_saved"))
        cb(true)
    end)

    ESX.RegisterServerCallback("esx_whitelist:testWebhook", function(source, cb)
        if not allowed(source) then return cb(false) end
        local sent = Discord.SendLog(Util.Translate(translations, "webhook_test", adminName(source)), Enum.DiscordEmbedColor.PRIMARY, translations)
        cb(sent)
    end)

    ESX.RegisterServerCallback("esx_whitelist:managePlayer", function(source, cb, data)
        if not allowed(source) or type(data) ~= "table" then return cb(false, "Invalid request") end
        if data.action ~= "add" and data.action ~= "remove" then return cb(false, "Invalid request") end
        local fullIdentifier, idType = Validation.Identifier(data.identifier)
        if not fullIdentifier then return cb(false, "Invalid identifier format") end
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return cb(false, "Error getting admin data") end

        if data.action == "add" then
            getAllIdentifiers(fullIdentifier, function(allIdentifiers, existingName, isOnline)
                local targetName = existingName or "Pending..."
                Database.FindByIdentifier(fullIdentifier, function(existing)
                    local function complete(id)
                        if not id then return cb(false, "Failed to update whitelist") end
                        for i = 1, #allIdentifiers do Cache.SetWhitelist(allIdentifiers[i], id) end
                        if isOnline and State.gracePlayers[Cache.FindOnline(fullIdentifier)] then
                            local target = Cache.FindOnline(fullIdentifier)
                            State.gracePlayers[target] = nil
                            TriggerClientEvent("esx_whitelist:cancelGracePeriod", target)
                        end
                        cb(true, "Player added successfully")
                    end
                    if existing then
                        if existing.whitelisted == 1 then return cb(false, "Player already whitelisted") end
                        Database.SetStatus(existing.id, 1, xPlayer.getIdentifier(), function()
                            Database.AddIdentifiers(existing.id, allIdentifiers, function() complete(existing.id) end)
                        end)
                    else
                        Database.InsertPlayer(targetName, allIdentifiers, true, xPlayer.getIdentifier(), complete)
                    end
                end)
            end)
        else
            Database.FindByIdentifier(fullIdentifier, function(existing)
                if not existing or existing.whitelisted == 0 then return cb(false, "Player not in whitelist") end
                Database.SetStatus(existing.id, 0, nil, function()
                    Database.GetIdentifiers(existing.id, function(rows)
                        for i = 1, #(rows or {}) do Cache.RemoveWhitelist(rows[i].identifier) end
                        cb(true, "Player removed successfully")
                    end)
                end)
            end)
        end
    end)

    ESX.RegisterServerCallback("esx_whitelist:toggleWhitelistStatus", function(source, cb, data)
        if not allowed(source) or type(data) ~= "table" then return cb(false) end
        local id, status = tonumber(data.id), tonumber(data.status)
        if not id or (status ~= 0 and status ~= 1) then return cb(false) end
        Database.SetStatus(id, status, nil, function(affected)
            if not affected or affected < 1 then return cb(false) end
            Database.GetIdentifiers(id, function(rows)
                for i = 1, #(rows or {}) do
                    if status == 1 then Cache.SetWhitelist(rows[i].identifier, id) else Cache.RemoveWhitelist(rows[i].identifier) end
                end
                cb(true)
            end)
        end)
    end)

    ESX.RegisterServerCallback("esx_whitelist:detectIdentifier", function(source, cb, rawValue)
        if not allowed(source) or type(rawValue) ~= "string" then return cb({ valid = false }) end
        local full, idType, value = Validation.Identifier(rawValue)
        cb({ type = idType, value = value, valid = full ~= nil })
    end)
end

return Callbacks
