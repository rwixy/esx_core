local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"

local Auth = {}
local adminGroups = {}

for i = 1, #Config.AdminGroups do
    adminGroups[Config.AdminGroups[i]] = true
end

function Auth.IsAdmin(source)
    local id = tonumber(source)
    if not id or id <= 0 then return true end
    if State.adminSources[id] ~= nil then return State.adminSources[id] end

    local xPlayer = ESX.GetPlayerFromId(id)
    if not xPlayer then return false end
    local group = xPlayer.getGroup()
    local result = adminGroups[group] == true
    State.adminSources[id] = result
    return result
end

function Auth.SetAdmin(source, value)
    source = tonumber(source)
    if not source or source <= 0 then return end
    State.adminSources[source] = value == true
end

function Auth.Clear(source)
    source = tonumber(source)
    if source then State.adminSources[source] = nil end
end

function Auth.Groups()
    return Config.AdminGroups
end

return Auth
