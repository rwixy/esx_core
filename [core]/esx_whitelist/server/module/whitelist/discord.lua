local ServerConfig <const> = xLib.require "@esx_whitelist.server.config.main"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"

local Discord = {}

local POSITIVE_TTL = 300
local NEGATIVE_TTL = 60
local MAX_ATTEMPTS = 3
local RETRY_DELAY = 1000
local TIMEOUT = 20000
local cache = {}
local pending = {}
local webhookCooldownUntil = 0

State.config.discordBotToken = ServerConfig.DiscordBotToken or ""

local function configured()
    return State.config.discordEnabled
        and State.config.discordGuildId ~= ""
        and State.config.discordRoleId ~= ""
        and Util.IsValidBotToken(State.config.discordBotToken)
end

function Discord.HasValidToken()
    return Util.IsValidBotToken(State.config.discordBotToken)
end

function Discord.CheckRole(discordId, callback)
    if not configured() then return callback(false, "disabled") end
    if type(discordId) ~= "string" or not discordId:match("^%d+$") then return callback(false, "invalid") end

    local now = os.time()
    local cached = cache[discordId]
    if cached and cached.expires > now then return callback(cached.hasRole) end

    if pending[discordId] then
        pending[discordId][#pending[discordId] + 1] = callback
        return
    end
    pending[discordId] = { callback }

    local endpoint = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(State.config.discordGuildId, discordId)
    local headers = {
        ["Authorization"] = "Bot " .. State.config.discordBotToken,
        ["Content-Type"] = "application/json"
    }
    local attempts = 0

    local function finish(hasRole, err)
        if not err then
            cache[discordId] = {
                hasRole = hasRole,
                expires = os.time() + (hasRole and POSITIVE_TTL or NEGATIVE_TTL)
            }
        end
        local callbacks = pending[discordId] or {}
        pending[discordId] = nil
        for i = 1, #callbacks do callbacks[i](hasRole, err) end
    end

    local function attempt()
        attempts = attempts + 1
        PerformHttpRequest(endpoint, function(statusCode, data)
            if statusCode == 200 and data then
                local ok, member = pcall(json.decode, data)
                if not ok then return finish(false, "invalid_response") end
                local hasRole = false
                if member and type(member.roles) == "table" then
                    for i = 1, #member.roles do
                        if member.roles[i] == State.config.discordRoleId then
                            hasRole = true
                            break
                        end
                    end
                end
                finish(hasRole)
            elseif (statusCode == 429 or statusCode >= 500 or statusCode == 0) and attempts < MAX_ATTEMPTS then
                SetTimeout(RETRY_DELAY * attempts, attempt)
            else
                finish(false, "error")
            end
        end, "GET", "", headers)
    end

    attempt()
end

function Discord.SendLog(message, color, translations)
    local webhook = State.config.discordWebhook
    if type(webhook) ~= "string" or webhook == "" or webhook == "***CONFIGURED***" then return false end
    local now = GetGameTimer()
    if now < webhookCooldownUntil then return false end
    webhookCooldownUntil = now + 5000

    local payload = json.encode({ embeds = {{
        title = Util.Translate(translations, "discord_title"),
        description = message,
        color = color or Enum.DiscordEmbedColor.PRIMARY,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
    }}})

    PerformHttpRequest(webhook, function() end, "POST", payload, { ["Content-Type"] = "application/json" })
    return true
end

function Discord.Sweep()
    local now = os.time()
    for id, entry in pairs(cache) do
        if entry.expires <= now then cache[id] = nil end
    end
end

function Discord.DeferralTimeout()
    return TIMEOUT
end

function Discord.FailOpen()
    return false
end

return Discord
