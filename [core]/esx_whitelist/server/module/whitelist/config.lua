-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local Class <const> = xLib.require "@esx_whitelist.server.module.whitelist.Class"
local State <const> = xLib.require "@esx_whitelist.server.module.whitelist.state"
local Util <const> = xLib.require "@esx_whitelist.server.module.whitelist.util"
local Validation <const> = xLib.require "@esx_whitelist.server.module.whitelist.validation"

---@class ConfigService
---@description Handles loading, saving, and validating the whitelist configuration from whitelist_config.json.
local ConfigService = {}
local PATH <const> = "whitelist_config.json"
local lastEncoded = nil
local saveInProgress = false

local function cloneRules(rules)
    local result = {}
    for i = 1, #(rules or {}) do
        local rule = {}
        for key, value in pairs(rules[i]) do rule[key] = value end
        result[#result + 1] = rule
    end
    return result
end

local function cloneConfig(config)
    local result = {}
    for key, value in pairs(config or {}) do
        result[key] = key == "rules" and cloneRules(value) or value
    end
    return result
end

local function defaults()
    return {
        enabled = false,
        gracePeriod = 60,
        kickConnected = false,
        discordWebhook = "",
        discordBotToken = "",
        discordEnabled = false,
        discordGuildId = "",
        discordRoleId = "",
        authorizationMethod = "identifier",
        rules = cloneRules(Config.DefaultRules)
    }
end

local function encodeConfig(config)
    local payload = {
        whitelistEnabled = config.enabled,
        gracePeriod = config.gracePeriod,
        kickConnected = config.kickConnected,
        discordWebhook = config.discordWebhook,
        discordEnabled = config.discordEnabled,
        discordGuildId = config.discordGuildId,
        discordRoleId = config.discordRoleId,
        authorizationMethod = config.authorizationMethod,
        rules = config.rules
    }

    local ok, encoded = pcall(json.encode, payload, { indent = true })
    if not ok then
        if Config.Debug then
            print("^1[esx_whitelist] Failed to encode whitelist configuration.^7")
        end
        return nil, "encode_failed"
    end
    return encoded
end

local function writeEncoded(encoded)
    if lastEncoded == encoded then return true end
    if saveInProgress then return false, "save_in_progress" end

    saveInProgress = true
    local resourceName = GetCurrentResourceName()
    local previous = LoadResourceFile(resourceName, PATH)
    local okTemp, tempResult = pcall(SaveResourceFile, resourceName, PATH .. ".tmp", encoded, #encoded)

    if okTemp and tempResult ~= false then
        local okFinal, finalResult = pcall(SaveResourceFile, resourceName, PATH, encoded, #encoded)
        if okFinal and finalResult ~= false then
            lastEncoded = encoded
            saveInProgress = false
            return true
        end

        if type(previous) == "string" then
            pcall(SaveResourceFile, resourceName, PATH, previous, #previous)
        end
        if Config.Debug then
            print("^1[esx_whitelist] Failed to save whitelist configuration.^7")
        end
        saveInProgress = false
        return false, "state_save_failed"
    end

    local okFinal, finalResult = pcall(SaveResourceFile, resourceName, PATH, encoded, #encoded)
    if okFinal and finalResult ~= false then
        lastEncoded = encoded
        saveInProgress = false
        return true
    end

    if type(previous) == "string" then
        pcall(SaveResourceFile, resourceName, PATH, previous, #previous)
    end
    if Config.Debug then
        print("^1[esx_whitelist] Failed to save whitelist configuration.^7")
    end
    saveInProgress = false
    return false, "state_save_failed"
end

local function adoptConfig(config, persist)
    local token = State.config.discordBotToken
    State.config = cloneConfig(config)
    State.config.discordBotToken = token or ""

    if not persist then
        local encoded = encodeConfig(State.config)
        lastEncoded = encoded
        ConfigService.RebuildRules()
        return encoded ~= nil
    end

    return ConfigService.CommitCandidate(State.config)
end

function ConfigService.RebuildRules()
    State.compiledRules = {}
    for i = 1, #(State.config.rules or {}) do
        if State.config.rules[i].enabled then
            State.compiledRules[#State.compiledRules + 1] = Class.WhitelistRule.new(State.config.rules[i])
        end
    end
    table.sort(State.compiledRules, function(a, b)
        if a.priority == b.priority then return a.id < b.id end
        return a.priority < b.priority
    end)
end

function ConfigService.CommitCandidate(candidate)
    local encoded, err = encodeConfig(candidate)
    if not encoded then return false, err end

    local ok, writeErr = writeEncoded(encoded)
    if not ok then return false, writeErr end

    State.config = cloneConfig(candidate)
    ConfigService.RebuildRules()
    return true
end

function ConfigService.Load()
    State.translations = Util.LoadLocale(Config.Locale)
    local fallback = defaults()
    local raw = LoadResourceFile(GetCurrentResourceName(), PATH)

    if not raw then
        if Config.Debug then
            print("^3[esx_whitelist] No saved configuration found at whitelist_config.json; writing safe defaults.^7")
        end
        adoptConfig(fallback, true)
        return
    end

    if Config.Debug then
        print("^3[esx_whitelist] Reading saved whitelist configuration.^7")
    end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= "table" then
        if Config.Debug then
            print("^1[esx_whitelist] Invalid whitelist_config.json; writing safe defaults.^7")
        end
        adoptConfig(fallback, true)
        return
    end

    local normalized, err = Validation.Config(parsed, fallback)
    if not normalized then
        if Config.Debug then
            print(("^1[esx_whitelist] Invalid saved config (%s); writing safe defaults.^7"):format(err or "unknown error"))
        end
        adoptConfig(fallback, true)
        return
    end

    if Config.Debug then
        print(("^3[esx_whitelist] Loaded saved configuration - enabled=%s - method=%s^7"):format(
        tostring(normalized.whitelistEnabled),
        tostring(normalized.authorizationMethod)
    ))
    end
    adoptConfig(normalized, false)
end

function ConfigService.Apply(data)
    local normalized, err = Validation.Config(data, State.config)
    if not normalized then return false, err end

    local oldEnabled = State.config.enabled
    local candidate = cloneConfig(State.config)
    candidate.enabled = normalized.whitelistEnabled
    candidate.gracePeriod = normalized.gracePeriod
    candidate.kickConnected = normalized.kickConnected
    candidate.discordWebhook = normalized.discordWebhook
    candidate.discordEnabled = normalized.discordEnabled
    candidate.discordGuildId = normalized.discordGuildId
    candidate.discordRoleId = normalized.discordRoleId
    candidate.authorizationMethod = normalized.authorizationMethod
    candidate.rules = normalized.rules

    local ok, saveErr = ConfigService.CommitCandidate(candidate)
    if not ok then return false, saveErr, oldEnabled end
    return true, nil, oldEnabled
end

function ConfigService.SetEnabled(enabled)
    local oldEnabled = State.config.enabled
    local candidate = cloneConfig(State.config)
    candidate.enabled = enabled == true

    local ok, saveErr = ConfigService.CommitCandidate(candidate)
    if not ok then return false, saveErr, oldEnabled end
    return true, nil, oldEnabled
end

return ConfigService
