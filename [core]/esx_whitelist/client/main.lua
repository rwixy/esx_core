local WhitelistClient <const> = xLib.require "@esx_whitelist.client.module.whitelist.main"

WhitelistClient.Init()

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    SetNuiFocus(false, false)
end)