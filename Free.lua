-- ActionBars: the free bars, past the client's 120 action slots. Each
-- button holds a saved action, the same record as a profile's slot (spell by
-- ID, item by ID, macro by name and text, equipment set by name), taken from
-- the cursor (### GetCursorInfo()). Cooldown, usable state and counts come by
-- event; only the range has none (the GAP below).
local _, FB = ...
if not FB.Load then return end

local db = ActionBarsDB
local free = {} -- every free button
local events = CreateFrame("Frame")
local ticker -- the range check, while it is needed

local function Icon(a)
    local kind = a.kind
    if kind == "spell" then return C_Spell.GetSpellTexture(a.id) end
    if kind == "item" then return C_Item.GetItemIconByID(a.id) end
    if kind == "macro" then return (select(2, GetMacroInfo(a.name))) end
    local id = C_EquipmentSet.GetEquipmentSetID(a.name)
    return id and (select(2, C_EquipmentSet.GetEquipmentSetInfo(id)))
end

-- The spell a button casts: its own, or the one its macro shows (### GetMacroSpell).
local function SpellOf(a)
    if a.kind == "spell" then return a.id end
    if a.kind == "macro" then
        local index = GetMacroIndexByName(a.name)
        if index and index > 0 then return select(3, GetMacroSpell(index)) end
    end
end

local function FromCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" and b == "spell" then return { kind = kind, id = c } end
    if kind == "item" then return { kind = kind, id = a } end
    if kind == "macro" then return { kind = kind, name = GetMacroInfo(a), body = select(3, GetMacroInfo(a)) } end
    if kind == "equipmentset" then return { kind = kind, name = a } end
end

local function Usable(b)
    if b.spell then FB.Usable(b, IsUsableSpell(b.spell))
    elseif b.item then FB.Usable(b, IsUsableItem(b.item))
    else FB.Usable(b, true) end
end

local function Cooldown(b)
    -- The spellbook's numbers: C_Spell.GetSpellCooldown makes a table per call.
    if b.book then
        return FB.Cooldown(b, GetSpellCooldown(b.book, "spell"))
    elseif b.item then
        return FB.Cooldown(b, C_Container.GetItemCooldown(b.item))
    end
    FB.Cooldown(b, 0, 0, 0)
end

local function Count(b)
    local text = ""
    if b.item and IsConsumableItem(b.item) then
        text = C_Item.GetItemCount(b.item)
    elseif b.spell and db.reagents and IsConsumableSpell(b.spell) then
        local casts = C_Spell.GetSpellCastCount(b.spell)
        text = casts > 999 and "*" or casts
    end
    b.count:SetText(text)
end

-- Where a free button's range comes from. ClassicAPI gives two events: a
-- ranged spell that is on any action slot follows that slot
-- (### ACTION_RANGE_CHECK_UPDATE event), a melee spell the swing range
-- (### PLAYER_SWING_RANGE_UPDATE event; melee spells have 0 yards, ### GetSpellInfo,
-- which C_Spell.IsSelfBuff tells apart from a spell on yourself). "check" is the GAP.
local MAINHAND = Enum.PlayerSwingType.MainHand
local swinging = false -- the swing range check is on

local function Source(b)
    local spell = b.spell
    if spell then
        if C_Spell.SpellHasRange(spell) then
            local slots = C_ActionBar.FindSpellActionButtons(spell)
            if slots then return "slot", slots[1] end
            return "check"
        end
        if not C_Spell.IsSelfBuff(spell) then return "swing" end
    elseif b.item and C_Item.ItemHasRange(b.item) then
        return "check"
    end
end

local function Follow(b)
    local by, slot = Source(b)
    if b.rangeSlot ~= slot then
        if b.rangeSlot then C_ActionBar.EnableActionRangeCheck(b.rangeSlot, false) end
        if slot then C_ActionBar.EnableActionRangeCheck(slot, true) end -- the event comes at once
        b.rangeSlot = slot
    end
    b.rangeBy = by
    if not by and b.inRange ~= nil then FB.Range(b, nil) end
end

-- An event's answer: true or false, or nil when no check was possible.
local function Answer(inRange, checks)
    if checks then return inRange and true or false end
end

local function SwingRange(inRange)
    for _, b in ipairs(free) do
        if b.rangeBy == "swing" then FB.Range(b, inRange) end
    end
end

-- GAP: a per-spell range event (retail's C_Spell.EnableSpellRangeCheck and
-- SPELL_RANGE_CHECK_UPDATE, as C_ActionBar.EnableActionRangeCheck is for a
-- slot). Until a DLL gives one, a ranged spell on no slot and an item with a
-- range are checked every 0.2 s, only while there is a target and such a
-- button shows.
local function CheckRange()
    for _, b in ipairs(free) do
        if b.rangeBy == "check" and b.bar.holder:IsShown() then
            local inRange
            if b.spell then inRange = C_Spell.IsSpellInRange(b.spell, "target")
            else inRange = C_Item.IsItemInRange(b.item, "target") end
            if inRange ~= b.inRange then FB.Range(b, inRange) end
        end
    end
end

-- After a change of the buttons, a bar shown or hidden, or a new target.
local function Range()
    local check, swing = false, false
    for _, b in ipairs(free) do
        if b.bar.holder:IsShown() then
            check = check or b.rangeBy == "check"
            swing = swing or b.rangeBy == "swing"
        end
    end
    if swing ~= swinging then
        swinging = swing
        C_SwingTimer.EnableRangeCheck(MAINHAND, swing)
    end
    if swing then SwingRange(C_SwingTimer.IsTargetWithinSwingRange(MAINHAND)) end -- nil: no answer
    if check and UnitExists("target") then
        CheckRange()
        if not ticker then ticker = C_Timer.NewTicker(0.2, CheckRange) end
    else
        if ticker then ticker:Cancel(); ticker = nil end
        for _, b in ipairs(free) do
            if b.rangeBy == "check" and b.inRange ~= nil then FB.Range(b, nil) end
        end
    end
end
FB.FreeRange = Range

local function Equipped(b) FB.Equipped(b, b.item and C_Item.IsEquippedItem(b.item)) end

local function Draw(b)
    local a = b.action
    b.item = a and a.kind == "item" and a.id
    FB.Icon(b, a and (Icon(a) or "Interface\\Icons\\INV_Misc_QuestionMark")) -- an item not cached yet
    b.label:SetText(a and a.kind == "macro" and a.name or "")
    b.spell = a and SpellOf(a)
    b.book = b.spell and FindSpellBookSlotByID(b.spell)
    Equipped(b)
    Usable(b)
    Cooldown(b)
    Count(b)
    Follow(b)
end


local function Set(b, action)
    local row = db.free[b.bar.free] or {}
    db.free[b.bar.free] = row
    row[b.index] = action
    b.action = action
    Draw(b)
    Range()
end

local function Use(b)
    local a = b.action
    if not a then return end
    if a.kind == "spell" then
        local name, rank = GetSpellInfo(a.id)
        if name then CastSpellByName(rank and rank ~= "" and name .. "(" .. rank .. ")" or name) end
    elseif a.kind == "item" then
        C_Item.UseItemByName(a.id)
    elseif a.kind == "macro" then
        local _, _, body = GetMacroInfo(a.name)
        if body then RunMacroText(body) end
    else
        local id = C_EquipmentSet.GetEquipmentSetID(a.name)
        if id then C_EquipmentSet.UseEquipmentSet(id) end
    end
end

-- The cursor's action goes on the button, and what the button held goes on the cursor.
local function Take(b)
    local new = FromCursor()
    if not new then return end
    ClearCursor()
    local old = b.action
    Set(b, new)
    if old then FB.Pickup(old) end
end

-- Off the button only onto the cursor: an item with none left stays
-- (Shift-right-click clears it).
local function DragOff(b)
    if FB.Pickup(b.action) then Set(b, nil) end
end

local function OnClick()
    this:SetChecked(nil)
    if GetCursorInfo() then
        if LOCK_ACTIONBAR ~= "1" then Take(this) end
    elseif not this.has then
        return
    elseif IsShiftKeyDown() and arg1 == "RightButton" then
        Set(this, nil)
    elseif IsShiftKeyDown() then
        DragOff(this)
    else
        Use(this)
    end
end

local function OnDragStart()
    if LOCK_ACTIONBAR ~= "1" and this.has then DragOff(this) end
end

local function OnReceiveDrag()
    if LOCK_ACTIONBAR ~= "1" then Take(this) end
end

-- Returns 1 while the tooltip counts a cooldown down (Buttons.lua, FB.Hover).
local function Tooltip(b)
    local a, counting = b.action, nil
    if not a then GameTooltip:Hide(); return end
    if a.kind == "spell" then counting = GameTooltip:SetSpellByID(a.id)
    elseif a.kind == "item" then GameTooltip:SetHyperlink("item:" .. a.id)
    elseif a.kind == "macro" then GameTooltip:SetText(a.name)
    else GameTooltip:SetEquipmentSet(a.name) end
    GameTooltip:Show()
    return counting
end

local function Each(f)
    for _, b in ipairs(free) do
        if b.has then f(b) end
    end
end

local function SlotRange(b)
    if b.rangeSlot == arg1 then FB.Range(b, Answer(arg2, arg3)) end
end

events:SetScript("OnEvent", function()
    if event == "ACTION_RANGE_CHECK_UPDATE" then
        Each(SlotRange)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        if arg1 == MAINHAND then SwingRange(Answer(arg2, arg3)) end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then -- a spell may have come onto a slot, or left it
        Each(Follow)
        Range()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Each(Equipped)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        Each(Cooldown)
    elseif event == "BAG_UPDATE_DELAYED" then
        Each(Count)
        Each(Usable)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Each(Usable)
        Range()
    elseif event == "UNIT_POWER_UPDATE" then
        Each(Usable)
    else -- the spellbook, the macros or the sets changed
        Each(Draw)
        Range()
    end
end)

function FB.FreeButton(bar, i)
    local b = FB.NewButton("ActionBars_" .. bar.key .. "_" .. i, bar.holder)
    b.bar, b.index, b.Draw, b.Tooltip, b.Use = bar, i, Draw, Tooltip, Use
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnDragStart", OnDragStart)
    b:SetScript("OnReceiveDrag", OnReceiveDrag)
    -- The events listen once there is a free bar.
    if #free == 0 then
        for _, name in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
            "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "UPDATE_MACROS", "EQUIPMENT_SETS_CHANGED",
            "ACTION_RANGE_CHECK_UPDATE", "PLAYER_SWING_RANGE_UPDATE", "ACTIONBAR_SLOT_CHANGED",
            "PLAYER_EQUIPMENT_CHANGED" }) do
            events:RegisterEvent(name)
        end
        events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    end
    free[#free + 1] = b
    local row = db.free[bar.free]
    b.action = row and row[i]
    Draw(b)
    return b
end

-- For a profile: a copy of every free bar, and a load that counts what changed.
function FB.CopyFree(from)
    local copy = {}
    for n, row in pairs(from) do
        copy[n] = {}
        for i, action in pairs(row) do
            local a = {}
            for k, v in pairs(action) do a[k] = v end
            copy[n][i] = a
        end
    end
    return copy
end

local function Same(a, b)
    if not a or not b then return a == b end
    return a.kind == b.kind and a.id == b.id and a.name == b.name and a.body == b.body
end

function FB.LoadFree(saved)
    local old = db.free
    db.free = FB.CopyFree(saved)
    local changed = 0
    for n = 2, 1 + FB.MAX_EXTRA do
        local was, now = old[n] or {}, db.free[n] or {}
        for i = 1, 12 do
            if not Same(was[i], now[i]) then changed = changed + 1 end
        end
    end
    for _, b in ipairs(free) do
        local row = db.free[b.bar.free]
        b.action = row and row[b.index]
        Draw(b)
    end
    Range()
    return changed
end
