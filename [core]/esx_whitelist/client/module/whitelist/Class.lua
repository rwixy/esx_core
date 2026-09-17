local Util <const> = xLib.require "@esx_whitelist.client.module.whitelist.util"

local WhitelistUI = {}
WhitelistUI.__index = WhitelistUI

function WhitelistUI.new()
    local self = setmetatable({}, WhitelistUI)
    self.isVisible = false
    self.isGraceActive = false
    self.graceThreadRunning = false
    self.graceEndTime = 0
    self.translations = Util.LoadLocale(Config.Locale)
    return self
end

function WhitelistUI:toggle(visible, data)
    self.isVisible = visible
    SetNuiFocus(visible, visible)
    SendNUIMessage({ action = visible and "openUI" or "closeUI", data = visible and data or nil })
    if visible then self:startControlDisabler() end
end

function WhitelistUI:startControlDisabler()
    if self.controlThreadRunning then return end
    self.controlThreadRunning = true
    CreateThread(function()
        while self.isVisible do
            Wait(0)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 18, true)
            DisableControlAction(0, 106, true)
        end
        self.controlThreadRunning = false
    end)
end

function WhitelistUI:startGracePeriod(seconds)
    self.isGraceActive = true
    self.graceEndTime = GetGameTimer() + math.max(0, tonumber(seconds) or 0) * 1000
    if self.graceThreadRunning then return end
    self.graceThreadRunning = true
    CreateThread(function()
        while self.isGraceActive and GetGameTimer() < self.graceEndTime do
            Wait(1000)
            local remaining = math.ceil((self.graceEndTime - GetGameTimer()) / 1000)
            if remaining > 0 and self.isGraceActive then
                ESX.ShowNotification(string.format("~r~%s~s~\n%s", Util.Translate(self.translations, "whitelist_active"), Util.Translate(self.translations, "remaining_time", remaining)))
            end
        end
        self.isGraceActive = false
        self.graceThreadRunning = false
    end)
end

function WhitelistUI:cancelGracePeriod()
    self.isGraceActive = false
    self.graceEndTime = 0
    ESX.ShowNotification("~g~" .. Util.Translate(self.translations, "grace_cancelled"))
end

return { WhitelistUI = WhitelistUI }
