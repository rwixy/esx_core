local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

local Validation = {}

local RULE_TYPES = {
    [Enum.RuleType.ADMIN_PRESENCE] = true,
    [Enum.RuleType.PLAYER_COUNT] = true,
    [Enum.RuleType.SCHEDULED] = true
}
local OPERATORS = { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true, ["=="] = true }
local ACTIONS = { enable = true, disable = true }

local function trim(value, max)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if max and #value > max then value = value:sub(1, max) end
    return value
end

function Validation.Webhook(url)
    if url == "" then return true end
    return type(url) == "string" and (
        url:match("^https://discord%.com/api/webhooks/%d+/.+$") ~= nil or
        url:match("^https://discordapp%.com/api/webhooks/%d+/.+$") ~= nil
    )
end

function Validation.Identifier(raw)
    local idType, value = Util.NormalizeIdentifier(raw)
    if not idType or not value then return nil end
    return idType .. ":" .. value, idType, value
end

function Validation.Rule(rule, index)
    if type(rule) ~= "table" then return nil, "rule " .. index .. " is invalid" end
    if not RULE_TYPES[rule.type] then return nil, "rule " .. index .. " has an invalid type" end
    if rule.operator ~= nil and not OPERATORS[rule.operator] then return nil, "rule " .. index .. " has an invalid operator" end
    if rule.action ~= nil and not ACTIONS[rule.action] then return nil, "rule " .. index .. " has an invalid action" end

    local normalized = {
        id = trim(tostring(rule.id or index), 64),
        type = rule.type,
        enabled = rule.enabled == true,
        priority = math.max(0, math.min(100000, math.floor(tonumber(rule.priority) or index))),
        operator = rule.operator,
        value = tonumber(rule.value),
        action = rule.action,
        startTime = trim(rule.startTime or "00:00", 5),
        endTime = trim(rule.endTime or "23:59", 5)
    }

    if normalized.type ~= Enum.RuleType.SCHEDULED then
        normalized.operator = normalized.operator or "<"
        normalized.value = normalized.value or 0
        normalized.action = normalized.action or "enable"
    else
        normalized.action = normalized.action or "enable"
        local function validTime(value)
            local hour, minute = value:match("^(%d%d?):(%d%d?)$")
            hour, minute = tonumber(hour), tonumber(minute)
            return hour ~= nil and minute ~= nil and hour <= 23 and minute <= 59
        end
        if not validTime(normalized.startTime) or not validTime(normalized.endTime) then
            return nil, "rule " .. index .. " has an invalid schedule"
        end
    end

    return normalized
end

function Validation.Rules(rules)
    if type(rules) ~= "table" or #rules > 50 then return nil, "invalid rules" end
    local output = {}
    for i = 1, #rules do
        local rule, err = Validation.Rule(rules[i], i)
        if not rule then return nil, err end
        output[#output + 1] = rule
    end
    return output
end

function Validation.Config(data, current)
    if type(data) ~= "table" then return nil, "invalid config" end

    local out = {}
    out.whitelistEnabled = data.whitelistEnabled == true
    out.gracePeriod = math.max(0, math.min(600, math.floor(tonumber(data.gracePeriod) or current.gracePeriod or 60)))
    out.kickConnected = data.kickConnected == true
    out.discordEnabled = data.discordEnabled == true
    out.discordGuildId = trim(data.discordGuildId or "", 64)
    out.discordRoleId = trim(data.discordRoleId or "", 64)

    local webhook = trim(data.discordWebhook or "", 250)
    if webhook == "***CONFIGURED***" then webhook = current.discordWebhook end
    if not Validation.Webhook(webhook) then return nil, "Invalid Discord webhook URL" end
    out.discordWebhook = webhook

    local rules, err = Validation.Rules(data.rules or current.rules)
    if not rules then return nil, err end
    out.rules = rules

    if out.discordEnabled and (out.discordGuildId == "" or out.discordRoleId == "") then
        return nil, "Discord configuration incomplete"
    end

    return out
end

return Validation
