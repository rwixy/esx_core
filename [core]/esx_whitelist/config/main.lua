---@class WhitelistConfig
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
        endTime = "08:00",
        action = "enable"
    }
}
