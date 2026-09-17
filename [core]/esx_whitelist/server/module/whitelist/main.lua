local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local ConfigService <const> = xLib.require "@esx_whitelist.server.module.whitelist.config"
local Database <const> = xLib.require "@esx_whitelist.server.module.whitelist.database"
local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"
local Auth <const> = xLib.require "@esx_whitelist.server.module.whitelist.auth"
local Rules <const> = xLib.require "@esx_whitelist.server.module.whitelist.rules"
local Connection <const> = xLib.require "@esx_whitelist.server.module.whitelist.connection"
local Callbacks <const> = xLib.require "@esx_whitelist.server.module.whitelist.callbacks"
local Commands <const> = xLib.require "@esx_whitelist.server.module.whitelist.commands"
local Discord <const> = xLib.require "@esx_whitelist.server.module.whitelist.discord"
local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

local Whitelist = {}
local initialized = false

local function applyStateChanged(enabled, manual, adminName)
    if manual then
        Discord.SendLog(Util.Translate(State.translations, enabled and "whitelist_enabled_manual" or "whitelist_disabled_manual", adminName), enabled and Enum.DiscordEmbedColor.DANGER or Enum.DiscordEmbedColor.SUCCESS, State.translations)
    else
        Discord.SendLog(Util.Translate(State.translations, enabled and "whitelist_enabled_auto" or "whitelist_disabled_auto"), enabled and Enum.DiscordEmbedColor.DANGER or Enum.DiscordEmbedColor.SUCCESS, State.translations)
    end

    if not enabled then
        for source in pairs(State.gracePlayers) do
            State.gracePlayers[source] = nil
            TriggerClientEvent("esx_whitelist:cancelGracePeriod", source)
        end
    else
        Connection.KickNonWhitelisted(State.translations)
    end
    TriggerClientEvent("esx_whitelist:stateChanged", -1, enabled)
end

local function reconcileOnline()
    CreateThread(function()
        Wait(2000)
        State.onlinePlayerCount = 0
        State.onlineAdminCount = 0
        State.onlineSources = {}
        State.adminSources = {}
        State.playerIdentifiers = {}
        State.onlineIdentifierSources = {}

        local players = ESX.GetExtendedPlayers()
        for i = 1, #players do
            local player = players[i]
            local source = player and tonumber(player.source)
            if source then
                State.onlineSources[source] = true
                Cache.SetIdentifiers(source, Util.GetPlayerIdentifiersFiltered(source))
                State.onlinePlayerCount = State.onlinePlayerCount + 1
                if Auth.IsAdmin(source) then State.onlineAdminCount = State.onlineAdminCount + 1 end
            end
        end
    end)
end

local function startMaintenance()
    CreateThread(function()
        while true do
            Wait(30000)
            Rules.EvaluateAndApply(applyStateChanged)
        end
    end)
    CreateThread(function()
        while true do
            Wait(300000)
            Discord.Sweep()
        end
    end)
end

function Whitelist.Init()
    if initialized then return end
    initialized = true
    ConfigService.Load()
    Database.Init(function()
        Database.RefreshCache(function()
            Callbacks.Register(State.translations, applyStateChanged)
            Commands.Register(function() end)
            reconcileOnline()
            startMaintenance()
            print(("^2[esx_whitelist]^0 Initialized - %s - Grace: %ss"):format(State.config.enabled and "enabled" or "disabled", State.config.gracePeriod))
        end)
    end)
end

function Whitelist.OnPlayerConnecting(playerName, setKickReason, deferrals)
    Connection.Verify(playerName, setKickReason, deferrals, State.translations)
end

function Whitelist.OnPlayerLoaded(playerId)
    local source = tonumber(playerId)
    if not source or source <= 0 or State.onlineSources[source] then return end
    State.onlineSources[source] = true
    Cache.SetIdentifiers(source, Util.GetPlayerIdentifiersFiltered(source))
    State.onlinePlayerCount = State.onlinePlayerCount + 1
    if Auth.IsAdmin(source) then State.onlineAdminCount = State.onlineAdminCount + 1 end
    Rules.EvaluateAndApply(applyStateChanged)
end

function Whitelist.OnPlayerDropped(playerId)
    local source = tonumber(playerId)
    if not source or source <= 0 then return end
    Cache.ClearIdentifiers(source)
    State.gracePlayers[source] = nil
    if State.onlineSources[source] then
        State.onlineSources[source] = nil
        if State.adminSources[source] then State.onlineAdminCount = math.max(0, State.onlineAdminCount - 1) end
        Auth.Clear(source)
        State.onlinePlayerCount = math.max(0, State.onlinePlayerCount - 1)
        Rules.EvaluateAndApply(applyStateChanged)
    end
end

function Whitelist.RefreshCache(cb)
    Database.RefreshCache(cb)
end

return Whitelist
