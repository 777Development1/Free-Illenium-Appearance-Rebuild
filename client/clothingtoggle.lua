-- Toggle individual clothing pieces on/off with chat commands (/hat, /shirt, /shoes, etc.)
-- Running the same command again restores the exact drawable/texture that was hidden.

if not Config.EnableClothingToggleCommands then return end

local hiddenComponents = {} -- [componentId] = { drawable = n, texture = n }
local hiddenProps = {}      -- [propId] = { drawable = n, texture = n } (drawable = -1 means "no prop was worn")

-- Fallback clip for any slot not covered by SLOT_ANIMATIONS below. Same one the built-in
-- wearClothes/removeClothes flow uses for most components (game/customization.lua).
local DEFAULT_ANIM = { dict = "clothingtie", anim = "try_tie_negative_a", duration = 1200, move = 51 }

-- Per-slot on/off animations, matching what the appearance menu itself plays for the same
-- pieces (constants.DATA_CLOTHES "head" and "bottom" categories in game/constants.lua):
-- putting the piece back on plays the "on" clip, hiding it plays the "off" clip.
local SLOT_ANIMATIONS = {
    props = {
        [0] = { -- hat (DATA_CLOTHES.head)
            on = { dict = "mp_masks@standard_car@ds@", anim = "put_on_mask", duration = 600, move = 51 },
            off = { dict = "missheist_agency2ahelmet", anim = "take_off_helmet_stand", duration = 1200, move = 51 }
        }
    },
    components = {
        [4] = { -- pants (DATA_CLOTHES.bottom)
            on = { dict = "re@construction", anim = "out_of_breath", duration = 1300, move = 51 },
            off = { dict = "re@construction", anim = "out_of_breath", duration = 1300, move = 51 }
        }
    }
}

local function resolveAnim(slotTable, id, isRestoring)
    local entry = slotTable and slotTable[id]
    if not entry then return DEFAULT_ANIM end
    return (isRestoring and entry.on or entry.off) or DEFAULT_ANIM
end

local function playAnim(animData)
    local ped = PlayerPedId()

    RequestAnimDict(animData.dict)
    local attempts = 0
    while not HasAnimDictLoaded(animData.dict) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end

    if HasAnimDictLoaded(animData.dict) then
        TaskPlayAnim(ped, animData.dict, animData.anim, 3.0, 3.0, animData.duration, animData.move, 0, false, false, false)
    end
end

local function toggleComponent(componentId)
    local ped = PlayerPedId()
    local isRestoring = hiddenComponents[componentId] ~= nil
    playAnim(resolveAnim(SLOT_ANIMATIONS.components, componentId, isRestoring))

    if isRestoring then
        local saved = hiddenComponents[componentId]
        SetPedComponentVariation(ped, componentId, saved.drawable, saved.texture, 0)
        hiddenComponents[componentId] = nil
    else
        hiddenComponents[componentId] = {
            drawable = GetPedDrawableVariation(ped, componentId),
            texture = GetPedTextureVariation(ped, componentId)
        }
        SetPedComponentVariation(ped, componentId, 0, 0, 0)
    end
end

local function toggleProp(propId)
    local ped = PlayerPedId()
    local isRestoring = hiddenProps[propId] ~= nil
    playAnim(resolveAnim(SLOT_ANIMATIONS.props, propId, isRestoring))

    if isRestoring then
        local saved = hiddenProps[propId]
        if saved.drawable == -1 then
            ClearPedProp(ped, propId)
        else
            SetPedPropIndex(ped, propId, saved.drawable, saved.texture, true)
        end
        hiddenProps[propId] = nil
    else
        hiddenProps[propId] = {
            drawable = GetPedPropIndex(ped, propId),
            texture = GetPedPropTextureIndex(ped, propId)
        }
        ClearPedProp(ped, propId)
    end
end

for _, entry in ipairs(Config.ClothingToggleCommands) do
    if entry.component then
        RegisterCommand(entry.command, function()
            toggleComponent(entry.component)
        end, false)
    elseif entry.prop then
        RegisterCommand(entry.command, function()
            toggleProp(entry.prop)
        end, false)
    end
end

-- Restore everything if this resource restarts, so nobody gets stuck with
-- permanently hidden clothing because a toggle state was lost mid-restart.
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local ped = PlayerPedId()

    for componentId, saved in pairs(hiddenComponents) do
        SetPedComponentVariation(ped, componentId, saved.drawable, saved.texture, 0)
    end

    for propId, saved in pairs(hiddenProps) do
        if saved.drawable ~= -1 then
            SetPedPropIndex(ped, propId, saved.drawable, saved.texture, true)
        end
    end
end)
