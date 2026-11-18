-- ActionBars: the buttons on action slots 1-120. One event frame tells
-- each slot only what changed: ACTIONBAR_SLOT_CHANGED for one slot,
-- ACTION_USABLE_CHANGED and ACTION_RANGE_CHECK_UPDATE for the slots named
-- (### C_ActionBar.EnableActionRangeCheck). No button has an OnUpdate.
local _, FB = ...
if not FB.Load then return end

local db = ActionBarsDB
local buttons, bySlot = {}, {} -- every slot button; slot -> { [button] = true }
local NONE = {} -- a slot no button shows
local attacking -- between PLAYER_ENTER_COMBAT and PLAYER_LEAVE_COMBAT (auto-attack)

-- The main bar pages as the stock one does (ActionButton.lua:441-461): bonus
-- offset k (stealth, a stance, a form) shows slots 73+12(k-1) to 84+12(k-1).
local function MainSlot(i)
    local offset = GetBonusBarOffset()
    if CURRENT_ACTIONBAR_PAGE == 1 and offset > 0 then return i + (5 + offset) * 12 end
    return i + (CURRENT_ACTIONBAR_PAGE - 1) * 12
end

-- An item's count; with Reagent Counter, how many casts the reagents allow.
local function Count(b)
    local slot, text = b.slot, ""
    if IsConsumableAction(slot) then
        text = GetActionCount(slot)
    elseif db.reagents and not IsItemAction(slot) then
        local spell = C_ActionBar.GetSpell(slot)
        if spell ~= 0 and IsConsumableSpell(spell) then
            local casts = C_Spell.GetSpellCastCount(spell)
            text = casts > 999 and "*" or casts
        end
    end
    b.count:SetText(text)
end

local function State(b)
    local slot = b.slot
    local current, repeating = IsCurrentAction(slot), IsAutoRepeatAction(slot)
    b:SetChecked(current or repeating)
    FB.Flash(b, repeating or (attacking and current and IsAttackAction(slot)))
end

local function Border(b) FB.Equipped(b, IsEquippedAction(b.slot)) end

local function Tooltip(b) return GameTooltip:SetAction(b.slot) end

local function Draw(b)
    local slot = b.slot
    FB.Icon(b, HasAction(slot) and GetActionTexture(slot) or nil)
    b.label:SetText(GetActionText(slot))
    Border(b)
    FB.Usable(b, IsUsableAction(slot))
    if b.has then FB.Cooldown(b, GetActionCooldown(slot)) end
    Count(b)
    State(b)
    if GameTooltip:IsOwned(b) then FB.Hover(b) end
end

-- The client counts the range checks per slot, so each button enables the
-- slot it shows, while its bar shows.
local function SetSlot(b, slot)
    local old = b.slot
    if old == slot then return end
    if old then
        bySlot[old][b] = nil
        if b.watching then C_ActionBar.EnableActionRangeCheck(old, false) end
    end
    b.slot = slot
    -- The stock button of the same key uses this slot too: the game's own binding
    -- presses it (the hooks below).
    for _, twin in ipairs(b.twins or {}) do twin.action = slot end
    bySlot[slot] = bySlot[slot] or {}
    bySlot[slot][b] = true
    if b.watching then C_ActionBar.EnableActionRangeCheck(slot, true) end
    FB.Range(b, nil)
    Draw(b)
end

local function Watch(bar, on)
    for _, b in ipairs(bar.buttons) do
        if b.watching ~= on then
            b.watching = on
            C_ActionBar.EnableActionRangeCheck(b.slot, on)
        end
    end
end

-- The stock button's scripts (ActionBarFrame.xml:12-45), with the action bar lock.
local function OnClick()
    if IsShiftKeyDown() then
        PickupAction(this.slot)
    else
        if MacroFrame_SaveMacro then MacroFrame_SaveMacro() end
        UseAction(this.slot, 1)
    end
    State(this)
end

local function OnDragStart()
    if LOCK_ACTIONBAR ~= "1" then PickupAction(this.slot); State(this) end
end

local function OnReceiveDrag()
    if LOCK_ACTIONBAR ~= "1" then PlaceAction(this.slot); State(this) end
end

-- A key from Key Bindings (ActionBars.Press), as the stock ActionButtonUp.
local function Use(b)
    if MacroFrame_SaveMacro then MacroFrame_SaveMacro() end
    UseAction(b.slot, 0)
    State(b)
end

-- The stock buttons of each stock bar (FrameXML ActionBarFrame.xml, MultiActionBars.xml).
local STOCK = { main = "Action", bottomleft = "MultiBarBottomLeft", bottomright = "MultiBarBottomRight",
    right = "MultiBarRight", left = "MultiBarLeft" }

-- Their keys: the game's own bindings press the stock buttons, which use our
-- slot (ActionButtonUp, MultiActionButtonUp: UseAction(button.action, 0)), so a
-- key acts as on the stock bars. A click of ours would pick the action up when
-- Shift is held, and Shift+6 runs the binding of 6 with Shift held (### Keys
-- with modifiers). Our button shows the press.
local BAR = {}
for key, stock in pairs(STOCK) do BAR[stock] = key end
local function Pushed(stock, i, state)
    local buttons = FB.byKey[BAR[stock]].buttons
    if buttons then buttons[i]:SetButtonState(state) end
end
hooksecurefunc("ActionButtonDown", function(i) Pushed("Action", i, "PUSHED") end)
hooksecurefunc("ActionButtonUp", function(i) Pushed("Action", i, "NORMAL") end)
hooksecurefunc("MultiActionButtonDown", function(bar, i) Pushed(bar, i, "PUSHED") end)
hooksecurefunc("MultiActionButtonUp", function(bar, i) Pushed(bar, i, "NORMAL") end)

function FB.SlotButton(bar, i)
    local b = FB.NewButton("ActionBars_" .. bar.key .. "_" .. i, bar.holder)
    b.bar, b.Draw, b.Tooltip, b.Use = bar, Draw, Tooltip, Use
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnDragStart", OnDragStart)
    b:SetScript("OnReceiveDrag", OnReceiveDrag)
    bar.Watch = Watch
    buttons[#buttons + 1] = b
    local stock = STOCK[bar.key]
    if stock then b.twins = { _G[stock .. "Button" .. i], bar.key == "main" and _G["BonusActionButton" .. i] or nil } end
    SetSlot(b, bar.key == "main" and MainSlot(i) or bar.first + i - 1)
    return b
end

local function Each(f)
    for _, b in ipairs(buttons) do
        if b.has then f(b) end
    end
end

local function Cooldown(b) FB.Cooldown(b, GetActionCooldown(b.slot)) end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if event == "ACTIONBAR_SLOT_CHANGED" then
        if arg1 == 0 then
            for _, b in ipairs(buttons) do Draw(b) end
        elseif bySlot[arg1] then
            for b in pairs(bySlot[arg1]) do Draw(b) end
        end
    elseif event == "ACTION_USABLE_CHANGED" then
        for _, change in ipairs(arg1) do
            for b in pairs(bySlot[change.slot] or NONE) do FB.Usable(b, change.usable, change.noMana) end
        end
    elseif event == "ACTION_RANGE_CHECK_UPDATE" then
        local inRange -- nil: no check (### ACTION_RANGE_CHECK_UPDATE event)
        if arg3 then inRange = arg2 and true or false end
        for b in pairs(bySlot[arg1] or NONE) do FB.Range(b, inRange) end
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        Each(Cooldown)
    elseif event == "BAG_UPDATE_DELAYED" then
        Each(Count)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Each(Border)
    elseif event == "UNIT_INVENTORY_CHANGED" then -- a thrown stack or charges (ActionButton.lua:325)
        Each(Count)
    elseif event == "UPDATE_BONUS_ACTIONBAR" or event == "ACTIONBAR_PAGE_CHANGED" then
        local main = FB.byKey.main.buttons
        if main then for i, b in ipairs(main) do SetSlot(b, MainSlot(i)) end end
    elseif event == "UPDATE_MACROS" then
        Each(Draw)
    else -- the checked and flash state
        if event == "PLAYER_ENTER_COMBAT" then attacking = true
        elseif event == "PLAYER_LEAVE_COMBAT" then attacking = nil end
        Each(State)
    end
end)
for _, name in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTION_USABLE_CHANGED", "ACTION_RANGE_CHECK_UPDATE",
    "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE", "BAG_UPDATE_DELAYED", "UPDATE_BONUS_ACTIONBAR",
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_MACROS", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "CRAFT_SHOW", "CRAFT_CLOSE", "PLAYER_EQUIPMENT_CHANGED" }) do
    events:RegisterEvent(name)
end
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
