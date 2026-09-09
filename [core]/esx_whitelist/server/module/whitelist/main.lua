local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Class <const> = xLib.require "@esx_whitelist.server.module.whitelist.Class"
local ServerConfig <const> = xLib.require "@esx_whitelist.server.config.main"

---@class WhitelistService
local Whitelist = {}

---@type table<string, number>
local whitelistCache = {}

---@type table<number, { endTime: number, playerName: string }>
local gracePeriodPlayers = {}

---@type table<number, boolean>
local adminSources = {}

---@type table<string, { hasRole: boolean, expireAt: number }>
local discordCache = {}

---@type table<string, number>
local webhookCooldowns = {}

---@type table<string, string>
local translations = {}

local onlinePlayerCount = 0
local onlineAdminCount = 0
local ruleChangeDebounce = false
local isManualOverride = false

local CONFIG_FILE_PATH <const> = "whitelist_config.json"
local DISCORD_CACHE_TTL_SECONDS <const> = 300
local KICK_CHUNK_SIZE <const> = 50

---Current running state
local state = {
    enabled = false,
    gracePeriod = 60,
    kickConnected = false,
    discordWebhook = "",
    discordEnabled = false,
    discordGuildId = "",
    discordRoleId = "",
    discordBotToken = ServerConfig.DiscordBotToken or GetConvar("discord:botToken", ""),
    rules = {}
}

---Checks if a player source has administrative permissions
---@param playerId number|string
---@return boolean
local function isPlayerAdmin(playerId)
    local numericId = tonumber(playerId)
    if not numericId or numericId == 0 then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(numericId)
    if not xPlayer then
        return false
    end

    local group = xPlayer.getGroup()
    for i = 1, #Config.AdminGroups do
        if group == Config.AdminGroups[i] then
            return true
        end
    end

    return false
end

---Sends a structured embed message to the configured Discord webhook
---@param message string
---@param color number?
local function sendDiscordLog(message, color)
    if not state.discordWebhook or state.discordWebhook == "" or state.discordWebhook == "***CONFIGURED***" then
        return
    end

    if not message or message == "" then
        return
    end

    local currentTime = GetGameTimer()
    if webhookCooldowns[message] and (currentTime - webhookCooldowns[message]) < 5000 then
        return
    end
    webhookCooldowns[message] = currentTime

    local payload = json.encode({
        embeds = {
            {
                title = Util.Translate(translations, "discord_title"),
                description = message,
                color = color or Enum.DiscordEmbedColor.PRIMARY,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
            }
        }
    })

    PerformHttpRequest(state.discordWebhook, function() end, "POST", payload, {
        ["Content-Type"] = "application/json"
    })
end

---Persists current whitelist configuration to disk
local function saveConfig()
    local payload = {
        whitelistEnabled = state.enabled,
        gracePeriod = state.gracePeriod,
        kickConnected = state.kickConnected,
        discordWebhook = state.discordWebhook,
        discordEnabled = state.discordEnabled,
        discordGuildId = state.discordGuildId,
        discordRoleId = state.discordRoleId,
        rules = state.rules
    }
    SaveResourceFile(GetCurrentResourceName(), CONFIG_FILE_PATH, json.encode(payload, { indent = true }), -1)
end

---Loads whitelist configuration from disk or initializes defaults
local function loadConfig()
    translations = Util.LoadLocale(Config.Locale)
    local rawContent = LoadResourceFile(GetCurrentResourceName(), CONFIG_FILE_PATH)

    if not rawContent then
        state.enabled = false
        state.gracePeriod = 60
        state.kickConnected = false
        state.discordWebhook = ""
        state.discordEnabled = false
        state.discordGuildId = ""
        state.discordRoleId = ""
        state.rules = Config.DefaultRules
        saveConfig()
        return
    end

    local success, parsed = pcall(json.decode, rawContent)
    if not success or type(parsed) ~= "table" then
        state.enabled = false
        state.gracePeriod = 60
        state.kickConnected = false
        state.discordWebhook = ""
        state.discordEnabled = false
        state.discordGuildId = ""
        state.discordRoleId = ""
        state.rules = Config.DefaultRules
        saveConfig()
        return
    end

    state.enabled = parsed.whitelistEnabled == true
    state.gracePeriod = tonumber(parsed.gracePeriod) or 60
    state.kickConnected = parsed.kickConnected == true
    state.discordWebhook = parsed.discordWebhook or ""
    state.discordEnabled = parsed.discordEnabled == true
    state.discordGuildId = parsed.discordGuildId or ""
    state.discordRoleId = parsed.discordRoleId or ""
    state.rules = parsed.rules or Config.DefaultRules
end

---Updates in-memory whitelist cache from MySQL
---@param callback function?
local function refreshWhitelistCache(callback)
    local query = "SELECT DISTINCT w.id, wi.identifier FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE CAST(w.whitelisted AS UNSIGNED) = 1"
    MySQL.query(query, {}, function(results)
        local newCache = {}
        if results then
            for i = 1, #results do
                newCache[results[i].identifier] = results[i].id
            end
        end
        whitelistCache = newCache
        if callback then
            callback()
        end
    end)
end

---Starts a grace period for a connected player before dropping them
---@param playerId number
---@param playerName string
local function startGracePeriod(playerId, playerName)
    if not playerId or playerId == 0 then
        return
    end

    if state.gracePeriod <= 0 then
        DropPlayer(tostring(playerId), Util.Translate(translations, "kick_message"))
        return
    end

    gracePeriodPlayers[playerId] = {
        endTime = os.time() + state.gracePeriod,
        playerName = playerName
    }

    TriggerClientEvent("esx_whitelist:startGracePeriod", playerId, state.gracePeriod)

    SetTimeout(state.gracePeriod * 1000, function()
        if gracePeriodPlayers[playerId] then
            if isPlayerAdmin(playerId) then
                gracePeriodPlayers[playerId] = nil
                return
            end
            DropPlayer(tostring(playerId), Util.Translate(translations, "kick_message"))
            gracePeriodPlayers[playerId] = nil
        end
    end)
end

---Kicks or starts grace period for non-whitelisted players in chunked batches to prevent lag spikes
local function kickNonWhitelistedPlayers()
    CreateThread(function()
        local playerIds = GetPlayers()
        local count = #playerIds

        for i = 1, count do
            local src = tonumber(playerIds[i])
            if src and not adminSources[src] and not isPlayerAdmin(src) then
                local identifiers = Util.GetPlayerIdentifiersFiltered(src)
                local isWhitelisted = false

                for j = 1, #identifiers do
                    if whitelistCache[identifiers[j]] then
                        isWhitelisted = true
                        break
                    end
                end

                if not isWhitelisted then
                    if state.kickConnected then
                        DropPlayer(tostring(src), Util.Translate(translations, "kick_message"))
                    else
                        local name = GetPlayerName(src) or "Unknown"
                        startGracePeriod(src, name)
                    end
                end
            end

            if (i % KICK_CHUNK_SIZE) == 0 then
                Wait(0)
            end
        end
    end)
end

---Evaluates active dynamic whitelist rules in priority order
---@return boolean
local function evaluateWhitelistRules()
    local activeRules = {}
    for i = 1, #state.rules do
        if state.rules[i].enabled then
            activeRules[#activeRules + 1] = Class.WhitelistRule.new(state.rules[i])
        end
    end

    table.sort(activeRules, function(a, b)
        return a.priority < b.priority
    end)

    for i = 1, #activeRules do
        local isApplicable, desiredState = activeRules[i]:evaluate(onlinePlayerCount, onlineAdminCount)
        if isApplicable and (desiredState ~= nil) then
            return desiredState
        end
    end

    return state.enabled
end

---Applies state changes if dynamic rule evaluations trigger an update
local function handleRuleEvaluation()
    if isManualOverride or ruleChangeDebounce then
        return
    end

    ruleChangeDebounce = true

    local newState = evaluateWhitelistRules()
    if newState ~= state.enabled then
        state.enabled = newState

        if state.enabled then
            sendDiscordLog(Util.Translate(translations, "whitelist_enabled_auto"), Enum.DiscordEmbedColor.DANGER)
            kickNonWhitelistedPlayers()
        else
            sendDiscordLog(Util.Translate(translations, "whitelist_disabled_auto"), Enum.DiscordEmbedColor.SUCCESS)
            for src in pairs(gracePeriodPlayers) do
                gracePeriodPlayers[src] = nil
                TriggerClientEvent("esx_whitelist:cancelGracePeriod", src)
            end
        end

        TriggerClientEvent("esx_whitelist:stateChanged", -1, state.enabled)
        saveConfig()
    end

    SetTimeout(5000, function()
        ruleChangeDebounce = false
    end)
end

---Checks a Discord user ID for the required role with in-memory TTL caching
---@param discordId string
---@param callback fun(hasRole: boolean)
local function checkDiscordRole(discordId, callback)
    if not state.discordEnabled or state.discordGuildId == "" or state.discordRoleId == "" or not Util.IsValidBotToken(state.discordBotToken) then
        callback(false)
        return
    end

    local cached = discordCache[discordId]
    if cached and (cached.expireAt > os.time()) then
        callback(cached.hasRole)
        return
    end

    local endpoint = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(state.discordGuildId, discordId)
    PerformHttpRequest(endpoint, function(statusCode, data)
        local hasRole = false
        if statusCode == 200 and data then
            local member = json.decode(data)
            if member and member.roles then
                for i = 1, #member.roles do
                    if member.roles[i] == state.discordRoleId then
                        hasRole = true
                        break
                    end
                end
            end
        end

        discordCache[discordId] = {
            hasRole = hasRole,
            expireAt = os.time() + DISCORD_CACHE_TTL_SECONDS
        }

        callback(hasRole)
    end, "GET", "", {
        ["Authorization"] = "Bot " .. state.discordBotToken,
        ["Content-Type"] = "application/json"
    })
end

---Finds all associated identifiers for an online or stored player
---@param singleIdentifier string
---@param callback fun(identifiers: string[], playerName: string?, isOnline: boolean)
local function getAllPlayerIdentifiers(singleIdentifier, callback)
    local idType, idValue = Util.NormalizeIdentifier(singleIdentifier)
    if not idType or not idValue then
        callback({}, nil, false)
        return
    end

    local fullIdentifier = idType .. ":" .. idValue
    local players = ESX.GetExtendedPlayers()

    for i = 1, #players do
        local targetPlayer = players[i]
        if targetPlayer and targetPlayer.source then
            local identifiers = Util.GetPlayerIdentifiersFiltered(targetPlayer.source)
            for j = 1, #identifiers do
                if identifiers[j] == fullIdentifier then
                    local name = GetPlayerName(targetPlayer.source) or targetPlayer.getName()
                    callback(identifiers, name, true)
                    return
                end
            end
        end
    end

    local subQuery = "SELECT wi.identifier, w.player_name FROM whitelist_identifiers wi JOIN whitelist w ON w.id = wi.whitelist_id WHERE wi.whitelist_id = (SELECT whitelist_id FROM whitelist_identifiers WHERE identifier = ? LIMIT 1)"
    MySQL.query(subQuery, { fullIdentifier }, function(results)
        if results and #results > 0 then
            local allIdentifiers = {}
            for i = 1, #results do
                allIdentifiers[#allIdentifiers + 1] = results[i].identifier
            end
            callback(allIdentifiers, results[1].player_name, false)
        else
            callback({ fullIdentifier }, nil, false)
        end
    end)
end

---Notifies an online player if they were whitelisted while in grace period
---@param fullIdentifier string
local function notifyOnlinePlayerWhitelisted(fullIdentifier)
    local players = ESX.GetExtendedPlayers()
    for i = 1, #players do
        local target = players[i]
        if target and target.source then
            local identifiers = Util.GetPlayerIdentifiersFiltered(target.source)
            for j = 1, #identifiers do
                if identifiers[j] == fullIdentifier then
                    target.showNotification("~g~" .. Util.Translate(translations, "added_to_whitelist"))
                    if gracePeriodPlayers[target.source] then
                        gracePeriodPlayers[target.source] = nil
                        TriggerClientEvent("esx_whitelist:cancelGracePeriod", target.source)
                    end
                    return
                end
            end
        end
    end
end

---Initializes database schema and ensures required tables and indices exist
local function initializeDatabase()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `whitelist` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `player_name` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
            `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
            `added_by` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
            `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_whitelisted` (`whitelisted`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `whitelist_identifiers` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `whitelist_id` INT NOT NULL,
            `type` VARCHAR(32) NOT NULL,
            `identifier` VARCHAR(255) NOT NULL COLLATE utf8mb4_bin,
            FOREIGN KEY (`whitelist_id`) REFERENCES `whitelist`(`id`) ON DELETE CASCADE,
            UNIQUE KEY `unique_identifier` (`type`, `identifier`),
            INDEX `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---Handles connecting player verification with O(1) memory lookup
---@param playerName string
---@param setKickReason fun(reason: string)
---@param deferrals table
local function onPlayerConnecting(playerName, setKickReason, deferrals)
    local src = source
    if not src or src == 0 then
        return
    end

    deferrals.defer()
    Wait(0)
    deferrals.update(Util.Translate(translations, "checking_whitelist"))

    local identifiers = Util.GetPlayerIdentifiersFiltered(src)
    if #identifiers == 0 then
        deferrals.done(Util.Translate(translations, "kick_message"))
        return
    end

    local realPlayerName = GetPlayerName(src) or playerName

    -- O(1) in-memory whitelist check
    local matchedWhitelistId = nil
    for i = 1, #identifiers do
        local id = whitelistCache[identifiers[i]]
        if id then
            matchedWhitelistId = id
            break
        end
    end

    -- If whitelist is disabled and no discord role check required
    if not state.enabled and not state.discordEnabled then
        deferrals.done()
        -- Asynchronously record player in database without blocking connection
        CreateThread(function()
            local conditions, params = Util.BuildIdentifierQuery(identifiers)
            MySQL.query("SELECT w.id FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE " .. conditions, params, function(res)
                if not res or #res == 0 then
                    MySQL.insert("INSERT INTO whitelist (player_name, whitelisted) VALUES (?, 0)", { realPlayerName }, function(insertId)
                        if insertId then
                            local inserts = {}
                            for j = 1, #identifiers do
                                local idType = identifiers[j]:match("^(%w+):")
                                if idType then
                                    inserts[#inserts + 1] = {
                                        query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                                        values = { insertId, idType, identifiers[j] }
                                    }
                                end
                            end
                            if #inserts > 0 then
                                MySQL.transaction(inserts)
                            end
                        end
                    end)
                end
            end)
        end)
        return
    end

    -- Whitelist is enabled or Discord verification is active
    if matchedWhitelistId and not state.discordEnabled then
        deferrals.done()
        return
    end

    -- Discord verification check
    if state.discordEnabled then
        local discordId = GetPlayerIdentifierByType(src, "discord")
        if not discordId then
            deferrals.done(Util.Translate(translations, "kick_message"))
            return
        end

        local cleanDiscord = discordId:gsub("discord:", "")
        checkDiscordRole(cleanDiscord, function(hasRole)
            if hasRole then
                deferrals.done()
                CreateThread(function()
                    local conditions, params = Util.BuildIdentifierQuery(identifiers)
                    MySQL.query("SELECT w.id FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE " .. conditions, params, function(res)
                        local targetId = (res and res[1]) and res[1].id
                        if targetId then
                            MySQL.update("UPDATE whitelist SET whitelisted = 1 WHERE id = ?", { targetId })
                            for i = 1, #identifiers do
                                whitelistCache[identifiers[i]] = targetId
                            end
                        else
                            MySQL.insert("INSERT INTO whitelist (player_name, whitelisted) VALUES (?, 1)", { realPlayerName }, function(newId)
                                if newId then
                                    local queries = {}
                                    for i = 1, #identifiers do
                                        local idType = identifiers[i]:match("^(%w+):")
                                        if idType then
                                            queries[#queries + 1] = {
                                                query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                                                values = { newId, idType, identifiers[i] }
                                            }
                                            whitelistCache[identifiers[i]] = newId
                                        end
                                    end
                                    if #queries > 0 then
                                        MySQL.transaction(queries)
                                    end
                                end
                            end)
                        end
                    end)
                end)
            else
                deferrals.done(Util.Translate(translations, "kick_message"))
            end
        end)
        return
    end

    -- Player is not whitelisted and whitelist is enabled
    deferrals.done(Util.Translate(translations, "kick_message"))
end

---Registers ESX server callbacks for NUI control panel
local function registerServerCallbacks()
    ESX.RegisterServerCallback("esx_whitelist:getConfig", function(source, cb)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb(nil)
            return
        end

        cb({
            whitelistEnabled = state.enabled,
            gracePeriod = state.gracePeriod,
            kickConnected = state.kickConnected,
            discordWebhook = state.discordWebhook ~= "" and "***CONFIGURED***" or "",
            discordEnabled = state.discordEnabled,
            discordGuildId = state.discordGuildId,
            discordRoleId = state.discordRoleId,
            rules = state.rules,
            locale = Config.Locale,
            translations = translations,
            hasBotToken = state.discordEnabled and Util.IsValidBotToken(state.discordBotToken)
        })
    end)

    ESX.RegisterServerCallback("esx_whitelist:getWhitelistEntries", function(source, cb)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb({})
            return
        end

        local query = [[
            SELECT w.id, w.player_name, CAST(w.whitelisted AS UNSIGNED) as whitelisted,
                   GROUP_CONCAT(wi.identifier SEPARATOR '|') as identifiers
            FROM whitelist w
            LEFT JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id
            GROUP BY w.id
            ORDER BY w.whitelisted DESC, w.id ASC
        ]]
        MySQL.query(query, {}, function(results)
            if not results then
                cb({})
                return
            end

            local entries = {}
            for i = 1, #results do
                local row = results[i]
                local ids = {}
                if row.identifiers then
                    for id in string.gmatch(row.identifiers, "[^|]+") do
                        ids[#ids + 1] = id
                    end
                end

                entries[#entries + 1] = {
                    id = row.id,
                    identifiers = ids,
                    playerName = row.player_name or "Unknown",
                    whitelisted = row.whitelisted
                }
            end

            cb(entries)
        end)
    end)

    ESX.RegisterServerCallback("esx_whitelist:updateConfig", function(source, cb, configData)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb(false)
            return
        end

        if configData.discordEnabled and not Util.IsValidBotToken(state.discordBotToken) then
            TriggerClientEvent("esx:showNotification", source, "~r~Discord bot token not configured")
            cb(false)
            return
        end

        if configData.discordEnabled and ((not configData.discordGuildId or configData.discordGuildId == "") or (not configData.discordRoleId or configData.discordRoleId == "")) then
            TriggerClientEvent("esx:showNotification", source, "~r~Discord configuration incomplete")
            cb(false)
            return
        end

        local oldState = state.enabled
        local xPlayer = ESX.GetPlayerFromId(source)
        local adminName = xPlayer and xPlayer.getName() or "Admin"

        if configData.discordWebhook and configData.discordWebhook ~= "" and configData.discordWebhook ~= "***CONFIGURED***" then
            if string.match(configData.discordWebhook, "^https://discord.com/api/webhooks/") or string.match(configData.discordWebhook, "^https://discordapp.com/api/webhooks/") then
                state.discordWebhook = configData.discordWebhook
            end
        end

        state.enabled = configData.whitelistEnabled == true
        state.gracePeriod = tonumber(configData.gracePeriod) or 60
        state.kickConnected = configData.kickConnected == true
        state.discordEnabled = configData.discordEnabled == true
        state.discordGuildId = configData.discordGuildId or ""
        state.discordRoleId = configData.discordRoleId or ""
        state.rules = configData.rules or state.rules
        isManualOverride = false

        saveConfig()

        if state.enabled and not oldState then
            sendDiscordLog(Util.Translate(translations, "whitelist_enabled_manual", adminName), Enum.DiscordEmbedColor.DANGER)
            Wait(1000)
            kickNonWhitelistedPlayers()
        elseif not state.enabled and oldState then
            sendDiscordLog(Util.Translate(translations, "whitelist_disabled_manual", adminName), Enum.DiscordEmbedColor.SUCCESS)
            for src in pairs(gracePeriodPlayers) do
                gracePeriodPlayers[src] = nil
                TriggerClientEvent("esx_whitelist:cancelGracePeriod", src)
            end
        end

        TriggerClientEvent("esx_whitelist:stateChanged", -1, state.enabled)
        TriggerClientEvent("esx:showNotification", source, "~g~" .. Util.Translate(translations, "config_saved"))
        cb(true)
    end)

    ESX.RegisterServerCallback("esx_whitelist:testWebhook", function(source, cb)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb(false)
            return
        end

        local xPlayer = ESX.GetPlayerFromId(source)
        local adminName = xPlayer and xPlayer.getName() or "Admin"
        sendDiscordLog(Util.Translate(translations, "webhook_test", adminName), Enum.DiscordEmbedColor.PRIMARY)
        cb(true)
    end)

    ESX.RegisterServerCallback("esx_whitelist:managePlayer", function(source, cb, data)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb(false, "No permission")
            return
        end

        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then
            cb(false, "Error getting admin data")
            return
        end

        local adminIdentifier = xPlayer.getIdentifier() or "admin"
        local rawIdentifier = data.identifier
        local action = data.action

        local idType, idValue = Util.NormalizeIdentifier(rawIdentifier)
        if not idType or not idValue then
            cb(false, "Invalid identifier format")
            return
        end

        local fullIdentifier = idType .. ":" .. idValue

        if action == "add" then
            getAllPlayerIdentifiers(fullIdentifier, function(allIdentifiers, existingName, isOnline)
                local targetName = existingName or "Pending..."
                local query = "SELECT w.id, w.whitelisted FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE wi.identifier = ?"

                MySQL.query(query, { fullIdentifier }, function(result)
                    if result and #result > 0 then
                        if result[1].whitelisted == 1 then
                            cb(false, "Player already whitelisted")
                            return
                        end

                        MySQL.update("UPDATE whitelist SET whitelisted = 1, added_by = ?, player_name = ? WHERE id = ?", {
                            adminIdentifier, targetName, result[1].id
                        }, function()
                            local updates = {}
                            for i = 1, #allIdentifiers do
                                local typePart = allIdentifiers[i]:match("^(%w+):")
                                if typePart then
                                    updates[#updates + 1] = {
                                        query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE whitelist_id = VALUES(whitelist_id)",
                                        values = { result[1].id, typePart, allIdentifiers[i] }
                                    }
                                end
                            end

                            if #updates > 0 then
                                MySQL.transaction(updates, function(ok)
                                    if ok then
                                        for i = 1, #allIdentifiers do
                                            whitelistCache[allIdentifiers[i]] = result[1].id
                                        end
                                    end
                                end)
                            else
                                for i = 1, #allIdentifiers do
                                    whitelistCache[allIdentifiers[i]] = result[1].id
                                end
                            end

                            sendDiscordLog(("%s added %s (%s) to whitelist"):format(xPlayer.getName(), targetName, idType), Enum.DiscordEmbedColor.SUCCESS)
                            if isOnline then
                                notifyOnlinePlayerWhitelisted(fullIdentifier)
                            end
                            cb(true, "Player added successfully")
                        end)
                    else
                        MySQL.insert("INSERT INTO whitelist (player_name, whitelisted, added_by) VALUES (?, 1, ?)", {
                            targetName, adminIdentifier
                        }, function(newId)
                            if newId then
                                local inserts = {}
                                for i = 1, #allIdentifiers do
                                    local typePart = allIdentifiers[i]:match("^(%w+):")
                                    if typePart then
                                        inserts[#inserts + 1] = {
                                            query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                                            values = { newId, typePart, allIdentifiers[i] }
                                        }
                                        whitelistCache[allIdentifiers[i]] = newId
                                    end
                                end

                                if #inserts > 0 then
                                    MySQL.transaction(inserts)
                                end

                                sendDiscordLog(("%s added %s (%s) to whitelist"):format(xPlayer.getName(), targetName, idType), Enum.DiscordEmbedColor.SUCCESS)
                                if isOnline then
                                    notifyOnlinePlayerWhitelisted(fullIdentifier)
                                end
                                cb(true, "Player added successfully")
                            else
                                cb(false, "Error creating database entry")
                            end
                        end)
                    end
                end)
            end)
        elseif action == "remove" then
            local query = "SELECT w.id, w.whitelisted FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE wi.identifier = ?"
            MySQL.query(query, { fullIdentifier }, function(result)
                if not result or #result == 0 or result[1].whitelisted == 0 then
                    cb(false, "Player not in whitelist")
                    return
                end

                local wlId = result[1].id
                MySQL.update("UPDATE whitelist SET whitelisted = 0 WHERE id = ?", { wlId }, function()
                    MySQL.query("SELECT identifier FROM whitelist_identifiers WHERE whitelist_id = ?", { wlId }, function(idResults)
                        if idResults then
                            for i = 1, #idResults do
                                whitelistCache[idResults[i].identifier] = nil
                            end
                        end
                        sendDiscordLog(("%s removed %s from whitelist"):format(xPlayer.getName(), fullIdentifier), Enum.DiscordEmbedColor.DANGER)
                        cb(true, "Player removed successfully")
                    end)
                end)
            end)
        else
            cb(false, "Invalid action")
        end
    end)

    ESX.RegisterServerCallback("esx_whitelist:toggleWhitelistStatus", function(source, cb, data)
        if not source or source == 0 or not isPlayerAdmin(source) then
            cb(false)
            return
        end

        local xPlayer = ESX.GetPlayerFromId(source)
        local adminName = xPlayer and xPlayer.getName() or "Admin"
        local targetStatus = tonumber(data.status) or 0
        local targetId = tonumber(data.id)

        if not targetId then
            cb(false)
            return
        end

        MySQL.update("UPDATE whitelist SET whitelisted = ? WHERE id = ?", { targetStatus, targetId }, function()
            MySQL.query("SELECT identifier FROM whitelist_identifiers WHERE whitelist_id = ?", { targetId }, function(res)
                if res then
                    for i = 1, #res do
                        if targetStatus == 1 then
                            whitelistCache[res[i].identifier] = targetId
                        else
                            whitelistCache[res[i].identifier] = nil
                        end
                    end
                end

                local color = targetStatus == 1 and Enum.DiscordEmbedColor.SUCCESS or Enum.DiscordEmbedColor.DANGER
                sendDiscordLog(("%s changed whitelist status to %s for entry ID: %s"):format(adminName, targetStatus == 1 and "Whitelisted" or "Removed", targetId), color)
                cb(true)
            end)
        end)
    end)

    ESX.RegisterServerCallback("esx_whitelist:detectIdentifier", function(source, cb, rawValue)
        local idType, idValue = Util.NormalizeIdentifier(rawValue)
        cb({
            type = idType,
            value = idValue,
            valid = (idType ~= nil) and (idValue ~= nil)
        })
    end)
end

---Registers in-game and console administrative commands
local function registerCommands()
    if Config.InGameCommands then
        ESX.RegisterCommand("wl_add", "admin", function(xPlayer, args)
            if not args.id then
                xPlayer.showNotification("~r~Usage: /wl_add [player id]")
                return
            end

            local targetId = tonumber(args.id)
            local targetPlayer = ESX.GetPlayerFromId(targetId)
            if not targetPlayer then
                xPlayer.showNotification("~r~Player not found")
                return
            end

            local targetIdentifiers = Util.GetPlayerIdentifiersFiltered(targetId)
            if #targetIdentifiers == 0 then
                xPlayer.showNotification("~r~No identifiers found for player")
                return
            end

            local conditions, params = Util.BuildIdentifierQuery(targetIdentifiers)
            local query = "SELECT w.id, w.whitelisted FROM whitelist w JOIN whitelist_identifiers wi ON w.id = wi.whitelist_id WHERE " .. conditions
            MySQL.query(query, params, function(res)
                if res and #res > 0 then
                    if res[1].whitelisted == 1 then
                        xPlayer.showNotification("~r~Player already whitelisted")
                        return
                    end

                    MySQL.update("UPDATE whitelist SET whitelisted = 1, added_by = ? WHERE id = ?", {
                        xPlayer.getIdentifier(), res[1].id
                    }, function()
                        for i = 1, #targetIdentifiers do
                            whitelistCache[targetIdentifiers[i]] = res[1].id
                        end
                        xPlayer.showNotification("~g~Player added to whitelist")
                        targetPlayer.showNotification("~g~You have been added to the whitelist")

                        if gracePeriodPlayers[targetId] then
                            gracePeriodPlayers[targetId] = nil
                            TriggerClientEvent("esx_whitelist:cancelGracePeriod", targetId)
                        end
                    end)
                else
                    MySQL.insert("INSERT INTO whitelist (player_name, whitelisted, added_by) VALUES (?, 1, ?)", {
                        targetPlayer.getName(), xPlayer.getIdentifier()
                    }, function(insertId)
                        if insertId then
                            local inserts = {}
                            for i = 1, #targetIdentifiers do
                                local idType = targetIdentifiers[i]:match("^(%w+):")
                                if idType then
                                    inserts[#inserts + 1] = {
                                        query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                                        values = { insertId, idType, targetIdentifiers[i] }
                                    }
                                    whitelistCache[targetIdentifiers[i]] = insertId
                                end
                            end
                            if #inserts > 0 then
                                MySQL.transaction(inserts)
                            end
                            xPlayer.showNotification("~g~Player added to whitelist")
                            targetPlayer.showNotification("~g~You have been added to the whitelist")
                        end
                    end)
                end
            end)
        end, false, {
            help = "Add player to whitelist",
            validate = true,
            arguments = {
                { name = "id", help = "Player ID", type = "number" }
            }
        })

        ESX.RegisterCommand("wl_check", "admin", function(xPlayer, args)
            if not args.id then
                xPlayer.showNotification("~r~Usage: /wl_check [player id]")
                return
            end

            local targetId = tonumber(args.id)
            local targetPlayer = ESX.GetPlayerFromId(targetId)
            if not targetPlayer then
                xPlayer.showNotification("~r~Player not found")
                return
            end

            local targetIdentifiers = Util.GetPlayerIdentifiersFiltered(targetId)
            local isWhitelisted = false
            for i = 1, #targetIdentifiers do
                if whitelistCache[targetIdentifiers[i]] then
                    isWhitelisted = true
                    break
                end
            end

            local name = targetPlayer.getName()
            if isWhitelisted then
                xPlayer.showNotification("~g~" .. name .. " is whitelisted")
            else
                xPlayer.showNotification("~r~" .. name .. " is NOT whitelisted")
            end
        end, false, {
            help = "Check player whitelist status",
            validate = true,
            arguments = {
                { name = "id", help = "Player ID", type = "number" }
            }
        })

        ESX.RegisterCommand("wl_sync", "admin", function(xPlayer)
            refreshWhitelistCache(function()
                xPlayer.showNotification("~g~Whitelist cache synchronized with database")
            end)
        end, false, { help = "Sync whitelist cache with database" })
    end
end

---Called when a player is loaded to update online stats and trigger rule evaluations
---@param playerId number
---@param xPlayer any
local function onPlayerLoaded(playerId, xPlayer)
    onlinePlayerCount = onlinePlayerCount + 1
    if isPlayerAdmin(playerId) then
        adminSources[playerId] = true
        onlineAdminCount = onlineAdminCount + 1
    end
    handleRuleEvaluation()
end

---Called when a player drops to update online stats and clean up grace periods
---@param playerId number
---@param reason string
local function onPlayerDropped(playerId, reason)
    if gracePeriodPlayers[playerId] then
        gracePeriodPlayers[playerId] = nil
    end

    if adminSources[playerId] then
        adminSources[playerId] = nil
        onlineAdminCount = math.max(0, onlineAdminCount - 1)
    end

    onlinePlayerCount = math.max(0, onlinePlayerCount - 1)
    handleRuleEvaluation()
end

---Initializes the whitelist subsystem on resource start
local function init()
    loadConfig()
    initializeDatabase()
    refreshWhitelistCache(function()
        local status = state.enabled and "enabled" or "disabled"
        print(("^2[esx_whitelist]^0 Whitelist system initialized - Status: %s - Grace Period: %ss"):format(status, state.gracePeriod))
    end)

    registerServerCallbacks()
    registerCommands()

    -- Recurring schedule rule check (every 30s)
    CreateThread(function()
        while true do
            Wait(30000)
            handleRuleEvaluation()
        end
    end)
end

Whitelist.Init = init
Whitelist.OnPlayerConnecting = onPlayerConnecting
Whitelist.OnPlayerLoaded = onPlayerLoaded
Whitelist.OnPlayerDropped = onPlayerDropped
Whitelist.RefreshCache = refreshWhitelistCache

return Whitelist
