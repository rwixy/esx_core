local State = {}

State.config = {
    enabled = false,
    gracePeriod = 60,
    kickConnected = false,
    discordWebhook = "",
    discordEnabled = false,
    discordGuildId = "",
    discordRoleId = "",
    rules = {}
}

State.translations = {}
State.compiledRules = {}
State.playerIdentifiers = {}
State.onlineIdentifierSources = {}
State.whitelistCache = {}
State.gracePlayers = {}
State.adminSources = {}
State.onlineSources = {}

State.onlinePlayerCount = 0
State.onlineAdminCount = 0
State.manualOverride = false
State.ruleEvaluationPending = false

return State
