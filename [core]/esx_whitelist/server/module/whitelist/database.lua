-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"

---@class Database
---@description Provides database operations for whitelist entries and identifiers including CRUD, search, and cache refresh.
local Database = {}
local noop = function() end

local CREATE_WHITELIST <const> = [[
CREATE TABLE IF NOT EXISTS `whitelist` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `player_name` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
    `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
    `added_by` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_whitelisted_id` (`whitelisted`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local CREATE_IDENTIFIERS <const> = [[
CREATE TABLE IF NOT EXISTS `whitelist_identifiers` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `whitelist_id` INT UNSIGNED NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `identifier` VARCHAR(255) NOT NULL COLLATE utf8mb4_bin,
    FOREIGN KEY (`whitelist_id`) REFERENCES `whitelist`(`id`) ON DELETE CASCADE,
    UNIQUE KEY `unique_identifier` (`identifier`),
    INDEX `idx_whitelist_id` (`whitelist_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local function validIdentifiers(identifiers)
    local result, seen = {}, {}
    for i = 1, #(identifiers or {}) do
        local identifier = type(identifiers[i]) == "string" and identifiers[i]:lower() or nil
        if identifier and identifier ~= "" and not seen[identifier] then
            local idType = identifier:match("^(%w+):")
            if idType then
                seen[identifier] = true
                result[#result + 1] = { identifier = identifier, type = idType }
            end
        end
    end
    return result
end

local function rawIdentifiers(clean)
    local result = {}
    for i = 1, #clean do result[#result + 1] = clean[i].identifier end
    return result
end

local function identifierInsertQueries(id, clean)
    local queries = {}
    for i = 1, #clean do
        queries[#queries + 1] = {
            query = "INSERT INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
            values = { id, clean[i].type, clean[i].identifier }
        }
    end
    return queries
end

local function normalizeWhitelisted(value)
    if value == true or tostring(value):lower() == "true" then return 1 end
    return tonumber(value) == 1 and 1 or 0
end

---@description Initializes database tables if they do not exist.
---@param cb fun(success: boolean)
function Database.Init(cb)
    cb = cb or noop
    MySQL.query(CREATE_WHITELIST, {}, function(result1)
        if result1 == false then
            if Config.Debug then
                print("^1[esx_whitelist] Failed to create/check whitelist table.^7")
            end
            return cb(false)
        end

        MySQL.query(CREATE_IDENTIFIERS, {}, function(result2)
            if result2 == false then
                if Config.Debug then
                    print("^1[esx_whitelist] Failed to create/check whitelist_identifiers table.^7")
                end
                return cb(false)
            end
            cb(true)
        end)
    end)
end

---@description Refreshes the in-memory whitelist cache from the database.
---@param cb fun(success: boolean)
function Database.RefreshCache(cb)
    cb = cb or noop
    local generation = Cache.BeginWhitelistRefresh()
    MySQL.query([[SELECT w.id, wi.identifier
        FROM whitelist w
        INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id
        WHERE w.whitelisted = 1]], {}, function(rows)
        if rows == false then return cb(false) end

        local cache = {}
        for i = 1, #(rows or {}) do
            local id = tonumber(rows[i].id)
            local identifier = rows[i].identifier
            if id and type(identifier) == "string" then cache[identifier] = id end
        end
        Cache.ReplaceWhitelist(cache, generation)
        cb(true)
    end)
end

---@description Finds a whitelist entry by a single identifier.
---@param identifier string The identifier to search for
---@param cb fun(row: table?)
function Database.FindByIdentifier(identifier, cb)
    cb = cb or noop
    if type(identifier) ~= "string" or identifier == "" then return cb(nil) end
    identifier = identifier:lower()

    MySQL.query([[SELECT w.id, w.player_name, w.whitelisted
        FROM whitelist w
        INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id
        WHERE wi.identifier = ? LIMIT 1]], { identifier }, function(rows)
        cb(rows ~= false and rows[1] or nil)
    end)
end

---@description Finds a whitelist entry by multiple identifiers.
---@param identifiers string[] List of identifiers
---@param cb fun(row: table?)
function Database.FindByIdentifiers(identifiers, cb)
    cb = cb or noop
    local clean = validIdentifiers(identifiers)
    if #clean == 0 then return cb(nil) end

    local placeholders, params = {}, {}
    for i = 1, #clean do
        placeholders[#placeholders + 1] = "?"
        params[#params + 1] = clean[i].identifier
    end

    MySQL.query(([[SELECT w.id, w.player_name, w.whitelisted
        FROM whitelist w
        INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id
        WHERE wi.identifier IN (%s)
        ORDER BY w.id ASC LIMIT 1]]):format(table.concat(placeholders, ",")), params, function(rows)
        cb(rows ~= false and rows[1] or nil)
    end)
end

---@description Finds conflicting identifiers assigned to other whitelist entries.
---@param whitelistId number The whitelist entry ID
---@param identifiers string[] Identifiers to check
---@param cb fun(conflicts: table[])
function Database.FindConflicts(whitelistId, identifiers, cb)
    cb = cb or noop
    local clean = validIdentifiers(identifiers)
    if #clean == 0 then return cb({}) end

    local whitelistId = tonumber(whitelistId)
    if not whitelistId then return cb({}) end
    local placeholders, params = {}, {}
    for i = 1, #clean do
        placeholders[#placeholders + 1] = "?"
        params[#params + 1] = clean[i].identifier
    end
    params[#params + 1] = whitelistId

    MySQL.query(([[SELECT wi.identifier, wi.whitelist_id
        FROM whitelist_identifiers wi
        WHERE wi.identifier IN (%s) AND wi.whitelist_id <> ?]]):format(table.concat(placeholders, ",")),
        params, function(rows)
            cb(rows ~= false and rows or {})
        end)
end

---@description Gets all identifiers for a whitelist entry.
---@param whitelistId number The whitelist entry ID
---@param cb fun(rows: table[])
function Database.GetIdentifiers(whitelistId, cb)
    cb = cb or noop
    whitelistId = tonumber(whitelistId)
    if not whitelistId then return cb({}) end

    MySQL.query("SELECT identifier FROM whitelist_identifiers WHERE whitelist_id = ? ORDER BY id ASC", { whitelistId }, function(rows)
        cb(rows ~= false and rows or {})
    end)
end

---@description Gets a flat list of identifier strings for a whitelist entry.
---@param whitelistId number The whitelist entry ID
---@param cb fun(identifiers: string[])
function Database.GetIdentifierList(whitelistId, cb)
    cb = cb or noop
    Database.GetIdentifiers(whitelistId, function(rows)
        local identifiers = {}
        for i = 1, #(rows or {}) do identifiers[#identifiers + 1] = rows[i].identifier end
        cb(identifiers)
    end)
end

---@description Inserts a new player with identifiers into the database.
---@param playerName string Player display name
---@param identifiers string[] Player identifiers
---@param whitelisted boolean Initial whitelist status
---@param addedBy string Who added the player
---@param cb fun(id: number?, error?: string)
function Database.InsertPlayer(playerName, identifiers, whitelisted, addedBy, cb)
    cb = cb or noop
    local clean = validIdentifiers(identifiers)
    if #clean == 0 then return cb(nil, "no_identifiers") end

    local identifiersOnly = rawIdentifiers(clean)
    Database.FindByIdentifiers(identifiersOnly, function(existing)
        if existing then return cb(nil, "identifier_already_exists", existing) end

        MySQL.insert("INSERT INTO whitelist (player_name, whitelisted, added_by) VALUES (?, ?, ?)", {
            tostring(playerName or "Unknown"):sub(1, 255),
            whitelisted and 1 or 0,
            tostring(addedBy or "Unknown"):sub(1, 255)
        }, function(id)
            id = tonumber(id)
            if not id then return cb(nil, "insert_failed") end

            MySQL.transaction(identifierInsertQueries(id, clean), function(success)
                if not success then
                    MySQL.update("DELETE FROM whitelist WHERE id = ?", { id })
                    return cb(nil, "identifier_insert_failed")
                end
                cb(id)
            end)
        end)
    end)
end

---@description Updates whitelist status for an entry.
---@param id number The whitelist entry ID
---@param status number 0 or 1
---@param addedBy string Optional who made the change
---@param cb fun(affected: number)
function Database.SetStatus(id, status, addedBy, cb)
    cb = cb or noop
    id = tonumber(id)
    status = tonumber(status)
    if not id or (status ~= 0 and status ~= 1) then return cb(0) end

    local query, params
    if addedBy then
        query = "UPDATE whitelist SET whitelisted = ?, added_by = ? WHERE id = ?"
        params = { status, tostring(addedBy):sub(1, 255), id }
    else
        query = "UPDATE whitelist SET whitelisted = ? WHERE id = ?"
        params = { status, id }
    end
    MySQL.update(query, params, cb)
end

---@description Ensures a player is whitelisted, inserting if needed and adding missing identifiers.
---@param playerName string Player display name
---@param identifiers string[] Player identifiers
---@param addedBy string Who added the player
---@param cb fun(success: boolean, error?: string, whitelistId?: number)
---@param retryCount number Internal retry counter
function Database.EnsureWhitelisted(playerName, identifiers, addedBy, cb, retryCount)
    cb = cb or noop
    retryCount = type(retryCount) == "number" and retryCount or 0
    local clean = validIdentifiers(identifiers)
    if #clean == 0 then return cb(false, "no_identifiers") end

    local identifiersOnly = rawIdentifiers(clean)
    local cacheIdentifiers = identifiersOnly
    local existing
    local function cacheAndFinish(id)
        Cache.SetWhitelistBatch(cacheIdentifiers, id)
        cb(true, nil, id)
    end

    local function enable(id)
        if tonumber(existing and existing.whitelisted) == 1 then return cacheAndFinish(id) end

        MySQL.update("UPDATE whitelist SET whitelisted = 1, added_by = ? WHERE id = ?", {
            tostring(addedBy or "system:admin"):sub(1, 255),
            id
        }, function(affected)
            if affected and tonumber(affected) > 0 then return cacheAndFinish(id) end

            MySQL.query("SELECT whitelisted FROM whitelist WHERE id = ? LIMIT 1", { id }, function(rows)
                local enabled = rows ~= false and rows[1] and tonumber(rows[1].whitelisted) == 1
                if not enabled then return cb(false, "verify_failed", id) end
                cacheAndFinish(id)
            end)
        end)
    end

    Database.FindByIdentifiers(identifiersOnly, function(existingRow)
        existing = existingRow
        if not existing then
            return Database.InsertPlayer(playerName, identifiersOnly, true, addedBy, function(id, err)
                if id then return cacheAndFinish(id) end
                if err == "identifier_already_exists" and retryCount < 2 then
                    return Database.EnsureWhitelisted(playerName, identifiersOnly, addedBy, cb, retryCount + 1)
                end
                cb(false, err or "insert_failed")
            end)
        end

        local id = tonumber(existing.id)
        if not id then return cb(false, "invalid_id") end

        Database.GetIdentifiers(id, function(rows)
            local known, knownIdentifiers, missing = {}, {}, {}
            for i = 1, #(rows or {}) do
                local identifier = rows[i].identifier
                if type(identifier) == "string" then
                    known[identifier] = true
                    knownIdentifiers[#knownIdentifiers + 1] = identifier
                end
            end
            for i = 1, #identifiersOnly do
                if not known[identifiersOnly[i]] then missing[#missing + 1] = identifiersOnly[i] end
            end

            if #missing == 0 then return enable(id) end

            Database.FindConflicts(id, missing, function(conflicts)
                local conflicting = {}
                for i = 1, #(conflicts or {}) do conflicting[conflicts[i].identifier] = true end
                local safe = {}
                for i = 1, #missing do
                    if not conflicting[missing[i]] then safe[#safe + 1] = missing[i] end
                end

                Database.AddIdentifiers(id, safe, function(success)
                    cacheIdentifiers = knownIdentifiers
                    if success then
                        for i = 1, #safe do
                            knownIdentifiers[#knownIdentifiers + 1] = safe[i]
                        end
                    end
                    enable(id)
                end)
            end)
        end)
    end)
end

---@description Adds identifiers to an existing whitelist entry.
---@param id number The whitelist entry ID
---@param identifiers string[] Identifiers to add
---@param cb fun(success: boolean, error?: string)
function Database.AddIdentifiers(id, identifiers, cb)
    cb = cb or noop
    id = tonumber(id)
    if not id then return cb(false, "invalid_id") end

    local clean = validIdentifiers(identifiers)
    if #clean == 0 then return cb(true) end

    Database.GetIdentifiers(id, function(rows)
        local known = {}
        for i = 1, #(rows or {}) do known[rows[i].identifier] = true end
        local missing = {}
        for i = 1, #clean do
            if not known[clean[i].identifier] then missing[#missing + 1] = clean[i] end
        end
        if #missing == 0 then return cb(true) end

        Database.FindConflicts(id, missing, function(conflicts)
            if #(conflicts or {}) > 0 then return cb(false, "identifier_already_exists", conflicts) end

            MySQL.transaction(identifierInsertQueries(id, missing), function(success)
                cb(success == true)
            end)
        end)
    end)
end

---@description Searches whitelist entries with pagination and filtering.
---@param request table Search parameters
---@param cb fun(result: {entries: table[], page: number, limit: number, total: number, totalPages: number})
function Database.Search(request, cb)
    cb = cb or noop
    request = type(request) == "table" and request or {}
    local page = math.max(1, math.min(100000, math.floor(tonumber(request.page) or 1)))
    local limit = math.min(100, math.max(10, math.floor(tonumber(request.limit) or 50)))
    local search = type(request.search) == "string" and request.search:sub(1, 100) or ""
    local status = tonumber(request.status)
    local where, params = {}, {}

    if search ~= "" then
        where[#where + 1] = "(w.player_name LIKE ? OR wi.identifier LIKE ?)"
        local pattern = "%" .. search .. "%"
        params[#params + 1] = pattern
        params[#params + 1] = pattern
    end
    if status == 0 or status == 1 then
        where[#where + 1] = "w.whitelisted = ?"
        params[#params + 1] = status
    end

    local clause = #where > 0 and (" WHERE " .. table.concat(where, " AND ")) or ""
    MySQL.query(([[SELECT COUNT(DISTINCT w.id) AS total
        FROM whitelist w
        LEFT JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id%s]]):format(clause), params, function(countRows)
        if countRows == false then return cb({ entries = {}, page = page, limit = limit, total = 0, totalPages = 1 }) end

        local total = tonumber(countRows[1] and countRows[1].total) or 0
        local totalPages = math.max(1, math.ceil(total / limit))
        if page > totalPages then page = totalPages end
        local offset = (page - 1) * limit

        local pageParams = {}
        for i = 1, #params do pageParams[#pageParams + 1] = params[i] end
        pageParams[#pageParams + 1] = limit
        pageParams[#pageParams + 1] = offset

        MySQL.query(([[SELECT DISTINCT w.id, w.player_name, w.whitelisted
            FROM whitelist w
            LEFT JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id%s
            ORDER BY w.id DESC
            LIMIT ? OFFSET ?]]):format(clause), pageParams, function(rows)
            if rows == false then return cb({ entries = {}, page = page, limit = limit, total = total, totalPages = totalPages }) end
            if #rows == 0 then return cb({ entries = {}, page = page, limit = limit, total = total, totalPages = totalPages }) end

            local ids, entriesById = {}, {}
            for i = 1, #rows do
                local row = rows[i]
                local id = tonumber(row.id)
                if id then
                    ids[#ids + 1] = id
                    entriesById[id] = {
                        id = id,
                        playerName = row.player_name or "Unknown",
                        whitelisted = normalizeWhitelisted(row.whitelisted),
                        identifiers = {}
                    }
                end
            end

            local identifierParams = {}
            for i = 1, #ids do identifierParams[#identifierParams + 1] = ids[i] end
            MySQL.query(([[SELECT whitelist_id, identifier
                FROM whitelist_identifiers
                WHERE whitelist_id IN (%s)
                ORDER BY whitelist_id, id ASC]]):format(table.concat(identifierParams, ",")), identifierParams, function(identifierRows)
                local identifiersById = {}
                for i = 1, #(identifierRows or {}) do
                    local row = identifierRows[i]
                    local id = tonumber(row.whitelist_id)
                    if id and type(row.identifier) == "string" then
                        if not identifiersById[id] then identifiersById[id] = {} end
                        identifiersById[id][#identifiersById[id] + 1] = row.identifier
                    end
                end

                local entries = {}
                for i = 1, #ids do
                    local entry = entriesById[ids[i]]
                    if entry then
                        entry.identifiers = identifiersById[ids[i]] or {}
                        entries[#entries + 1] = entry
                    end
                end
                cb({ entries = entries, page = page, limit = limit, total = total, totalPages = totalPages })
            end)
        end)
    end)
end

---@description Checks if identifiers belong to any admin user.
---@param identifiers string[] Player identifiers
---@param adminGroups table Admin group names
---@param cb fun(isAdmin: boolean)
function Database.FindAdminByIdentifiers(identifiers, adminGroups, cb)
    cb = cb or noop
    local clean = validIdentifiers(identifiers)
    if #clean == 0 or #clean > 32 then return cb(false) end

    local placeholders, params = {}, {}
    for i = 1, #clean do
        placeholders[#placeholders + 1] = "?"
        params[#params + 1] = clean[i].identifier
    end

    local groups, seenGroups = {}, {}
    for group in pairs(adminGroups or {}) do
        group = string.lower(tostring(group))
        if not seenGroups[group] then
            seenGroups[group] = true
            groups[#groups + 1] = group
        end
    end
    if #groups == 0 then return cb(false) end

    local groupPlaceholders = {}
    for i = 1, #groups do
        groupPlaceholders[#groupPlaceholders + 1] = "?"
        params[#params + 1] = groups[i]
    end

    local query = ([[SELECT 1 AS is_admin FROM users WHERE identifier IN (%s) AND LOWER(`group`) IN (%s) LIMIT 1]]):format(
        table.concat(placeholders, ","),
        table.concat(groupPlaceholders, ",")
    )
    MySQL.query(query, params, function(rows) cb(rows ~= false and rows[1] ~= nil) end)
end

return Database
