-- FostercareBars: what every button shares, on a slot or past slot 120: the
-- stock button's parts (FrameXML ActionButtonTemplate.xml, no scripts), a
-- native Cooldown that counts down, and the stock colours for usable, range,
-- key and flash (ActionButton.lua). Doc headings are ClassicAPI's docs/API.md.
local _, FB = ...
if not FB.Load then return end

local db = FostercareBarsDB
FB.buttons = {}
FB.hidden = CreateFrame("Frame") -- the parent of what the addon hides
FB.hidden:Hide()

-- The countdown in F12's look (### CreateFrame("Cooldown"...), SetCountdownFormatter).
local Up = Enum.NumericRuleFormatRounding.Up
local countdown = C_StringUtil.CreateNumericRuleFormatter()
countdown:SetBreakpoints({
    { threshold = 0, step = 0.1, rounding = Up, format = "|cffff4444%.1f|r" },
    { threshold = 5, step = 1, rounding = Up, format = "|cffffff33%d|r" },
    { threshold = 10, step = 1, rounding = Up, format = "|cffffffff%d|r" },
    { threshold = 60, format = "|cffffffff%dm|r", components = { { div = 60, step = 1, rounding = Up } } },
    { threshold = 3600, format = "|cffffffff%dh|r", components = { { div = 3600, step = 1, rounding = Up } } },
    { threshold = 86400, format = "|cffffffff%dd|r", components = { { div = 86400, step = 1, rounding = Up } } },
})
FB.Countdown = countdown

local EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 }

-- Floating Actionbar: a thin grey frame round a cropped icon; else the stock quickslot.
function FB.Style(b)
    if db.floating then
        b.edge:Show(); b.normal:SetAlpha(0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
        b.edge:Hide(); b.normal:SetAlpha(1); b.icon:SetTexCoord(0, 1, 0, 1)
    end
end

-- The tooltip of the button under the cursor. The engine tells when it shows
-- a cooldown that counts down (GameTooltip:SetAction and SetSpellByID return
-- 1, ### GameTooltip:SetSpellByID); only then is it filled again each second,
-- and only while the cursor stays. b:Tooltip() fills it and returns that 1.
local hovered, refresh

local function Refill()
    if hovered and GameTooltip:IsOwned(hovered) then FB.Hover(hovered) else FB.Unhover() end
end

function FB.Hover(b)
    hovered = b
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local counting = b:Tooltip()
    if counting and not refresh then refresh = C_Timer.NewTicker(1, Refill)
    elseif not counting and refresh then refresh:Cancel(); refresh = nil end
end

function FB.Unhover()
    if hovered and GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
    hovered = nil
    if refresh then refresh:Cancel(); refresh = nil end
end

local function OnEnter() FB.Hover(this) end
local function OnLeave() FB.Unhover() end

function FB.NewButton(name, parent)
    local b = CreateFrame("CheckButton", name, parent, "ActionButtonTemplate")
    b.icon, b.count, b.hotkey = _G[name .. "Icon"], _G[name .. "Count"], _G[name .. "HotKey"]
    b.label, b.border, b.flash = _G[name .. "Name"], _G[name .. "Border"], _G[name .. "Flash"]
    b.normal = _G[name .. "NormalTexture"]
    _G[name .. "Cooldown"]:SetParent(FB.hidden) -- the 1.12 Model; the native one counts down
    b.cooldown = CreateFrame("Cooldown", nil, b)
    b.cooldown:SetAllPoints(b)
    b.cooldown:SetCountdownFormatter(countdown)
    b.edge = CreateFrame("Frame", nil, b)
    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
    b.edge:SetBackdrop(EDGE)
    b.edge:SetBackdropBorderColor(0.7, 0.7, 0.7)
    b:RegisterForDrag("LeftButton", "RightButton")
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b.key = ""
    FB.Style(b)
    FB.buttons[#FB.buttons + 1] = b
    return b
end

-- An empty button shows while the bar shows empty buttons, or while the
-- cursor holds something to drop on it (CURSOR_CHANGED, in Bars.lua).
function FB.Grid(b)
    if b.has or FB.dragging or b.bar.cfg.showEmpty then b:Show() else b:Hide() end
end

function FB.Icon(b, texture)
    b.has = texture ~= nil
    b.icon:SetTexture(texture)
    if texture then b.icon:Show() else b.icon:Hide(); FB.Cooldown(b, 0, 0, 0) end
    b:SetNormalTexture(texture and "Interface\\Buttons\\UI-Quickslot2" or "Interface\\Buttons\\UI-Quickslot")
    b.normal:SetAlpha(db.floating and 0 or 1)
    FB.Grid(b)
end

-- Writes only a change: the free buttons hear every power tick.
function FB.Usable(b, usable, noMana)
    local state = usable and 1 or noMana and 2 or 3
    if b.usable == state then return end
    b.usable = state
    if usable then b.icon:SetVertexColor(1, 1, 1)
    elseif noMana then b.icon:SetVertexColor(0.5, 0.5, 1)
    else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
end

-- inRange: false is out of range (a red key, or a red dot without a key);
-- true or nil (no check) is grey.
function FB.Range(b, inRange)
    if b.inRange == inRange and b.painted == b.key then return end
    b.inRange, b.painted = inRange, b.key
    if b.key ~= "" then b.hotkey:SetText(b.key)
    elseif inRange == false then b.hotkey:SetText(RANGE_INDICATOR)
    else b.hotkey:SetText("") end
    if inRange == false then b.hotkey:SetVertexColor(1, 0.1, 0.1) else b.hotkey:SetVertexColor(0.6, 0.6, 0.6) end
end

function FB.SetKey(b, key)
    b.key = key and GetBindingText(key, "KEY_", 1) or ""
    FB.Range(b, b.inRange)
end

function FB.Cooldown(b, start, duration, enable)
    if start > 0 and duration > 0 and enable > 0 then
        if b.cdStart ~= start or b.cdDuration ~= duration then
            b.cdStart, b.cdDuration = start, duration
            b.cooldown:SetCooldown(start, duration)
        end
    elseif b.cdStart then
        b.cdStart, b.cdDuration = nil, nil
        b.cooldown:Clear()
    end
end

-- Auto-attack and auto-shot: one timer for every flashing button, only while one flashes.
local flashing, ticker = {}, nil
local function Blink()
    for b in pairs(flashing) do
        if b.flash:IsShown() then b.flash:Hide() else b.flash:Show() end
    end
end

function FB.Flash(b, on)
    if on then
        flashing[b] = true
        if not ticker then ticker = C_Timer.NewTicker(0.4, Blink) end -- ATTACK_BUTTON_FLASH_TIME
    elseif flashing[b] then
        flashing[b] = nil
        b.flash:Hide()
        if next(flashing) == nil then ticker:Cancel(); ticker = nil end
    end
end

-- A worn item: the stock green border (ActionButton_Update).
function FB.Equipped(b, worn)
    if worn then b.border:SetVertexColor(0, 1, 0, 0.35); b.border:Show() else b.border:Hide() end
end

function FB.Redraw()
    for _, b in ipairs(FB.buttons) do b:Draw() end
end
