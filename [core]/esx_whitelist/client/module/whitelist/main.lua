local Class <const> = xLib.require "@esx_whitelist.client.module.whitelist.Class"
local Util <const> = xLib.require "@esx_whitelist.client.module.whitelist.util"

---@class WhitelistClientService
local WhitelistClient = {}

local uiController = Class.WhitelistUI.new()
local isWhitelistEnabled = false

---Retrieves configured theme convars for frontend customization
---@return table<string, string>
local function getThemeConvars()
    return {
        primaryColor = GetConvar("esx:ui:primaryColor", "#FB9B04"),
        secondaryColor = GetConvar("esx:ui:secondaryColor", "#252525"),
        backgroundColor = GetConvar("esx:ui:backgroundColor", "#161616"),
        accentColor = GetConvar("esx:ui:accentColor", "#FB9B04"),
        logoUrl = GetConvar("esx:ui:logoUrl", "")
    }
end

---Opens administrative whitelist control panel if player has permissions
local function openWhitelistUI()
    if uiController.isVisible then
        return
    end

    ESX.TriggerServerCallback("esx_whitelist:getConfig", function(serverConfig)
        if not serverConfig then
            ESX.ShowNotification("~r~" .. Util.Translate(uiController.translations, "no_permission"))
            return
        end

        serverConfig.theme = getThemeConvars()
        uiController:toggle(true, serverConfig)
    end)
end

---Registers client network events
local function registerNetworkEvents()
    RegisterNetEvent("esx_whitelist:stateChanged", function(enabled)
        isWhitelistEnabled = enabled
    end)

    RegisterNetEvent("esx_whitelist:startGracePeriod", function(seconds)
        uiController:startGracePeriod(seconds)
    end)

    RegisterNetEvent("esx_whitelist:cancelGracePeriod", function()
        uiController:cancelGracePeriod()
    end)
end

---Registers NUI callbacks for frontend actions
local function registerNuiCallbacks()
    RegisterNUICallback("closeUI", function(data, cb)
        uiController:toggle(false)
        cb("ok")
    end)

    RegisterNUICallback("getConfig", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:getConfig", function(serverConfig)
            if serverConfig then
                serverConfig.theme = getThemeConvars()
            end
            cb(serverConfig or {})
        end)
    end)

    RegisterNUICallback("updateConfig", function(configData, cb)
        ESX.TriggerServerCallback("esx_whitelist:updateConfig", function(success)
            cb(success)
        end, configData)
    end)

    RegisterNUICallback("testWebhook", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:testWebhook", function(success)
            if success then
                ESX.ShowNotification("~g~" .. Util.Translate(uiController.translations, "webhook_sent"))
            end
            cb(success)
        end)
    end)

    RegisterNUICallback("getWhitelistEntries", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:getWhitelistEntries", function(entries)
            cb(entries or {})
        end)
    end)

    RegisterNUICallback("managePlayer", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:managePlayer", function(success, message)
            cb({ success = success, message = message })
        end, data)
    end)

    RegisterNUICallback("toggleWhitelistStatus", function(data, cb)
        ESX.TriggerServerCallback("esx_whitelist:toggleWhitelistStatus", function(success)
            cb(success)
        end, data)
    end)
end

---Initializes the client whitelist service
local function init()
    registerNetworkEvents()
    registerNuiCallbacks()

    RegisterCommand(Config.UICommand, function()
        openWhitelistUI()
    end, false)
end

WhitelistClient.Init = init
WhitelistClient.OpenUI = openWhitelistUI

return WhitelistClient
