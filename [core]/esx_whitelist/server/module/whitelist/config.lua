local Class <const> = xLib.require "@esx_whitelist.server.module.whitelist.Class"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Validation <const> = xLib.require "@esx_whitelist.server.module.whitelist.validation"

local ConfigService = {}
local PATH = "whitelist_config.json"

local function cloneRules(rules)
    local result = {}
    for i = 1, #(rules or {}) do
        local rule = {}
        for key, value in pairs(rules[i]) do rule[key] = value end
        result[#result + 1] = rule
    end
    return result
end

local function defaults()
    return {
        enabled = false,
        gracePeriod = 60,
        kickConnected = false,
        discordWebhook = "",
        discordEnabled = false,
        discordGuildId = "",
        discordRoleId = "",
        rules = cloneRules(Config.DefaultRules)
    }
end

function ConfigService.RebuildRules()
    State.compiledRules = {}
    for i = 1, #State.config.rules do
        if State.config.rules[i].enabled then
            State.compiledRules[#State.compiledRules + 1] = Class.WhitelistRule.new(State.config.rules[i])
        end
    end
    table.sort(State.compiledRules, function(a, b) return a.priority < b.priority end)
end

function ConfigService.Load()
    State.translations = Util.LoadLocale(Config.Locale)
    local raw = LoadResourceFile(GetCurrentResourceName(), PATH)
    if not raw then
        State.config = defaults()
        ConfigService.RebuildRules()
        return ConfigService.Save()
    end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= "table" then
        State.config = defaults()
        ConfigService.RebuildRules()
        return ConfigService.Save()
    end

    local normalized, err = Validation.Config(parsed, defaults())
    if not normalized then
        print(("^3[esx_whitelist]^0 Invalid saved config (%s); using safe defaults"):format(err or "unknown error"))
        State.config = defaults()
    else
        State.config = normalized
    end
    ConfigService.RebuildRules()
end

function ConfigService.Save()
    local payload = {
        whitelistEnabled = State.config.enabled,
        gracePeriod = State.config.gracePeriod,
        kickConnected = State.config.kickConnected,
        discordWebhook = State.config.discordWebhook,
        discordEnabled = State.config.discordEnabled,
        discordGuildId = State.config.discordGuildId,
        discordRoleId = State.config.discordRoleId,
        rules = State.config.rules
    }
    SaveResourceFile(GetCurrentResourceName(), PATH, json.encode(payload, { indent = true }), -1)
end

function ConfigService.Apply(data)
    local normalized, err = Validation.Config(data, State.config)
    if not normalized then return false, err end
    local oldEnabled = State.config.enabled
    local oldRules = json.encode(State.config.rules)
    State.config.enabled = normalized.whitelistEnabled
    State.config.gracePeriod = normalized.gracePeriod
    State.config.kickConnected = normalized.kickConnected
    State.config.discordWebhook = normalized.discordWebhook
    State.config.discordEnabled = normalized.discordEnabled
    State.config.discordGuildId = normalized.discordGuildId
    State.config.discordRoleId = normalized.discordRoleId
    State.config.rules = normalized.rules
    ConfigService.RebuildRules()
    State.manualOverride = json.encode(State.config.rules) == oldRules
    ConfigService.Save()
    return true, nil, oldEnabled
end

return ConfigService
