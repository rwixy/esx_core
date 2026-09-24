-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local Discord <const> = xLib.require "@esx_whitelist.server.module.whitelist.discord"
local Auth <const> = xLib.require "@esx_whitelist.server.module.whitelist.auth"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

---@class Connection
---@description Manages player connection authorization, grace periods, and enforcement of whitelist rules.
local Connection = {}
local GRACE_MIN <const>, GRACE_MAX <const> = 0, 600
local KICK_CHUNK <const> = 25

local function finish(deferrals, allow, reason)
    if allow then
        deferrals.done()
    else
        deferrals.done(reason or Util.Translate(State.translations, "kick_message"))
    end
end

local DATABASE_TIMEOUT <const> = 10000

local function whenDatabaseReady(callback)
    if State.databaseReady then return callback(true) end

    CreateThread(function()
        local deadline = GetGameTimer() + DATABASE_TIMEOUT
        while not State.databaseReady and GetGameTimer() < deadline do Wait(100) end
        callback(State.databaseReady)
    end)
end

local function enforce(source, translations, useGrace)
    source = tonumber(source)
    if not source or source <= 0 then return end

    Connection.Authorize(source, function(allow)
        if allow then
            if State.gracePlayers[source] then
                State.gracePlayers[source] = nil
                TriggerClientEvent("esx_whitelist:cancelGracePeriod", source)
            end
            return
        end

        if State.config.kickConnected or useGrace == false then
            DropPlayer(tostring(source), Util.Translate(translations or State.translations, "kick_message"))
        else
            Connection.StartGrace(source, GetPlayerName(source) or "Unknown", translations or State.translations)
        end
    end)
end

local function identifiersFor(source)
    local identifiers = Util.GetPlayerIdentifiersFiltered(source)
    Cache.SetIdentifiers(source, identifiers)
    return identifiers
end

local function persistAccess(source, identifiers, addedBy, callback)
    local function persist()
        Database.EnsureWhitelisted(
            GetPlayerName(source) or "Unknown",
            identifiers,
            addedBy,
            function(saved, err, whitelistId)
                if saved and whitelistId then
                    TriggerClientEvent("esx_whitelist:entryChanged", -1, whitelistId)
                end
                callback(saved == true, err, whitelistId)
            end
        )
    end

    whenDatabaseReady(function(ready)
        if not ready then return callback(false, "database_unavailable") end
        persist()
    end)
end

local function persistAdmin(source, identifiers, callback)
    persistAccess(source, identifiers, "system:admin", callback)
end

local function checkDiscord(source, callback)
    local discordIdentifier = GetPlayerIdentifierByType(source, "discord")
    if not discordIdentifier then return callback(false, "missing_discord") end

    local discordId = discordIdentifier:gsub("^discord:", "")
    Discord.CheckRole(discordId, function(hasRole, err)
        if err then return callback(false, "discord_error") end
        callback(hasRole == true, hasRole and "discord" or "not_whitelisted")
    end)
end

-- The configured method is authoritative. Identifier and Discord checks are
-- never silently used as each other's fallback.
---@description Authorizes a player connection by checking configured identifiers, admin status, Discord role, or database whitelist.
---@param source number The player source ID
---@param callback fun(allow: boolean, reason: string?)
function Connection.Authorize(source, callback)
    source = tonumber(source)
    if not source or source <= 0 then return callback(false, "invalid_source") end

    local identifiers = Cache.GetIdentifiers(source)
    if #identifiers == 0 then identifiers = identifiersFor(source) end

    if Config.Debug then
        local identifierList = #identifiers > 0 and table.concat(identifiers, ", ") or "none"
        print(("^3[esx_whitelist] Authorization check for source %s: identifiers=[%s]^7"):format(source, identifierList))
    end

    local configuredMatch = Auth.HasConfiguredIdentifier(identifiers)
    if Config.Debug then
        print(("^3[esx_whitelist] Configured identifier match: %s^7"):format(tostring(configuredMatch)))
    end
    if configuredMatch then
        return callback(true, "configured_identifier")
    end

    local function checkAdmin(alreadyChecked)
        Auth.IsAdminAsync(source, identifiers, function(isAdmin)
            if isAdmin then
                return persistAdmin(source, identifiers, function(saved, err, whitelistId)
                    callback(saved == true, saved and "admin" or (err or "admin_persist_failed"))
                end)
            end

            if not State.config.enabled then
                return callback(false, "disabled")
            end

            if State.config.authorizationMethod == "discord" then
                return checkDiscord(source, function(hasRole, reason)
                    if not hasRole then
                        return callback(false, reason or "not_whitelisted")
                    end

                    persistAccess(source, identifiers, "system:discord", function(saved, err)
                        callback(saved, saved and "discord" or (err or "discord_persist_failed"))
                    end)
                end)
            end

            local function checkIdentifierWhitelist()
                local whitelisted = Cache.IsWhitelisted(identifiers)
                callback(whitelisted == true, whitelisted and "identifier" or "not_whitelisted")
            end

            if State.databaseReady then return checkIdentifierWhitelist() end

            whenDatabaseReady(function(ready)
                if not ready then return callback(false, "database_unavailable") end
                checkIdentifierWhitelist()
            end)
        end, alreadyChecked == true)
    end

    local localAdmin = Auth.IsAdmin(source)
    if localAdmin then return checkAdmin(true) end
    if State.databaseReady then return checkAdmin(false) end

    whenDatabaseReady(function(ready)
        if not ready then return callback(false, "database_unavailable") end
        checkAdmin(false)
    end)
end

---@description Starts a grace period for a non-whitelisted connected player before kicking them.
---@param source number The player source ID
---@param playerName string The player display name
---@param translations table Locale translation strings
function Connection.StartGrace(source, playerName, translations)
    source = tonumber(source)
    translations = translations or State.translations
    if not source or source <= 0 then return end

    local seconds = math.max(GRACE_MIN, math.min(GRACE_MAX, tonumber(State.config.gracePeriod) or 0))
    if seconds <= 0 then
        DropPlayer(tostring(source), Util.Translate(translations, "kick_message"))
        return
    end

    State.gracePlayers[source] = {
        endTime = GetGameTimer() + seconds * 1000,
        playerName = playerName or "Unknown"
    }
    TriggerClientEvent("esx_whitelist:startGracePeriod", source, seconds)

    SetTimeout(seconds * 1000, function()
        if not State.gracePlayers[source] then return end
        enforce(source, translations, false)
    end)
end

---@description Kicks all connected players who are not whitelisted.
---@param translations table Locale translation strings
function Connection.KickNonWhitelisted(translations)
    CreateThread(function()
        local players = GetPlayers()
        for i = 1, #players do
            local source = tonumber(players[i])
            if source and not State.gracePlayers[source] then
                enforce(source, translations)
            end
            if i % KICK_CHUNK == 0 then Wait(0) end
        end
    end)
end

---@description Verifies a player during the connection deferral process.
---@param playerSource number The player source ID
---@param playerName string The player display name
---@param setKickReason fun(reason: string)
---@param deferrals table Connection deferral object
---@param translations table Locale translation strings
function Connection.Verify(playerSource, playerName, setKickReason, deferrals, translations)
    local source = tonumber(playerSource)
    if not source or source <= 0 then
        return finish(deferrals, false, "Invalid player connection.")
    end

    deferrals.defer()
    Wait(0)
    deferrals.update(Util.Translate(translations, "checking_whitelist"))

    local finished = false
    local function finishOnce(allow, reason)
        if finished then return end
        finished = true
        finish(deferrals, allow, reason)
    end

    SetTimeout(Discord.DeferralTimeout() + 500, function()
        finishOnce(false, Util.Translate(translations, "kick_message"))
    end)

    Connection.Authorize(source, function(allow, reason)
        if allow then
            State.gracePlayers[source] = nil
            return finishOnce(true)
        end

        if Config.Debug then
            print(("^1[esx_whitelist] Rejected source %s: %s^7"):format(source, reason or "unknown"))
        end
        if reason == "discord_error" then
            return finishOnce(false, Util.Translate(translations, "discord_check_failed"))
        end

        finishOnce(false, Util.Translate(translations, "kick_message"))
    end)
end

---@description Forces enforcement of whitelist rules on a player (public alias for local enforce).
---@param source number The player source ID
---@param translations table Locale translation strings
---@param useGrace boolean Whether grace period applies
Connection.Enforce = enforce

return Connection
