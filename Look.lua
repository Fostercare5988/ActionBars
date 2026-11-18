-- ActionBars: the stock bars give way to ours, and the look switches.
-- MainMenuBar stays, emptied of its buttons, under our main bar: it holds the
-- XP and reputation bars, the bags and menu, and the pet and stance bars
-- (FrameXML MainMenuBar.xml, PetActionBarFrame.xml:70, BonusActionBarFrame.xml:203).
local _, FB = ...
if not FB.Load then return end

local db = ActionBarsDB
local hidden = FB.hidden

-- The stock action buttons stop listening, so none of their redraws runs, and
-- sit under a hidden frame, whatever MultiActionBar_Update shows.
for _, prefix in ipairs({ "Action", "BonusAction", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBarRight" }) do
    for i = 1, 12 do
        local button = _G[prefix .. "Button" .. i]
        button:UnregisterAllEvents()
        button:SetParent(hidden)
    end
end
for _, frame in ipairs({ BonusActionBarFrame, MultiBarBottomLeft, MultiBarBottomRight, MultiBarLeft, MultiBarRight }) do
    frame:UnregisterAllEvents()
    frame:SetParent(hidden)
end

local main = FB.byKey.main.holder
MainMenuBar:EnableMouse(false) -- its old rectangle would catch clicks
MainMenuBar:ClearAllPoints()
MainMenuBar:SetPoint("BOTTOM", main, "TOP", 0, -38) -- its XP band, the top 13 of 53, above our buttons

-- Floating Actionbar: the bar art and the XP bars' frames.
local art = {}
for i = 0, 3 do
    for _, name in ipairs({ "MainMenuBarTexture", "MainMenuXPBarTexture", "ReputationWatchBarTexture",
        "ReputationXPBarTexture", "MainMenuMaxLevelBar" }) do
        art[#art + 1] = _G[name .. i]
    end
end

-- Reduced Actionbar Size: the bags, the menu and the page arrows.
local menu = {} -- frame -> its own parent
for _, name in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton",
    "HelpMicroButton", "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton", "MainMenuBarPerformanceBarFrame",
    "ActionBarUpButton", "ActionBarDownButton" }) do
    local frame = _G[name]
    menu[frame] = frame:GetParent()
end
local WIDE = { MainMenuBar, MainMenuExpBar, MainMenuBarMaxLevelBar, ReputationWatchBar, ReputationWatchStatusBar }

-- Each switch applies at once (the page calls this on a change, Bars.lua on the main bar's layout).
function FB.Look()
    local alpha = db.floating and 0 or 1
    for _, texture in ipairs(art) do texture:SetAlpha(alpha) end
    alpha = db.hideGryphons and 0 or 1
    MainMenuBarLeftEndCap:SetAlpha(alpha)
    MainMenuBarRightEndCap:SetAlpha(alpha)
    for frame, parent in pairs(menu) do frame:SetParent(db.shortMain and hidden or parent) end
    MainMenuBarPageNumber:SetAlpha(db.shortMain and 0 or 1)
    local width = db.shortMain and main:GetWidth() * main:GetScale() or 1024
    for _, frame in ipairs(WIDE) do frame:SetWidth(width) end
    ShapeshiftBarFrame:SetParent(db.hideStanceBar and hidden or MainMenuBar)
    for _, b in ipairs(FB.buttons) do FB.Style(b) end
end

-- Countdown numbers on every stock sweep: the pet and stance buttons, bags, the
-- spellbook, the character sheet, and other addons' (Bagnon, GearRack). They are
-- 1.12 Models without numbers: each gets a native Cooldown that draws only the
-- numbers, by the player's countdownForCooldowns (the Cooldown section). FrameXML
-- Cooldown.lua: CooldownFrame_SetTimer shows the Model for a running cooldown
-- and hides it otherwise; the numbers hide with it.
local function Numbers(model)
    if model:GetObjectType() == "Cooldown" then return false end -- counts down by itself
    local numbers = CreateFrame("Cooldown", nil, model)
    numbers:SetAllPoints(model)
    numbers:SetDrawSwipe(false)
    numbers:SetDrawBling(false)
    numbers:SetCountdownFormatter(FB.Countdown)
    return numbers
end

-- Made at a sweep's first running cooldown: a bag clears every slot when it opens.
hooksecurefunc("CooldownFrame_SetTimer", function(model, start, duration, enable)
    if not model then return end
    local numbers = model.fbNumbers
    if start > 0 and duration > 0 and enable > 0 then
        if numbers == nil then numbers = Numbers(model); model.fbNumbers = numbers end
        if numbers and (numbers.start ~= start or numbers.duration ~= duration) then
            numbers.start, numbers.duration = start, duration
            numbers:SetCooldown(start, duration)
        end
    elseif numbers and numbers.start then
        numbers.start, numbers.duration = nil, nil
        numbers:Clear()
    end
end)
