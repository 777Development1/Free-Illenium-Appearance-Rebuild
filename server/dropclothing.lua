-- Relays dropped hat/glasses between clients. The client that drops an item only knows
-- about it locally, so without this relay only that one player could ever see/pick it up.
-- This also makes the pickup atomic (claimedDrops) so two players diving for the same item
-- at the same time can't both end up wearing it.

if not Config.DropClothingOnHit or not Config.DropClothingOnHit.enabled then return end

local claimedDrops = {} -- [netId] = source of the player who claimed it

RegisterNetEvent("illenium-appearance:server:notifyDrop", function(netId, propId, drawable, texture, label)
    claimedDrops[netId] = nil
    TriggerClientEvent("illenium-appearance:client:addDroppedItem", -1, netId, propId, drawable, texture, label)
end)

lib.callback.register("illenium-appearance:server:claimDroppedItem", function(source, netId)
    if claimedDrops[netId] then
        return false -- someone else already got it
    end

    claimedDrops[netId] = source
    TriggerClientEvent("illenium-appearance:client:removeDroppedItem", -1, netId)
    return true
end)
