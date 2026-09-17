local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local Discord <const> = xLib.require "@esx_whitelist.server.module.whitelist.discord"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

local Connection = {}
local GRACE_MIN, GRACE_MAX = 0, 600
local KICK_CHUNK = 50

local function finish(deferrals, done, reason)
    if done then return end
    done = true
    deferrals.done(reason)
    return done
end

function Connection.StartGrace(source, playerName, translations)
    if not source or source <= 0 then return end
    local seconds = State.config.gracePeriod
    if seconds <= GRACE_MIN then
        DropPlayer(tostring(source), Util.Translate(translations, "kick_message"))
        return
    end

    State.gracePlayers[source] = { endTime = GetGameTimer() + seconds * 1000, playerName = playerName }
    TriggerClientEvent("esx_whitelist:startGracePeriod", source, seconds)

    SetTimeout(seconds * 1000, function()
        if not State.gracePlayers[source] then return end
        if State.adminSources[source] == true then
            State.gracePlayers[source] = nil
            return
        end
        if Cache.IsWhitelisted(Cache.GetIdentifiers(source)) then
            State.gracePlayers[source] = nil
            TriggerClientEvent("esx_whitelist:cancelGracePeriod", source)
            return
        end
        DropPlayer(tostring(source), Util.Translate(translations, "kick_message"))
        State.gracePlayers[source] = nil
    end)
end

function Connection.KickNonWhitelisted(translations)
    CreateThread(function()
        local players = GetPlayers()
        for i = 1, #players do
            local source = tonumber(players[i])
            if source and not State.adminSources[source] then
                local identifiers = Cache.GetIdentifiers(source)
                local whitelisted = Cache.IsWhitelisted(identifiers)
                if not whitelisted then
                    if State.config.kickConnected then
                        DropPlayer(tostring(source), Util.Translate(translations, "kick_message"))
                    else
                        Connection.StartGrace(source, GetPlayerName(source) or "Unknown", translations)
                    end
                end
            end
            if i % KICK_CHUNK == 0 then Wait(0) end
        end
    end)
end

function Connection.Verify(playerName, setKickReason, deferrals, translations)
    local source = tonumber(source)
    if not source or source <= 0 then return end

    deferrals.defer()
    Wait(0)
    deferrals.update(Util.Translate(translations, "checking_whitelist"))

    local identifiers = Util.GetPlayerIdentifiersFiltered(source)
    if #identifiers == 0 then return finish(deferrals, false, Util.Translate(translations, "kick_message")) end

    local realName = GetPlayerName(source) or playerName or "Unknown"
    local cachedWhitelist = Cache.IsWhitelisted(identifiers)

    if not State.config.enabled and not State.config.discordEnabled then
        finish(deferrals, false)
        Database.FindByIdentifiers(identifiers, function(existing)
            if not existing then Database.InsertPlayer(realName, identifiers, false, nil, function() end) end
        end)
        return
    end

    if cachedWhitelist and not State.config.discordEnabled then
        finish(deferrals, false)
        return
    end

    if not State.config.discordEnabled then
        finish(deferrals, false, Util.Translate(translations, "kick_message"))
        return
    end

    local discordId = GetPlayerIdentifierByType(source, "discord")
    if not discordId then return finish(deferrals, false, Util.Translate(translations, "kick_message")) end
    discordId = discordId:gsub("^discord:", "")

    local settled = false
    local function complete(allow, reason)
        if settled then return end
        settled = true
        if allow then deferrals.done() else deferrals.done(reason or Util.Translate(translations, "kick_message")) end
    end

    SetTimeout(Discord.DeferralTimeout(), function()
        complete(Discord.FailOpen())
    end)

    Discord.CheckRole(discordId, function(hasRole, err)
        if err then
            complete(Discord.FailOpen())
            return
        end
        if not hasRole then
            complete(false)
            return
        end

        complete(true)
        Database.FindByIdentifiers(identifiers, function(existing)
            if existing then
                Database.SetStatus(existing.id, 1, nil, function()
                    for i = 1, #identifiers do Cache.SetWhitelist(identifiers[i], existing.id) end
                end)
            else
                Database.InsertPlayer(realName, identifiers, true, nil, function(id)
                    if id then for i = 1, #identifiers do Cache.SetWhitelist(identifiers[i], id) end end
                end)
            end
        end)
    end)
end

return Connection
