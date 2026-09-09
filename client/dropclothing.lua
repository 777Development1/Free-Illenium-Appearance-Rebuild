-- Drops a worn hat/glasses on the ground when another player hits you, and lets anyone
-- nearby pick it back up. If Config.UseTarget is enabled (and ox_target/qb-target was
-- detected via this resource's existing Target abstraction in client/target/*.lua), the
-- pickup is offered through target. Otherwise, players just walk up and press E.
--
-- The drop is announced through the server (see server/dropclothing.lua) so every client
-- gets it added to their own droppedItems table and target registration -- not just the
-- client who got hit. Picking it up is also claimed through the server so two players
-- can't both walk away wearing the same hat.
--
-- NOTE ON THE DROPPED MODEL: matching the exact hat/glasses mesh you're wearing would need a
-- full lookup table from ped prop drawable -> world object model, which varies by DLC/clothing
-- pack and isn't something that can be reliably guessed. Config.DropClothingOnHit.hat.dropModel
-- and .glasses.dropModel use a generic placeholder object instead ("prop_cs_clothes_box"). If
-- you know the exact prop model name for your server's hats, swap it in there.

if not Config.DropClothingOnHit or not Config.DropClothingOnHit.enabled then return end

local UseTargetForPickup = Config.UseTarget and Target and Target.AddTargetEntity

local droppedItems = {} -- [objectHandle] = { propId = n, drawable = n, texture = n, label = s, netId = n }
local nearbyObj = nil -- only used in the E-key (non-target) pickup mode

local function forgetDrop(obj)
    droppedItems[obj] = nil
    if nearbyObj == obj then
        nearbyObj = nil
        lib.hideTextUI()
    end
end

local function pickupDroppedItem(obj)
    local data = droppedItems[obj]
    if not data or not DoesEntityExist(obj) then
        forgetDrop(obj)
        return
    end

    -- Claim it on the server first. If someone else grabbed it a moment earlier, this
    -- returns false and we just clean up locally instead of also equipping it.
    local claimed = lib.callback.await("illenium-appearance:server:claimDroppedItem", false, data.netId)
    if not claimed then
        forgetDrop(obj)
        return
    end

    SetPedPropIndex(PlayerPedId(), data.propId, data.drawable, data.texture, true)
    forgetDrop(obj)
end

local function spawnDrop(propId, cfg)
    local ped = PlayerPedId()
    local drawable = GetPedPropIndex(ped, propId)
    if drawable == -1 then return end -- nothing worn in this slot, nothing to drop

    if math.random(1, 100) > cfg.chance then return end

    local texture = GetPedPropTextureIndex(ped, propId)
    local coords = GetEntityCoords(ped)
    local dropX = coords.x + (math.random(-60, 60) / 100.0)
    local dropY = coords.y + (math.random(-60, 60) / 100.0)

    ClearPedProp(ped, propId)

    lib.requestModel(cfg.dropModel)
    local obj = CreateObject(cfg.dropModel, dropX, dropY, coords.z + 0.3, true, true, true)
    SetEntityDynamic(obj, true)
    PlaceObjectOnGroundProperly(obj)

    local netId = ObjToNet(obj)

    -- Announce the drop through the server so every client (including us) adds it via the
    -- same addDroppedItem handler below -- one code path instead of duplicating the
    -- "add to droppedItems / register target" logic here too.
    TriggerServerEvent("illenium-appearance:server:notifyDrop", netId, propId, drawable, texture, cfg.label)

    local despawnAfter = Config.DropClothingOnHit.despawnAfter
    if despawnAfter and despawnAfter > 0 then
        SetTimeout(despawnAfter, function()
            if droppedItems[obj] and DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
            forgetDrop(obj)
        end)
    end
end

-- Fired for every client (including the one who dropped it) once the server has been told
-- about a new drop. Waits for the networked object to actually exist locally before wiring
-- it up, since replication to other clients isn't instant.
RegisterNetEvent("illenium-appearance:client:addDroppedItem", function(netId, propId, drawable, texture, label)
    CreateThread(function()
        local attempts = 0
        while not NetworkDoesEntityExistWithNetworkId(netId) and attempts < 100 do
            Wait(50)
            attempts = attempts + 1
        end
        if not NetworkDoesEntityExistWithNetworkId(netId) then return end

        local obj = NetworkGetEntityFromNetworkId(netId)
        if not DoesEntityExist(obj) then return end

        droppedItems[obj] = { propId = propId, drawable = drawable, texture = texture, label = label, netId = netId }

        if UseTargetForPickup then
            Target.AddTargetEntity(obj, {
                distance = Config.DropClothingOnHit.pickupDistance,
                options = {{
                    type = "client",
                    icon = "fas fa-hand",
                    label = label,
                    action = function()
                        pickupDroppedItem(obj)
                    end
                }}
            })
        end
    end)
end)

-- Fired for every client once someone has successfully claimed a drop (or it despawned),
-- so everyone's local state and the object itself get cleaned up together.
RegisterNetEvent("illenium-appearance:client:removeDroppedItem", function(netId)
    for obj, data in pairs(droppedItems) do
        if data.netId == netId then
            forgetDrop(obj)
            if DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
            break
        end
    end
end)

-- Non-target pickup: walk within Config.DropClothingOnHit.pickupDistance of a dropped
-- hat/glasses and press E. Only runs when target pickup isn't available/enabled.
local function ProximityPickupLoop()
    while true do
        local sleep = 1000

        if next(droppedItems) then
            sleep = 250

            local coords = GetEntityCoords(PlayerPedId())
            local closestObj, closestDist = nil, nil

            for obj, data in pairs(droppedItems) do
                if DoesEntityExist(obj) then
                    local dist = #(coords - GetEntityCoords(obj))
                    if dist <= Config.DropClothingOnHit.pickupDistance and (not closestDist or dist < closestDist) then
                        closestObj, closestDist = obj, dist
                    end
                else
                    forgetDrop(obj)
                end
            end

            if closestObj ~= nearbyObj then
                if nearbyObj then
                    lib.hideTextUI()
                end
                nearbyObj = closestObj
                if nearbyObj then
                    lib.showTextUI("[E] " .. droppedItems[nearbyObj].label, Config.TextUIOptions)
                end
            end

            if nearbyObj then
                sleep = 5
                if IsControlJustReleased(0, 38) then -- INPUT_PICKUP (E)
                    pickupDroppedItem(nearbyObj)
                end
            end
        elseif nearbyObj then
            nearbyObj = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end

-- Official FiveM client event: fires locally whenever an entity you're tracking takes damage.
-- victim/culprit are ped handles, weapon is a hash, baseDamage is a float.
AddEventHandler('entityDamaged', function(victim, culprit, weapon, baseDamage)
    if victim ~= PlayerPedId() then return end
    if not culprit or culprit == 0 or culprit == victim then return end
    if not IsPedAPlayer(culprit) then return end

    spawnDrop(0, Config.DropClothingOnHit.hat)     -- prop slot 0 = hat
    spawnDrop(1, Config.DropClothingOnHit.glasses) -- prop slot 1 = glasses
end)

CreateThread(function()
    if not UseTargetForPickup then
        ProximityPickupLoop()
    end
end)

-- Clean up anything this resource dropped if it restarts, so nothing is left on the ground
-- pointing at an interaction that no longer does anything.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if nearbyObj then
        lib.hideTextUI()
    end
    for obj in pairs(droppedItems) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
end)
