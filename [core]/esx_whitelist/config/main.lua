---@class WhitelistRuleConfig
---@field id string
---@field type "admin-presence" | "player-count" | "scheduled"
---@field enabled boolean
---@field priority number
---@field operator string?
---@field value number?
---@field action string?
---@field startTime string?
---@field endTime string?

---@class WhitelistConfig
---@field Locale string
---@field Debug boolean
---@field UICommand string
---@field AdminGroups string[]
---@field ConsoleCommands boolean
---@field InGameCommands boolean
---@field DefaultRules WhitelistRuleConfig[]
Config = {}

Config.Locale = "en"
Config.Debug = false
Config.UICommand = "whitelist"

Config.AdminGroups = {
    "admin",
    "mod"
}

Config.ConsoleCommands = true
Config.InGameCommands = true

Config.DefaultRules = {
    {
        id = "1",
        type = "admin-presence",
        enabled = false,
        priority = 1,
        operator = "<",
        value = 1,
        action = "enable"
    },
    {
        id = "2",
        type = "player-count",
        enabled = false,
        priority = 2,
        operator = ">",
        value = 32,
        action = "enable"
    },
    {
        id = "3",
        type = "scheduled",
        enabled = false,
        priority = 3,
        startTime = "03:00",
        endTime = "08:00"
    }
}
