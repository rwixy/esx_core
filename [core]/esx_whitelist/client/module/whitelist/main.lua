local Class <const> = xLib.require "@esx_whitelist.client.module.whitelist.Class"
local Util <const> = xLib.require "@esx_whitelist.client.module.whitelist.util"

local Service = {}
local ui = Class.WhitelistUI.new()
local theme = {
    primaryColor = GetConvar("esx:ui:primaryColor", "#FB9B04"),
    secondaryColor = GetConvar("esx:ui:secondaryColor", "#252525"),
    backgroundColor = GetConvar("esx:ui:backgroundColor", "#161616"),
    accentColor = GetConvar("esx:ui:accentColor", "#FB9B04"),
    logoUrl = GetConvar("esx:ui:logoUrl", "")
}

local function openUI()
    if ui.isVisible then return end
    ESX.TriggerServerCallback("esx_whitelist:getConfig", function(config)
        if not config then
            ESX.ShowNotification("~r~" .. Util.Translate(ui.translations, "no_permission"))
            return
        end
        config.theme = theme
        ui:toggle(true, config)
    end)
end

local function registerEvents()
    RegisterNetEvent("esx_whitelist:startGracePeriod", function(seconds) ui:startGracePeriod(seconds) end)
    RegisterNetEvent("esx_whitelist:cancelGracePeriod", function() ui:cancelGracePeriod() end)
    RegisterNetEvent("esx_whitelist:stateChanged", function() end)
end

local function registerNui()
    RegisterNUICallback("closeUI", function(_, cb) ui:toggle(false); cb("ok") end)
    RegisterNUICallback("getConfig", function(_, cb)
        ESX.TriggerServerCallback("esx_whitelist:getConfig", function(config)
            if config then config.theme = theme end
            cb(config or {})
        end)
    end)
    RegisterNUICallback("updateConfig", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:updateConfig", function(success) cb(success == true) end, type(data) == "table" and data or {})
    end)
    RegisterNUICallback("testWebhook", function(_, cb)
        ESX.TriggerServerCallback("esx_whitelist:testWebhook", function(success)
            if success then ESX.ShowNotification("~g~" .. Util.Translate(ui.translations, "webhook_sent")) end
            cb(success == true)
        end)
    end)
    RegisterNUICallback("getWhitelistEntries", function(data, cb)
        data = type(data) == "table" and data or {}
        ESX.TriggerServerCallback("esx_whitelist:getWhitelistEntries", function(result) cb(result or { entries = {}, page = 1, limit = 50, total = 0, totalPages = 0 }) end, {
            page = tonumber(data.page) or 1,
            limit = tonumber(data.limit) or 50,
            search = type(data.search) == "string" and data.search or "",
            status = tonumber(data.status)
        })
    end)
    RegisterNUICallback("managePlayer", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:managePlayer", function(success, message) cb({ success = success == true, message = message }) end, type(data) == "table" and data or {})
    end)
    RegisterNUICallback("toggleWhitelistStatus", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:toggleWhitelistStatus", function(success) cb(success == true) end, type(data) == "table" and data or {})
    end)
end

function Service.Init()
    registerEvents()
    registerNui()
    RegisterCommand(Config.UICommand, openUI, false)
end

return Service
