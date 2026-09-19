local ServerConfig <const> = xLib.require "@esx_whitelist.server.config.main"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"

---@class Discord
---@description Discord integration for role verification, webhook logging, and API communication with retry logic.
local Discord = {}

local POSITIVE_TTL <const> = 60
local NEGATIVE_TTL <const> = 30
local MAX_ATTEMPTS <const> = 3
local RETRY_DELAY <const> = 1000
local TIMEOUT <const> = 15000
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

---@description Checks if the Discord bot token is valid.
---@return boolean valid
function Discord.HasValidToken()
    return Util.IsValidBotToken(State.config.discordBotToken)
end

---@description Checks if a Discord user has the configured role, with caching and deduplication.
---@param discordId string Discord user ID
---@param callback fun(hasRole: boolean, error?: string)
function Discord.CheckRole(discordId, callback)
    if not configured() then
        return callback(false, "not_configured")
    end

    if type(discordId) ~= "string" or not discordId:match("^%d+$") then
        return callback(false, "invalid_discord_id")
    end

    local now = os.time()
    local cacheKey = ("%s:%s:%s"):format(State.config.discordGuildId, State.config.discordRoleId, discordId)
    local cached = cache[cacheKey]
    if cached and cached.expires > now then
        return callback(cached.hasRole, nil)
    end

    if pending[cacheKey] then
        pending[cacheKey].callbacks[#pending[cacheKey].callbacks + 1] = callback
        return
    end

    local request = { callbacks = { callback }, settled = false }
    pending[cacheKey] = request

    local function finish(hasRole, err)
        if request.settled then return end
        request.settled = true

        if not err then
            cache[cacheKey] = {
                hasRole = hasRole,
                expires = os.time() + (hasRole and POSITIVE_TTL or NEGATIVE_TTL)
            }
        end

        pending[cacheKey] = nil
        local callbacks = request.callbacks
        for i = 1, #callbacks do callbacks[i](hasRole, err) end
    end

    SetTimeout(TIMEOUT, function()
        finish(false, "discord_timeout")
    end)

    local endpoint = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(
        State.config.discordGuildId,
        discordId
    )
    local headers = {
        ["Authorization"] = "Bot " .. State.config.discordBotToken,
        ["Content-Type"] = "application/json"
    }
    local attempts = 0

    local function attempt()
        if request.settled then return end
        attempts = attempts + 1
        PerformHttpRequest(endpoint, function(statusCode, data, responseHeaders)
            if request.settled then return end

            if statusCode == 200 and data then
                local member = data
                if type(data) == "string" then
                    local ok, decoded = pcall(json.decode, data)
                    if not ok then return finish(false, "invalid_response") end
                    member = decoded
                end
                if type(member) ~= "table" then return finish(false, "invalid_response") end

                local hasRole = false
                for i = 1, #(member.roles or {}) do
                    if member.roles[i] == State.config.discordRoleId then
                        hasRole = true
                        break
                    end
                end
                return finish(hasRole, nil)
            end

            if statusCode == 404 then
                return finish(false, nil)
            end

            if statusCode == 429 and attempts < MAX_ATTEMPTS then
                local retryAfter = tonumber(responseHeaders and (responseHeaders["retry-after"] or responseHeaders["Retry-After"]))
                local delay = retryAfter and math.max(100, math.min(10000, retryAfter * 1000)) or (RETRY_DELAY * attempts)
                return SetTimeout(delay, attempt)
            end

            if (statusCode >= 500 or statusCode == 0) and attempts < MAX_ATTEMPTS then
                return SetTimeout(RETRY_DELAY * attempts, attempt)
            end

            finish(false, "discord_api_error:" .. tostring(statusCode))
        end, "GET", "", headers)
    end

    attempt()
end

---@description Sends a log message to the Discord webhook with cooldown.
---@param message string Log message
---@param color number Discord embed color
---@param translations table Locale strings
---@return boolean sent
function Discord.SendLog(message, color, translations)
    local webhook = State.config.discordWebhook
    if type(webhook) ~= "string" or webhook == "" or webhook == "***CONFIGURED***" then return false end

    local now = GetGameTimer()
    if now < webhookCooldownUntil then return false end
    webhookCooldownUntil = now + 5000

    local payload = json.encode({ embeds = {{
        title = Util.Translate(translations, "discord_title"),
        description = tostring(message or ""):sub(1, 1800),
        color = color or Enum.DiscordEmbedColor.PRIMARY,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
    }}})

    PerformHttpRequest(webhook, function() end, "POST", payload, {
        ["Content-Type"] = "application/json"
    })
    return true
end

function Discord.Sweep()
    local now = os.time()
    for id, entry in pairs(cache) do
        if entry.expires <= now then cache[id] = nil end
    end
end

---@description Returns the HTTP timeout duration in milliseconds.
---@return number timeoutMs
function Discord.DeferralTimeout()
    return TIMEOUT
end

---@description Returns whether Discord should fail open on errors.
---@return boolean failOpen
function Discord.FailOpen()
    return false
end

return Discord
