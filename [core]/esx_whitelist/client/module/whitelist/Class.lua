local Util <const> = xLib.require "@esx_whitelist.client.module.whitelist.util"

---@class WhitelistUIController
---@field isVisible boolean
---@field isGraceActive boolean
---@field graceThreadRunning boolean
---@field graceEndTime number
---@field translations table<string, string>
local WhitelistUI = {}
WhitelistUI.__index = WhitelistUI

---Creates a new WhitelistUI instance
---@return WhitelistUIController
function WhitelistUI.new()
    local self = setmetatable({}, WhitelistUI)
    self.isVisible = false
    self.isGraceActive = false
    self.graceThreadRunning = false
    self.graceEndTime = 0
    self.translations = Util.LoadLocale(Config.Locale)
    return self
end

---Toggles NUI focus and visibility state
---@param visible boolean
---@param initialData table?
function WhitelistUI:toggle(visible, initialData)
    self.isVisible = visible
    SetNuiFocus(visible, visible)

    if visible then
        SendNUIMessage({
            action = "openUI",
            data = initialData
        })
        self:startControlDisabler()
    else
        SendNUIMessage({
            action = "closeUI"
        })
    end
end

---Spawns an active thread ONLY while UI is open to disable conflicting game controls
function WhitelistUI:startControlDisabler()
    CreateThread(function()
        while self.isVisible do
            Wait(0)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 18, true)
            DisableControlAction(0, 106, true)
        end
    end)
end

---Starts temporary scoped grace period countdown thread.
---@param seconds number
function WhitelistUI:startGracePeriod(seconds)
    self.isGraceActive = true
    self.graceEndTime = GetGameTimer() + (seconds * 1000)

    if self.graceThreadRunning then
        return
    end

    self.graceThreadRunning = true
    CreateThread(function()
        while self.isGraceActive and (GetGameTimer() < self.graceEndTime) do
            Wait(1000)
            local remainingSeconds = math.ceil((self.graceEndTime - GetGameTimer()) / 1000)
            if remainingSeconds > 0 and self.isGraceActive then
                local message = string.format("~r~%s~s~\n%s",
                    Util.Translate(self.translations, "whitelist_active"),
                    Util.Translate(self.translations, "remaining_time", remainingSeconds)
                )
                ESX.ShowNotification(message)
            end
        end
        self.isGraceActive = false
        self.graceThreadRunning = false
    end)
end

---Cancels any active grace period
function WhitelistUI:cancelGracePeriod()
    self.isGraceActive = false
    self.graceEndTime = 0
    ESX.ShowNotification("~g~" .. Util.Translate(self.translations, "grace_cancelled"))
end

---@class WhitelistClientClassContainer
local Class = {
    WhitelistUI = WhitelistUI
}

return Class