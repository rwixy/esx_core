---@class WhitelistServerConfig
---@field DiscordBotToken string
local ServerConfig = {}

-- Prefer the server convar. Never put a real token in a resource file.
ServerConfig.DiscordBotToken = GetConvar("discord:botToken", "")

return ServerConfig
