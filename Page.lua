-- The FostercareBars page in ClassicAPI's Settings window (AddOn Options, or
-- /fbars): the profiles, the extra bars, the look; and a Layout page per bar.
local _, FB = ...
if not FB.Load then return end -- no ClassicAPI: Profiles.lua said so

local db = FostercareBarsDB
local Bool, Number = Settings.VarType.Boolean, Settings.VarType.Number

local chosen = "" -- the profile the three buttons act on; "" while there is none
local category, profile

-- After a save or a delete: show that profile, or the first one.
local function Choose(name)
    chosen = name or FB.Names()[1] or ""
    if profile then profile:NotifyUpdate() end
end

local function Save(name)
    local saved = FB.Save(name)
    if saved then Choose(saved) end
    return saved
end

StaticPopupDialogs.FOSTERCAREBARS_NEW = {
    text = "Save the buttons on your action bars as:",
    button1 = SAVE, button2 = CANCEL,
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function() _G[this:GetName() .. "EditBox"]:SetFocus() end,
    -- Returning true keeps the popup open, so an empty name can be typed again.
    OnAccept = function() return not Save(_G[this:GetParent():GetName() .. "EditBox"]:GetText()) end,
    EditBoxOnEnterPressed = function() if Save(this:GetText()) then this:GetParent():Hide() end end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
}

StaticPopupDialogs.FOSTERCAREBARS_DELETE = {
    text = "Delete the profile \"%s\"?",
    button1 = YES, button2 = NO,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(name) if FB.Delete(name) then Choose() end end,
}

SettingsRegistrar:AddRegistrant(function()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("FostercareBars")
    chosen = FB.Names()[1] or ""
    -- Not saved: the page only points at a profile. Defaults leaves it.
    local function Get() return chosen end
    profile = Settings.RegisterProxySetting(category, "FostercareBars_Profile", Settings.VarType.String,
        "Profile", Get, Get, function(name) chosen = name end)
    local list = Settings.CreateDropdown(category, profile, function()
        local choices = Settings.CreateControlTextContainer()
        for _, name in ipairs(FB.Names()) do choices:Add(name, name) end
        if chosen == "" then choices:Add("", "No profiles yet") end
        return choices:GetData()
    end, "The profile the three buttons below act on.")
    local function Picked() return chosen ~= "" end
    for _, row in ipairs({
        CreateSettingsButtonInitializer("Load", "Load", function() FB.Load(chosen) end,
            "Put this profile's buttons on your action bars.", false),
        CreateSettingsButtonInitializer("Save over it", "Save", function() Save(chosen) end,
            "Replace this profile with the buttons on your bars now.", false),
        CreateSettingsButtonInitializer("Delete", "Delete",
            function() StaticPopup_Show("FOSTERCAREBARS_DELETE", chosen, nil, chosen) end,
            "Delete this profile. You are asked first.", false),
    }) do
        row:SetParentInitializer(list, Picked)
        layout:AddInitializer(row)
    end
    layout:AddInitializer(CreateSettingsButtonInitializer("New profile", "Save bars as...",
        function() StaticPopup_Show("FOSTERCAREBARS_NEW") end,
        "Save the buttons on your bars under a new name.", true))

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Bars"))
    local function Slider(cat, variable, key, tbl, name, default, low, high, step, tooltip, changed)
        local setting = Settings.RegisterAddOnSetting(cat, variable, key, tbl, Number, name, default)
        local options = Settings.CreateSliderOptions(low, high, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        setting:SetValueChangedCallback(changed)
        return Settings.CreateSlider(cat, setting, options, tooltip)
    end
    local function Checkbox(cat, variable, key, tbl, name, default, tooltip, changed)
        local setting = Settings.RegisterAddOnSetting(cat, variable, key, tbl, Bool, name, default)
        setting:SetValueChangedCallback(changed)
        return Settings.CreateCheckbox(cat, setting, tooltip)
    end
    Slider(category, "FostercareBars_extraBars", "extraBars", db, "Extra bars", FB.DEFAULTS.extraBars,
        1, FB.MAX_EXTRA, 1, "How many extra bars. The first use the action slots your class does not page to; "
        .. "the rest hold spells, items, macros and sets of their own.", FB.LayoutAll)
    layout:AddInitializer(CreateSettingsButtonInitializer("Move bars", "Move bars", FB.Move,
        "Drag the bars where you want them. Press again to lock them.", true))
    for _, switch in ipairs({
        { "hideGryphons", "Hide Gryphons", "No gryphons at the ends of the main bar." },
        { "floating", "Floating Actionbar", "No bar art: buttons with a thin frame, flat XP and reputation bars." },
        { "shortMain", "Reduced Actionbar Size", "No bag and menu buttons; the XP bar as wide as the main bar." },
        { "reagents", "Reagent Counter", "How many casts your reagents allow, on spells that use them." },
        { "hideStanceBar", "Hide Stealth / Stance Bar", "No stance, form or stealth bar." },
    }) do
        local key = switch[1]
        Checkbox(category, "FostercareBars_" .. key, key, db, switch[2], FB.DEFAULTS[key], switch[3], function()
            FB.Look()
            FB.Redraw()
        end)
    end
    Settings.RegisterAddOnCategory(category)

    -- Layout: a section per bar; an extra bar's rows show while the bar exists.
    local sub, rows = Settings.RegisterVerticalLayoutSubcategory(category, "Layout")
    for _, bar in ipairs(FB.bars) do
        local function Exists() return not bar.extra or bar.extra <= db.extraBars end
        local function Changed() FB.Layout(bar) end
        local cfg, prefix = bar.cfg, "FostercareBars_" .. bar.key .. "_"
        local header = CreateSettingsListSectionHeaderInitializer(bar.name)
        rows:AddInitializer(header)
        local list = { header,
            Checkbox(sub, prefix .. "shown", "shown", cfg, "Shown", FB.LayoutDefault(bar, "shown"),
                "Show this bar.", Changed),
            Slider(sub, prefix .. "scale", "scale", cfg, "Size", FB.LayoutDefault(bar, "scale"), 0.5, 2, 0.05,
                "The size of the buttons.", Changed),
            Slider(sub, prefix .. "columns", "columns", cfg, "Buttons per row", FB.LayoutDefault(bar, "columns"),
                1, 12, 1, "How many buttons in a row.", Changed),
            Slider(sub, prefix .. "spacing", "spacing", cfg, "Spacing", FB.LayoutDefault(bar, "spacing"), 0, 20, 1,
                "The gap between the buttons.", Changed),
            Checkbox(sub, prefix .. "showEmpty", "showEmpty", cfg, "Show empty", FB.LayoutDefault(bar, "showEmpty"),
                "Show the buttons that hold nothing.", Changed),
        }
        bar.placed = Settings.RegisterProxySetting(sub, prefix .. "placed", Bool, "Placed by hand", false,
            function() return bar.holder:IsUserPlaced() and true or false end,
            function(placed) FB.SetPlaced(bar, placed) end)
        list[#list + 1] = Settings.CreateCheckbox(sub, bar.placed,
            "On after you drag the bar with Move bars. Turn it off to put the bar back in its own spot.")
        for _, row in ipairs(list) do row:AddShownPredicate(Exists) end
    end
end)

SLASH_FOSTERCAREBARS1 = "/fbars"
SlashCmdList.FOSTERCAREBARS = function()
    if category then Settings.OpenToCategory(category:GetID()) end
end
