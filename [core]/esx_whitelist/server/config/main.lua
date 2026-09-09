---@class WhitelistServerConfig
---@field DiscordBotToken string
local ServerConfig = {}

---Discord Bot Token used exclusively for server-side role verification
---Can be configured here or passed via server convar: set discord:botToken "your_token"
ServerConfig.DiscordBotToken = GetConvar("discord:botToken", "YOUR_DISCORD_BOT_TOKEN_HERE")

return ServerConfig
