local WhitelistClient <const> = xLib.require "@esx_whitelist.client.module.whitelist.main"

WhitelistClient.Init()

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetNuiFocus(false, false)
    end
end)
