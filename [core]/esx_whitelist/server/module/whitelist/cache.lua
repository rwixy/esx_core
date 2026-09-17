local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"

local Cache = {}

function Cache.SetWhitelist(identifier, id)
    if identifier and id then State.whitelistCache[identifier] = id end
end

function Cache.RemoveWhitelist(identifier)
    State.whitelistCache[identifier] = nil
end

function Cache.SetIdentifiers(source, identifiers)
    source = tonumber(source)
    if not source or source <= 0 then return identifiers or {} end
    Cache.ClearIdentifiers(source)
    State.playerIdentifiers[source] = identifiers
    for i = 1, #identifiers do
        State.onlineIdentifierSources[identifiers[i]] = source
    end
    return identifiers
end

function Cache.GetIdentifiers(source)
    source = tonumber(source)
    if not source or source <= 0 then return {} end
    return State.playerIdentifiers[source] or Cache.SetIdentifiers(source, Util.GetPlayerIdentifiersFiltered(source))
end

function Cache.ClearIdentifiers(source)
    source = tonumber(source)
    if not source then return end
    local identifiers = State.playerIdentifiers[source]
    if identifiers then
        for i = 1, #identifiers do
            if State.onlineIdentifierSources[identifiers[i]] == source then
                State.onlineIdentifierSources[identifiers[i]] = nil
            end
        end
    end
    State.playerIdentifiers[source] = nil
end

function Cache.FindOnline(identifier)
    return State.onlineIdentifierSources[identifier]
end

function Cache.ReplaceWhitelist(newCache)
    State.whitelistCache = newCache or {}
end

function Cache.IsWhitelisted(identifiers)
    for i = 1, #identifiers do
        if State.whitelistCache[identifiers[i]] then
            return true, State.whitelistCache[identifiers[i]]
        end
    end
    return false, nil
end

return Cache
