-- ActionBars: the bars. The six stock bars' slots, then up to ten extra
-- bars: first on the slot pages the class never pages to, then free bars past
-- slot 120 (Free.lua). Layout, Move bars and the keys.
local _, FB = ...
if not FB.Load then return end

local db = ActionBarsDB
FB.MAX_EXTRA = 10

-- How many bonus offsets the class pages the main bar to (ActionButton.lua:441-448).
-- UNVERIFIED: OctoWoW's custom content could give a class another form.
local PAGED = { WARRIOR = 3, DRUID = 3, ROGUE = 1 }

-- binding: the stock key binding names whose keys press these buttons.
-- anchor: where the bar sits until it is moved (point, bar key or the screen, point, x, y).
FB.bars = {
    { key = "main", name = "Main", first = 1, binding = "ACTIONBUTTON", anchor = { "BOTTOM", nil, "BOTTOM", 0, 4 } },
    { key = "bottomleft", name = "Bottom Left", first = 61, binding = "MULTIACTIONBAR1BUTTON",
        anchor = { "BOTTOM", "main", "TOP", 0, 30 } },
    { key = "bottomright", name = "Bottom Right", first = 49, binding = "MULTIACTIONBAR2BUTTON",
        anchor = { "BOTTOM", "bottomleft", "TOP", 0, 6 } },
    { key = "right", name = "Right", first = 25, binding = "MULTIACTIONBAR3BUTTON", columns = 1,
        anchor = { "RIGHT", nil, "RIGHT", -4, 0 } },
    { key = "left", name = "Left", first = 37, binding = "MULTIACTIONBAR4BUTTON", columns = 1,
        anchor = { "RIGHT", "right", "LEFT", -6, 0 } },
    { key = "extra1", name = "Extra 1", first = 13, anchor = { "BOTTOM", "bottomright", "TOP", 0, 6 } },
}
for n = 2, FB.MAX_EXTRA + 1 do
    FB.bars[#FB.bars + 1] = { key = "extra" .. n, name = "Extra " .. n, extra = n - 1,
        anchor = { "BOTTOM", n == 2 and "extra1" or "extra" .. (n - 1), "TOP", 0, 6 } }
end

-- The layout of a bar the player has not changed.
local LAYOUT = { shown = true, scale = 0.9, spacing = 6 }
function FB.LayoutDefault(bar, field)
    if field == "columns" then return bar.columns or 12 end
    if field == "showEmpty" then return bar.key == "main" end
    return LAYOUT[field]
end

FB.byKey = {}
for _, bar in ipairs(FB.bars) do
    FB.byKey[bar.key] = bar
    bar.cfg = db.bars[bar.key] or {}
    db.bars[bar.key] = bar.cfg
    for _, field in ipairs({ "shown", "scale", "columns", "spacing", "showEmpty" }) do
        if bar.cfg[field] == nil then bar.cfg[field] = FB.LayoutDefault(bar, field) end
    end
    -- Named, so the client saves where it is dragged (### frame:SetDontSavePosition).
    bar.holder = CreateFrame("Frame", "ActionBars_" .. bar.key, UIParent)
    bar.holder:SetMovable(true)
    bar.holder:SetClampedToScreen(true)
end

-- A bar dragged with Move bars is the client's: it saves the place in
-- layout-cache.txt and puts the bar back there at login. UNVERIFIED: that it
-- does so before PLAYER_ENTERING_WORLD, when the bars are laid out.
local function Place(bar)
    local holder = bar.holder
    if holder:IsUserPlaced() then return end
    local a = bar.anchor
    holder:ClearAllPoints()
    holder:SetPoint(a[1], a[2] and FB.byKey[a[2]].holder or UIParent, a[3], a[4], a[5])
end

-- The bar's top left on the screen, kept through a change of its size. At login
-- the client's saved place may not be laid out yet (GetLeft is nil, 2026-11-17):
-- the size changes and the client's anchor stays.
local function Pin(holder, scale)
    local old, left, top = holder:GetScale(), holder:GetLeft(), holder:GetTop()
    holder:SetScale(scale)
    if not left or not top then return end
    left, top = left * old, top * old
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

-- The page's "Placed by hand": off puts the bar back in its own spot, on keeps it where it is.
function FB.SetPlaced(bar, placed)
    local holder = bar.holder
    if placed == (holder:IsUserPlaced() and true or false) then return end
    if placed then Pin(holder, holder:GetScale()) end
    holder:SetUserPlaced(placed)
    Place(bar)
end

-- An extra bar is a slot bar while the class has a free slot page left.
local function Build(bar)
    if bar.extra then
        local _, class = UnitClass("player")
        local page = (PAGED[class] or 0) + bar.extra
        if page <= 4 then bar.first = 73 + 12 * (page - 1) else bar.free = bar.extra + 1 end
    end
    bar.buttons = {}
    for i = 1, 12 do
        bar.buttons[i] = bar.free and FB.FreeButton(bar, i) or FB.SlotButton(bar, i)
    end
end

function FB.Layout(bar)
    local cfg, holder = bar.cfg, bar.holder
    local columns = math.floor(cfg.columns)
    local step = 36 + cfg.spacing
    if holder:IsUserPlaced() then Pin(holder, cfg.scale) else holder:SetScale(cfg.scale) end
    holder:SetWidth(columns * step - cfg.spacing)
    holder:SetHeight(math.ceil(12 / columns) * step - cfg.spacing)
    Place(bar)
    local on = cfg.shown and (not bar.extra or bar.extra <= db.extraBars) and true or false
    if on and not bar.buttons then Build(bar) end
    if bar.buttons then
        for i, b in ipairs(bar.buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) % columns * step, -math.floor((i - 1) / columns) * step)
            FB.Grid(b)
        end
        if bar.Watch then bar:Watch(on) end
    end
    if on then holder:Show() else holder:Hide() end
    if bar.key == "main" then FB.Look() end
    if bar.free then FB.FreeRange() end
end

function FB.LayoutAll()
    for _, bar in ipairs(FB.bars) do FB.Layout(bar) end
    FB.Keys()
end

-- Move bars: a handle on each bar that shows; the place is saved where it is dropped.
local moving
local HANDLE = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 } }

local function Dropped()
    local bar = this.bar
    bar.holder:StopMovingOrSizing() -- StartMoving made it the client's to save
    if bar.placed then bar.placed:NotifyUpdate() end
end

local function Handle(bar)
    local handle = CreateFrame("Button", nil, bar.holder)
    handle.bar = bar
    handle:SetAllPoints(bar.holder)
    handle:SetFrameStrata("DIALOG")
    handle:SetBackdrop(HANDLE)
    handle:SetBackdropColor(0.1, 0.3, 0.6, 0.7)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() this.bar.holder:StartMoving() end)
    handle:SetScript("OnDragStop", Dropped)
    local text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", handle, "CENTER", 0, 0)
    text:SetText(bar.name)
    bar.handle = handle
    return handle
end

function FB.Move()
    moving = not moving
    for _, bar in ipairs(FB.bars) do
        if moving and bar.holder:IsShown() then (bar.handle or Handle(bar)):Show()
        elseif bar.handle then bar.handle:Hide() end
    end
    FB.Print(moving and "Drag the bars. Press Move bars again to lock them." or "Bars locked.")
end

-- Keys: those of the stock buttons press ours (Slots.lua); the other bars'
-- keys are in Key Bindings (Bindings.xml).
local function Command(bar, i)
    return bar.binding and bar.binding .. i or "ACTIONBARS_" .. string.upper(bar.key) .. "_" .. i
end

-- The key text on each button.
function FB.Keys()
    for _, bar in ipairs(FB.bars) do
        for i, b in ipairs(bar.buttons or {}) do FB.SetKey(b, (GetBindingKey(Command(bar, i)))) end
    end
end

BINDING_HEADER_ACTIONBARS = "ActionBars"
for _, bar in ipairs(FB.bars) do
    if not bar.binding then
        for i = 1, 12 do _G["BINDING_NAME_" .. Command(bar, i)] = bar.name .. " Button " .. i end
    end
end

-- Every bar's keys (Bindings.xml, Slots.lua), as ClassicAPI's stock handlers:
-- the press shows the button pushed, the release normal, and the action is used
-- on the press with the player's ActionButtonUseKeyDown, else on the release
-- (### ActionButtonUseKeyDown). Not a click: a key bound in Lua sees Shift held
-- (### Modifier keys during a binding), and a Shift-click picks the action up.
function ActionBars.Press(key, i, state, onSelf)
    local bar = FB.byKey[key]
    local b = bar and bar.buttons and bar.buttons[i]
    if not b or not bar.holder:IsShown() then return end
    local onPress = GetCVar("ActionButtonUseKeyDown") == "1"
    if state == "down" then
        b:SetButtonState("PUSHED")
        if onPress then b:Use() end
    elseif b:GetButtonState() == "PUSHED" then
        b:SetButtonState("NORMAL")
        if not onPress then b:Use(onSelf) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("CURSOR_CHANGED")
events:SetScript("OnEvent", function()
    if event == "CURSOR_CHANGED" then
        local dragging = GetCursorInfo() ~= nil
        if dragging ~= FB.dragging then
            FB.dragging = dragging
            for _, b in ipairs(FB.buttons) do FB.Grid(b) end
        end
    elseif event == "UPDATE_BINDINGS" then
        FB.Keys()
    elseif FB.built then
        FB.Redraw()
    else
        FB.built = true
        FB.LayoutAll()
    end
end)
