local Cache <const> = xLib.require "@esx_whitelist.server.module.whitelist.cache"

local Database = {}

local CREATE_WHITELIST = [[
CREATE TABLE IF NOT EXISTS `whitelist` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `player_name` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
    `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
    `added_by` VARCHAR(255) COLLATE utf8mb4_unicode_ci,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_whitelisted_id` (`whitelisted`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local CREATE_IDENTIFIERS = [[
CREATE TABLE IF NOT EXISTS `whitelist_identifiers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `whitelist_id` INT NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `identifier` VARCHAR(255) NOT NULL COLLATE utf8mb4_bin,
    FOREIGN KEY (`whitelist_id`) REFERENCES `whitelist`(`id`) ON DELETE CASCADE,
    UNIQUE KEY `unique_identifier` (`type`, `identifier`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_whitelist_id` (`whitelist_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

function Database.Init(cb)
    MySQL.query(CREATE_WHITELIST, {}, function()
        MySQL.query(CREATE_IDENTIFIERS, {}, cb)
    end)
end

function Database.RefreshCache(cb)
    MySQL.query("SELECT w.id, wi.identifier FROM whitelist w INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id WHERE w.whitelisted = 1", {}, function(rows)
        local cache = {}
        for i = 1, #(rows or {}) do cache[rows[i].identifier] = rows[i].id end
        Cache.ReplaceWhitelist(cache)
        if cb then cb() end
    end)
end

function Database.FindByIdentifier(identifier, cb)
    MySQL.query([[SELECT w.id, w.player_name, w.whitelisted
        FROM whitelist w INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id
        WHERE wi.identifier = ? LIMIT 1]], { identifier }, function(rows)
        cb(rows and rows[1] or nil)
    end)
end

function Database.FindByIdentifiers(identifiers, cb)
    if #identifiers == 0 then return cb(nil) end
    local placeholders = {}
    for i = 1, #identifiers do placeholders[i] = "?" end
    MySQL.query(([[SELECT w.id, w.player_name, w.whitelisted
        FROM whitelist w INNER JOIN whitelist_identifiers wi ON wi.whitelist_id = w.id
        WHERE wi.identifier IN (%s)
        ORDER BY w.id ASC LIMIT 1]]):format(table.concat(placeholders, ",")), identifiers, function(rows)
        cb(rows and rows[1] or nil)
    end)
end

function Database.GetIdentifiers(whitelistId, cb)
    MySQL.query("SELECT identifier FROM whitelist_identifiers WHERE whitelist_id = ? ORDER BY id ASC", { whitelistId }, cb)
end

function Database.InsertPlayer(playerName, identifiers, whitelisted, addedBy, cb)
    if #identifiers == 0 then return cb(nil) end
    MySQL.insert("INSERT INTO whitelist (player_name, whitelisted, added_by) VALUES (?, ?, ?)", {
        playerName, whitelisted and 1 or 0, addedBy
    }, function(id)
        id = tonumber(id)
        if not id then return cb(nil) end

        local queries = {}
        for i = 1, #identifiers do
            local idType = identifiers[i]:match("^(%w+):")
            if idType then
                queries[#queries + 1] = {
                    query = "INSERT IGNORE INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                    values = { id, idType, identifiers[i] }
                }
            end
        end

        if #queries == 0 then return cb(id) end
        MySQL.transaction(queries, function(success)
            cb(success and id or nil)
        end)
    end)
end

function Database.SetStatus(id, status, addedBy, cb)
    local query, params
    if addedBy then
        query = "UPDATE whitelist SET whitelisted = ?, added_by = ? WHERE id = ?"
        params = { status, addedBy, id }
    else
        query = "UPDATE whitelist SET whitelisted = ? WHERE id = ?"
        params = { status, id }
    end
    MySQL.update(query, params, cb)
end

function Database.AddIdentifiers(id, identifiers, cb)
    local queries = {}
    for i = 1, #identifiers do
        local idType = identifiers[i]:match("^(%w+):")
        if idType then
            queries[#queries + 1] = {
                query = "INSERT IGNORE INTO whitelist_identifiers (whitelist_id, type, identifier) VALUES (?, ?, ?)",
                values = { id, idType, identifiers[i] }
            }
        end
    end
    if #queries == 0 then return cb(true) end
    MySQL.transaction(queries, cb)
end

function Database.Search(request, cb)
    local page = math.max(1, math.min(100000, math.floor(tonumber(request.page) or 1)))
    local limit = math.min(100, math.max(10, math.floor(tonumber(request.limit) or 50)))
    local search = type(request.search) == "string" and request.search:sub(1, 100) or ""
    local status = tonumber(request.status)
    local where, params = {}, {}

    if search ~= "" then
        where[#where + 1] = "(w.player_name LIKE ? OR EXISTS (SELECT 1 FROM whitelist_identifiers ws WHERE ws.whitelist_id = w.id AND ws.identifier LIKE ?))"
        local pattern = "%" .. search .. "%"
        params[#params + 1], params[#params + 1] = pattern, pattern
    end
    if status == 0 or status == 1 then
        where[#where + 1] = "w.whitelisted = ?"
        params[#params + 1] = status
    end

    local whereSql = #where > 0 and " WHERE " .. table.concat(where, " AND ") or ""
    MySQL.query("SELECT COUNT(*) AS total FROM whitelist w" .. whereSql, params, function(countRows)
        local total = tonumber(countRows and countRows[1] and countRows[1].total) or 0
        local totalPages = math.max(1, math.ceil(total / limit))
        page = math.min(page, totalPages)
        local offset = (page - 1) * limit
        local queryParams = {}
        for i = 1, #params do queryParams[i] = params[i] end
        queryParams[#queryParams + 1], queryParams[#queryParams + 1] = limit, offset

        MySQL.query(([[SELECT w.id, w.player_name, CAST(w.whitelisted AS UNSIGNED) AS whitelisted
            FROM whitelist w%s ORDER BY w.whitelisted DESC, w.id ASC LIMIT ? OFFSET ?]]):format(whereSql), queryParams, function(rows)
            rows = rows or {}
            if #rows == 0 then return cb({ entries = {}, page = page, limit = limit, total = total, totalPages = totalPages }) end

            local placeholders, ids = {}, {}
            for i = 1, #rows do placeholders[i], ids[i] = "?", rows[i].id end
            MySQL.query(("SELECT whitelist_id, identifier FROM whitelist_identifiers WHERE whitelist_id IN (%s) ORDER BY whitelist_id ASC, id ASC"):format(table.concat(placeholders, ",")), ids, function(idRows)
                local map = {}
                for i = 1, #(idRows or {}) do
                    local row = idRows[i]
                    map[row.whitelist_id] = map[row.whitelist_id] or {}
                    map[row.whitelist_id][#map[row.whitelist_id] + 1] = row.identifier
                end
                local entries = {}
                for i = 1, #rows do
                    local row = rows[i]
                    entries[i] = {
                        id = row.id,
                        identifiers = map[row.id] or {},
                        playerName = row.player_name or "Unknown",
                        whitelisted = tonumber(row.whitelisted) or 0
                    }
                end
                cb({ entries = entries, page = page, limit = limit, total = total, totalPages = totalPages })
            end)
        end)
    end)
end

return Database
