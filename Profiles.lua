-- FostercareBars: profiles, the buttons on the action bars saved under a name
-- and put back later. Doc headings are ClassicAPI's docs/API.md.
if not CLASSIC_API_VERSION then
    error("FostercareBars needs ClassicAPI.", 0)
end

local _, FB = ...
FostercareBarsDB = FostercareBarsDB or {} -- restored first: LoadSavedVariablesFirst
local db = FostercareBarsDB
db.profiles = db.profiles or {}
db.free = db.free or {} -- [bar number][button] = a saved action, for the bars past slot 120
db.bars = db.bars or {} -- [bar key] = its layout

-- The page's switches, and how many extra bars there are. Filled in here, since the
-- bars are drawn before the Settings window registers the page.
FB.DEFAULTS = { hideGryphons = true, floating = true, shortMain = true, reagents = true,
    hideStanceBar = true, extraBars = 1 }
for key, value in pairs(FB.DEFAULTS) do
    if db[key] == nil then db[key] = value end
end

local SLOTS, MACROS = 120, 36
local waiting -- slot -> saved item, while an item a load wanted is not in the bags
local listener = CreateFrame("Frame")

function FB.Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cffff9e38FostercareBars:|r " .. text) end

local function Label(action)
    if action.kind == "spell" then return GetSpellInfo(action.id) or "spell " .. action.id end
    if action.kind == "item" then return GetItemInfo(action.id) or "item " .. action.id end
    return action.name
end

-- Saving ----------------------------------------------------------------------

-- What a slot holds (GetActionInfo); nil for an empty slot. Spells and items
-- by ID, so by rank; macros by name and text, since their indexes move.
local function Read(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "macro" then
        local name, _, body = GetMacroInfo(id)
        return { kind = kind, name = name, body = body }
    elseif kind == "equipmentset" then
        return { kind = kind, name = id }
    elseif kind then
        return { kind = kind, id = id }
    end
end

-- Returns the saved name, or false.
function FB.Save(name)
    name = string.match(name or "", "^%s*(.-)%s*$")
    if name == "" then FB.Print("A profile needs a name."); return false end
    local old = db.profiles[name]
    local profile = { actions = {}, free = FB.CopyFree(db.free) }
    for slot = 1, SLOTS do profile.actions[slot] = Read(slot) end
    db.profiles[name] = profile
    FB.Print((old and "Saved over \"" or "Saved \"") .. name .. "\".")
    return name
end

function FB.Delete(name)
    if not db.profiles[name] then return false end
    db.profiles[name] = nil
    FB.Print("Deleted \"" .. name .. "\".")
    return true
end

-- Case is ignored in the order, not in the names: "PVP" and "pvp" are two.
local function Before(a, b)
    local la, lb = string.lower(a), string.lower(b)
    if la ~= lb then return la < lb end
    return a < b
end

function FB.Names()
    local names = {}
    for name in pairs(db.profiles) do names[#names + 1] = name end
    table.sort(names, Before)
    return names
end

-- Loading ---------------------------------------------------------------------

local function Macros()
    local list = {}
    for index = 1, MACROS do
        local name, _, body = GetMacroInfo(index)
        if name then list[#list + 1] = { index = index, name = name, body = body } end
    end
    return list
end

-- The macro with the saved name and text; else the only one with the name.
local function FindMacro(action, macros)
    local found
    for _, macro in ipairs(macros) do
        if macro.name == action.name then
            if macro.body == action.body then return macro.index end
            found = found == nil and macro.index or false
        end
    end
    return found or nil
end

-- A saved action as it is now: what GetActionInfo reports once it is placed,
-- what picks it up (nil: nothing can), and why nothing can.
local function Find(action, macros)
    local kind = action.kind
    if kind == "spell" then
        local slot, book = FindSpellBookSlotByID(action.id)
        return action.id, book == "spell" and slot or nil, "spell not known"
    elseif kind == "item" then
        -- Worn items count (C_Item.GetItemCount).
        return action.id, C_Item.GetItemCount(action.id) > 0 and action.id or nil, "not in your bags"
    elseif kind == "macro" then
        local index = FindMacro(action, macros)
        return index, index, "macro not found"
    end
    return action.name, C_EquipmentSet.GetEquipmentSetID(action.name), "set not found"
end

-- False when nothing reached the cursor: C_Item.PickupItem leaves a locked item.
local function Grab(kind, source)
    if kind == "spell" then PickupSpell(source, "spell")
    elseif kind == "item" then C_Item.PickupItem(source)
    elseif kind == "macro" then PickupMacro(source)
    else C_EquipmentSet.PickupEquipmentSet(source) end
    return GetCursorInfo() ~= nil
end

-- A saved action on the cursor (a free button's, dragged off it).
function FB.Pickup(action)
    local _, source = Find(action, Macros())
    return source ~= nil and Grab(action.kind, source)
end

local function Put(slot, kind, source)
    if not Grab(kind, source) then return false end
    PlaceAction(slot)
    ClearCursor()
    return true
end

local function Empty(slot) PickupAction(slot); ClearCursor() end

-- Listens only while a slot waits (BAG_UPDATE_DELAYED: once per frame).
local function Wait(slots)
    waiting = slots
    if slots then
        listener:RegisterEvent("BAG_UPDATE_DELAYED")
        listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        listener:UnregisterAllEvents()
    end
end

-- An item that arrived goes to its slot, unless the player filled the slot.
listener:SetScript("OnEvent", function()
    if not waiting or UnitAffectingCombat("player") or GetCursorInfo() then return end
    for slot, action in pairs(waiting) do
        if GetActionInfo(slot) then
            waiting[slot] = nil
        elseif C_Item.GetItemCount(action.id) > 0 and Put(slot, "item", action.id) then
            waiting[slot] = nil
            FB.Print("Placed " .. Label(action) .. ".")
        end
    end
    if next(waiting) == nil then Wait(nil) end
end)

function FB.Load(name)
    local profile = db.profiles[name]
    if not profile then FB.Print("No profile \"" .. tostring(name) .. "\"."); return false end
    -- Buttons are placed with the cursor (InCombatLockdown is always false here).
    if UnitAffectingCombat("player") then FB.Print("Leave combat to load a profile."); return false end
    if GetCursorInfo() then FB.Print("Empty the cursor to load a profile."); return false end
    local macros, changed, missing, skipped, waits = Macros(), 0, {}, {}, nil
    for slot = 1, SLOTS do
        local action, kind, id = profile.actions[slot], GetActionInfo(slot)
        if not action then
            if kind then Empty(slot); changed = changed + 1 end
        else
            local want, source, why = Find(action, macros)
            if kind ~= action.kind or id ~= want then
                if source then
                    if Put(slot, action.kind, source) then changed = changed + 1
                    else skipped[#skipped + 1] = Label(action) .. " (item is locked)" end
                elseif action.kind == "item" then
                    -- Potions run out: the slot is filled when the item arrives.
                    if kind then Empty(slot); changed = changed + 1 end
                    waits = waits or {}
                    waits[slot] = action
                    missing[#missing + 1] = Label(action)
                else
                    skipped[#skipped + 1] = Label(action) .. " (" .. why .. ")"
                end
            end
        end
    end
    -- A profile from before the free bars leaves them as they are.
    if profile.free then changed = changed + FB.LoadFree(profile.free) end
    Wait(waits) -- this load decided every slot: earlier waits are over
    FB.Print("Loaded \"" .. name .. "\": " .. changed .. (changed == 1 and " button" or " buttons")
        .. " changed.")
    if waits then FB.Print("Placed when they reach your bags: " .. table.concat(missing, ", ") .. ".") end
    if #skipped > 0 then FB.Print("Left as they were: " .. table.concat(skipped, ", ") .. ".") end
    return true
end

-- For other addons (BrainwasherPro).
FostercareBars = { GetProfileNames = FB.Names, LoadProfile = FB.Load }
