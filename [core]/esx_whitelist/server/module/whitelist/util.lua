local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"

---@class WhitelistServerUtil
local Util = {}

---@type table<string, boolean>
local INVALID_TOKENS <const> = {
    ["TU_TOKEN_AQUI"] = true,
    ["YOUR_TOKEN_HERE"] = true,
    ["YOUR_BOT_TOKEN"] = true,
    ["DISCORD_BOT_TOKEN"] = true,
    ["YOUR_DISCORD_BOT_TOKEN_HERE"] = true
}

---Validates if a Discord bot token is well-formed and not a placeholder
---@param token string?
---@return boolean
local function isValidBotToken(token)
    if not token or token == "" or #token < 50 or not string.match(token, "%.") then
        return false
    end

    if INVALID_TOKENS[token] then
        return false
    end

    return true
end

---Detects the identifier type from raw string value
---@param value string?
---@return string?
local function detectIdentifierType(value)
    if not value or value == "" then
        return nil
    end

    local cleanValue = value:gsub("%s+", ""):gsub("^%w+:", "")
    local length = #cleanValue

    if cleanValue:find("^[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+$") and length == 36 then
        return Enum.IdentifierType.LICENSE2
    end

    if cleanValue:find("^[0-9a-fA-F]+$") and length == 40 then
        return Enum.IdentifierType.LICENSE
    end

    if cleanValue:find("^%d+$") then
        if length >= 17 and length <= 19 then
            return Enum.IdentifierType.DISCORD
        elseif length == 16 then
            return Enum.IdentifierType.XBL
        elseif length >= 6 and length <= 8 then
            return Enum.IdentifierType.FIVEM
        end
    end

    if cleanValue:find("^[0-9a-fA-F]+$") and length >= 15 and length <= 17 then
        return Enum.IdentifierType.STEAM
    end

    return nil
end

---Normalizes an identifier string into type and value
---@param rawValue string?
---@return string?, string?
local function normalizeIdentifier(rawValue)
    if not rawValue or rawValue == "" then
        return nil, nil
    end

    local cleanValue = rawValue:gsub("%s+", "")
    local providedPrefix, providedValue = cleanValue:match("^(%w+):(.+)$")
    local valueToDetect = providedValue or cleanValue
    local detectedType = detectIdentifierType(valueToDetect)

    if not detectedType then
        return nil, nil
    end

    return detectedType, valueToDetect
end

---Extracts all identifiers for a given player source
---@param playerId number|string
---@return string[]
local function getPlayerIdentifiersFiltered(playerId)
    local identifiers = {}
    local license = GetPlayerIdentifierByType(playerId, "license")
    local license2 = GetPlayerIdentifierByType(playerId, "license2")
    local steam = GetPlayerIdentifierByType(playerId, "steam")
    local discord = GetPlayerIdentifierByType(playerId, "discord")
    local xbl = GetPlayerIdentifierByType(playerId, "xbl")
    local fivem = GetPlayerIdentifierByType(playerId, "fivem")

    if license then
        identifiers[#identifiers + 1] = "license:" .. license
    end
    if license2 then
        identifiers[#identifiers + 1] = "license2:" .. license2
    end
    if steam then
        identifiers[#identifiers + 1] = "steam:" .. steam
    end
    if discord then
        identifiers[#identifiers + 1] = "discord:" .. discord
    end
    if xbl then
        identifiers[#identifiers + 1] = "xbl:" .. xbl
    end
    if fivem then
        identifiers[#identifiers + 1] = "fivem:" .. fivem
    end

    return identifiers
end

---Builds SQL WHERE clause for multiple identifiers
---@param identifiers string[]
---@return string, string[]
local function buildIdentifierQuery(identifiers)
    local conditions = {}
    local params = {}
    for i = 1, #identifiers do
        conditions[#conditions + 1] = "wi.identifier = ?"
        params[#params + 1] = identifiers[i]
    end
    return table.concat(conditions, " OR "), params
end

---Loads translation JSON for the configured locale
---@param localeName string
---@return table<string, string>
local function loadLocale(localeName)
    local rawJson = LoadResourceFile(GetCurrentResourceName(), ("locales/%s.json"):format(localeName))
    if not rawJson then
        rawJson = LoadResourceFile(GetCurrentResourceName(), "locales/en.json")
    end

    if not rawJson then
        return {}
    end

    local success, decoded = pcall(json.decode, rawJson)
    if success and type(decoded) == "table" then
        return decoded
    end

    return {}
end

---Translates a key with optional string formatting
---@param translations table<string, string>
---@param key string
---@param ... any
---@return string
local function translate(translations, key, ...)
    local template = translations[key] or key
    if not ... then
        return template
    end

    local success, result = pcall(string.format, template, ...)
    if success then
        return result
    end

    return template
end

Util.IsValidBotToken = isValidBotToken
Util.DetectIdentifierType = detectIdentifierType
Util.NormalizeIdentifier = normalizeIdentifier
Util.GetPlayerIdentifiersFiltered = getPlayerIdentifiersFiltered
Util.BuildIdentifierQuery = buildIdentifierQuery
Util.LoadLocale = loadLocale
Util.Translate = translate

return Util
