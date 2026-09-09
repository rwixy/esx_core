---@class WhitelistClientUtil
local Util = {}

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

Util.LoadLocale = loadLocale
Util.Translate = translate

return Util
