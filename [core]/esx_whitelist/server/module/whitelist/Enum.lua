---@class WhitelistEnums
local Enum = {}

---@enum IdentifierType
Enum.IdentifierType = {
    STEAM = "steam",
    LICENSE = "license",
    LICENSE2 = "license2",
    DISCORD = "discord",
    XBL = "xbl",
    FIVEM = "fivem"
}

---@enum RuleType
Enum.RuleType = {
    ADMIN_PRESENCE = "admin-presence",
    PLAYER_COUNT = "player-count",
    SCHEDULED = "scheduled"
}

---@enum RuleOperator
Enum.RuleOperator = {
    LESS_THAN = "<",
    GREATER_THAN = ">",
    LESS_OR_EQUAL = "<=",
    GREATER_OR_EQUAL = ">=",
    EQUALS = "=="
}

---@enum RuleAction
Enum.RuleAction = {
    ENABLE = "enable",
    DISABLE = "disable"
}

---@enum DiscordEmbedColor
Enum.DiscordEmbedColor = {
    SUCCESS = 3066993,
    DANGER = 15158332,
    PRIMARY = 3447003,
    WARNING = 16489220
}

return Enum
