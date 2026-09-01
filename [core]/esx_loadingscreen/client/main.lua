--[[
    ESX Loading Screen - Client Logic
    Handles load screen lifecycle and NUI shutdown
--]]

local isLoadScreenActive = false
local currentProgress = 0
local targetProgress = 0

local UPDATE_INTERVAL <const> = 50
local SHUTDOWN_DELAY <const> = 2500
local PROGRESS_LERP_FACTOR <const> = 0.1

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    end
    return value
end

local function lerp(startValue, endValue, progress)
    return startValue + (endValue - startValue) * clamp(progress, 0, 1)
end

local function updateLoadScreen()
    while isLoadScreenActive do
        Wait(UPDATE_INTERVAL)

        if currentProgress < targetProgress then
            currentProgress = lerp(currentProgress, targetProgress, PROGRESS_LERP_FACTOR)
        end

        if currentProgress >= 100 then
            Wait(SHUTDOWN_DELAY)
            isLoadScreenActive = false
            ShutdownLoadingScreenNui()
        end
    end
end

local function setProgress(progress)
    targetProgress = clamp(progress, 0, 100)
end

local function init()
    isLoadScreenActive = true
    currentProgress = 0
    targetProgress = 0

    CreateThread(updateLoadScreen)
end

AddEventHandler("playerSpawned", init)

RegisterNetEvent("esx_loadScreen:setProgress")
AddEventHandler("esx_loadScreen:setProgress", function(progress)
    setProgress(progress)
end)