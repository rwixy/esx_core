local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local ConfigService <const> = xLib.require "@esx_whitelist.server.module.whitelist.config"

local Rules = {}

function Rules.Evaluate()
    local currentMinutes = (tonumber(os.date("%H")) or 0) * 60 + (tonumber(os.date("%M")) or 0)
    for i = 1, #State.compiledRules do
        local applicable, desired = State.compiledRules[i]:evaluate(State.onlinePlayerCount, State.onlineAdminCount, currentMinutes)
        if applicable and desired ~= nil then return desired end
    end
    return State.config.enabled
end

function Rules.EvaluateAndApply(onChanged)
    if State.manualOverride or State.ruleEvaluationPending then return false end
    State.ruleEvaluationPending = true
    local newState = Rules.Evaluate()
    local changed = newState ~= State.config.enabled
    if changed then
        State.config.enabled = newState
        ConfigService.Save()
        if onChanged then onChanged(newState) end
    end
    SetTimeout(5000, function() State.ruleEvaluationPending = false end)
    return changed
end

return Rules
