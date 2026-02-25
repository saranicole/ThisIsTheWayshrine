-- ============================================================
--  AddonSettingsFramework.lua  (Console / Gamepad)
--  Drop-in settings framework for Elder Scrolls Online addons
--  targeting the CONSOLE / GAMEPAD UI layer.
--
--  NO XML FILE REQUIRED - uses only ZOS stock virtual templates
--  and the native GAMEPAD_TEXT_INPUT dialog.
--
--  UI system:  ZO_Gamepad parametric scroll list
--  SavedVars:  caller passes in their own pre-loaded SV table
--  Activation: caller calls registration:Show() / :Hide() / :Toggle()
--
--  SUPPORTED CONTROL TYPES:
--    checkbox     – on/off boolean toggle
--    slider       – numeric value between min and max
--    dropdown     – pick one value from a list
--    colorpicker  – RGBA color stored as { r, g, b, a }
--    textbox      – freeform string via native gamepad keyboard dialog
--    iconchooser  – pick one texture path from a list
--    button       – fire a callback (no saved value)
--    header       – non-interactive section label
--    divider      – visual separator
--
--  ── QUICK START ──────────────────────────────────────────────
--
--  1. Add this file BEFORE your main addon file in your .txt manifest.
--
--  2. In EVENT_ADD_ON_LOADED, after your SV table is ready:
--
--        MySettings = AddonSettings:Register({
--            name      = "My Addon",
--            savedVars = MySavedVarsTable,
--        })
--
--        MySettings:AddOption({ type="header",   name="General" })
--        MySettings:AddOption({ type="checkbox", name="Enabled",
--            key="enabled", default=true })
--        MySettings:AddOption({ type="slider",   name="Scale",
--            key="scale", min=50, max=200, step=5, default=100 })
--
--  3. Open the menu from a keybind or button in your addon:
--        MySettings:Show()
--
--  ── DYNAMIC API SUMMARY ──────────────────────────────────────
--
--    :AddOption(def [, afterName])
--        Add a control. Optionally insert after a named control.
--        Returns def for later reference.
--
--    :RemoveOption(nameOrDef)
--        Remove a control by name string or stored def reference.
--
--    :UpdateOption(nameOrDef, changes)
--        Merge changes into an existing def and refresh live.
--
--    :GetOption(name)
--        Return the def table for the first control with that name.
--
--    :Show() / :Hide() / :Toggle()
--        Control visibility of the settings scene.
--
-- ============================================================

AddonSettings = AddonSettings or {}

-- ─────────────────────────────────────────────────────────────
--  CONSTANTS
--  All virtual template names reference ZOS stock templates that
--  ship with ESO's base UI - no addon XML required.
-- ─────────────────────────────────────────────────────────────

local SCENE_NAME_PREFIX = "AddonSettingsFramework_Scene_"
local LIST_TEMPLATE     = "ZO_GamepadMenuEntryTemplate"
local HEADER_TEMPLATE   = "ZO_GamepadMenuEntryHeaderTemplate"
local DIVIDER_TEMPLATE  = "ZO_GamepadMenuEntryFullWidthHeaderTemplate"

-- ZOS's own gamepad text input dialog - registered by ZOS in their
-- own XML/Lua, present on all platforms including console.
local ZOS_TEXT_INPUT_DIALOG = "GAMEPAD_TEXT_INPUT"

-- ─────────────────────────────────────────────────────────────
--  INTERNAL HELPERS
-- ─────────────────────────────────────────────────────────────

local function ApplyDefaults(sv, defaults)
    for k, v in pairs(defaults) do
        if sv[k] == nil then
            if type(v) == "table" then
                sv[k] = {}
                ApplyDefaults(sv[k], v)
            else
                sv[k] = v
            end
        end
    end
end

local function GetNested(tbl, path)
    local cur = tbl
    for part in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end

local function SetNested(tbl, path, value)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do
        table.insert(parts, part)
    end
    local cur = tbl
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(cur[part]) ~= "table" then cur[part] = {} end
        cur = cur[part]
    end
    cur[parts[#parts]] = value
end

local function SnapToStep(value, min, max, step)
    local snapped = math.floor((value - min) / step + 0.5) * step + min
    return math.max(min, math.min(max, snapped))
end

local function FmtNum(n)
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return tostring(n)
end

local function ApplyControlDefault(sv, ctrl)
    if ctrl.key ~= nil and ctrl.default ~= nil then
        if GetNested(sv, ctrl.key) == nil then
            SetNested(sv, ctrl.key, ctrl.default)
        end
    end
end

local function FindControl(controls, nameOrDef)
    if type(nameOrDef) == "table" then
        for i, ctrl in ipairs(controls) do
            if ctrl == nameOrDef then return i, ctrl end
        end
    elseif type(nameOrDef) == "string" then
        for i, ctrl in ipairs(controls) do
            if ctrl.name == nameOrDef then return i, ctrl end
        end
    end
    return nil, nil
end

-- ─────────────────────────────────────────────────────────────
--  NATIVE TEXT INPUT HELPER
--
--  Wraps ZOS's GAMEPAD_TEXT_INPUT dialog which is defined entirely
--  in ZOS's own code. Requires no addon XML on any platform.
--
--  Expected fields on the data table passed to the dialog:
--    title.text        – header string shown above the input field
--    defaultText       – pre-filled content
--    maxInputChars     – character limit
--    keyboardTitle     – label shown on the virtual keyboard (console)
--    finishedCallback  – function(text) fired on accept
--    cancelCallback    – function() fired on cancel / back
-- ─────────────────────────────────────────────────────────────

local function ShowTextInput(title, currentText, maxChars, onAccept, onCancel)
    local data = {
        title             = { text = title or "" },
        defaultText       = currentText or "",
        maxInputChars     = maxChars or 256,
        keyboardTitle     = title or "",
        finishedCallback  = function(text)
            if onAccept then onAccept(text) end
        end,
        cancelCallback    = function()
            if onCancel then onCancel() end
        end,
    }
    ZO_Dialogs_ShowGamepadDialog(ZOS_TEXT_INPUT_DIALOG, data)
end

-- ─────────────────────────────────────────────────────────────
--  COLOR INPUT HELPER
--
--  Preferred path: ZOS COLOR_PICKER (available on all platforms).
--  Fallback path:  three sequential GAMEPAD_TEXT_INPUT prompts for
--                  R, G, B channels (0-255 integers). No XML needed.
-- ─────────────────────────────────────────────────────────────

local function ShowColorInput(title, currentColor, onAccept)
    local c = currentColor or { r = 1, g = 1, b = 1, a = 1 }

    -- Preferred: ZOS native color picker
    if COLOR_PICKER then
        local pickFn = COLOR_PICKER.ShowGamepad or COLOR_PICKER.Show
        if pickFn then
            pickFn(COLOR_PICKER, function(r, g, b, a)
                onAccept({ r = r, g = g, b = b, a = a or 1 })
            end, c.r, c.g, c.b, c.a, title)
            return
        end
    end

    -- Fallback: sequential R -> G -> B prompts via GAMEPAD_TEXT_INPUT
    local r, g, b = c.r, c.g, c.b

    local function AskB()
        ShowTextInput(
            (title or "Color") .. " – Blue (0-255)",
            tostring(math.floor(b * 255)),
            3,
            function(text)
                b = math.max(0, math.min(255, tonumber(text) or 0)) / 255
                onAccept({ r = r, g = g, b = b, a = c.a or 1 })
            end
        )
    end

    local function AskG()
        ShowTextInput(
            (title or "Color") .. " – Green (0-255)",
            tostring(math.floor(g * 255)),
            3,
            function(text)
                g = math.max(0, math.min(255, tonumber(text) or 0)) / 255
                AskB()
            end
        )
    end

    ShowTextInput(
        (title or "Color") .. " – Red (0-255)",
        tostring(math.floor(r * 255)),
        3,
        function(text)
            r = math.max(0, math.min(255, tonumber(text) or 0)) / 255
            AskG()
        end
    )
end

-- ─────────────────────────────────────────────────────────────
--  ENTRY BUILDERS
--  Each returns a list of ZO_GamepadEntryData objects.
-- ─────────────────────────────────────────────────────────────

local EntryBuilders = {}

-- ── header ───────────────────────────────────────────────────
EntryBuilders["header"] = function(def, _sv, _reg)
    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry:SetHeader(def.name or "")
    entry.isInteractive = false
    entry.templateName  = HEADER_TEMPLATE
    return { entry }
end

-- ── divider ──────────────────────────────────────────────────
EntryBuilders["divider"] = function(_def, _sv, _reg)
    local entry = ZO_GamepadEntryData:New("", nil)
    entry.isInteractive = false
    entry.templateName  = DIVIDER_TEMPLATE
    return { entry }
end

-- ── checkbox ─────────────────────────────────────────────────
EntryBuilders["checkbox"] = function(def, sv, reg)
    local function GetVal()
        local v = GetNested(sv, def.key)
        return (v == nil) and def.default or v
    end
    local function GetSubLabel()
        return GetVal()
            and GetString(SI_CHECK_BUTTON_ON)
            or  GetString(SI_CHECK_BUTTON_OFF)
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = GetSubLabel()
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    entry.Activate = function()
        local newVal = not GetVal()
        SetNested(sv, def.key, newVal)
        entry.subLabel = GetSubLabel()
        reg:_RefreshList()
        if def.onChange then def.onChange(newVal) end
    end

    entry.OnDirectionalInput = function(_direction)
        entry.Activate()
    end

    return { entry }
end

-- ── slider ───────────────────────────────────────────────────
EntryBuilders["slider"] = function(def, sv, reg)
    local min  = def.min  or 0
    local max  = def.max  or 100
    local step = def.step or 1

    local function GetVal()
        local v = GetNested(sv, def.key)
        if v == nil then v = def.default or min end
        return SnapToStep(v, min, max, step)
    end
    local function GetSubLabel()
        return FmtNum(GetVal()) .. " / " .. FmtNum(max)
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = GetSubLabel()
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    local function ChangeBy(delta)
        local newVal = SnapToStep(GetVal() + delta, min, max, step)
        SetNested(sv, def.key, newVal)
        entry.subLabel = GetSubLabel()
        reg:_RefreshList()
        if def.onChange then def.onChange(newVal) end
    end

    entry.Activate           = function() ChangeBy(step) end
    entry.OnDirectionalInput = function(direction)
        if direction == MOVEMENT_CONTROLLER_DIRECTION_NEGATIVE then
            ChangeBy(-step)
        else
            ChangeBy(step)
        end
    end

    return { entry }
end

-- ── dropdown ─────────────────────────────────────────────────
EntryBuilders["dropdown"] = function(def, sv, reg)
    local choices = def.choices or {}

    local function GetVal()
        local v = GetNested(sv, def.key)
        if v == nil then v = def.default or choices[1] end
        return v
    end
    local function GetIndex()
        local cur = GetVal()
        for i, c in ipairs(choices) do
            if c == cur then return i end
        end
        return 1
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = tostring(GetVal())
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    local function CycleBy(delta)
        if #choices == 0 then return end
        local newIdx = ((GetIndex() - 1 + delta) % #choices) + 1
        local newVal = choices[newIdx]
        SetNested(sv, def.key, newVal)
        entry.subLabel = tostring(newVal)
        reg:_RefreshList()
        if def.onChange then def.onChange(newVal) end
    end

    entry.Activate           = function() CycleBy(1) end
    entry.OnDirectionalInput = function(direction)
        if direction == MOVEMENT_CONTROLLER_DIRECTION_NEGATIVE then
            CycleBy(-1)
        else
            CycleBy(1)
        end
    end

    return { entry }
end

-- ── colorpicker ───────────────────────────────────────────────
EntryBuilders["colorpicker"] = function(def, sv, reg)
    local function GetVal()
        local v = GetNested(sv, def.key)
        if v == nil then
            v = def.default or { r = 1, g = 1, b = 1, a = 1 }
            SetNested(sv, def.key, v)
        end
        return v
    end
    local function GetSubLabel()
        local c = GetVal()
        return string.format("R:%.0f G:%.0f B:%.0f",
            c.r * 255, c.g * 255, c.b * 255)
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = GetSubLabel()
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    entry.Activate = function()
        ShowColorInput(def.name, GetVal(), function(col)
            SetNested(sv, def.key, col)
            entry.subLabel = GetSubLabel()
            reg:_RefreshList()
            if def.onChange then def.onChange(col) end
        end)
    end

    return { entry }
end

-- ── textbox ───────────────────────────────────────────────────
EntryBuilders["textbox"] = function(def, sv, reg)
    local function GetVal()
        local v = GetNested(sv, def.key)
        return (v == nil) and (def.default or "") or v
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = tostring(GetVal())
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    entry.Activate = function()
        ShowTextInput(
            def.name,
            tostring(GetVal()),
            def.maxChars or 256,
            function(text)
                SetNested(sv, def.key, text)
                entry.subLabel = text
                reg:_RefreshList()
                if def.onChange then def.onChange(text) end
            end
        )
    end

    return { entry }
end

-- ── iconchooser ───────────────────────────────────────────────
EntryBuilders["iconchooser"] = function(def, sv, reg)
    local icons = def.icons or {}

    local function GetVal()
        local v = GetNested(sv, def.key)
        if v == nil then v = def.default or icons[1] or "" end
        return v
    end
    local function GetIndex()
        local cur = GetVal()
        for i, path in ipairs(icons) do
            if path == cur then return i end
        end
        return 1
    end
    local function ShortPath(p)
        return (p and p:match("([^/]+)%.%a+$")) or p or ""
    end

    local entry = ZO_GamepadEntryData:New(def.name or "", nil)
    entry.subLabel      = ShortPath(GetVal())
    entry.icon          = GetVal()
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    local function CycleBy(delta)
        if #icons == 0 then return end
        local newIdx = ((GetIndex() - 1 + delta) % #icons) + 1
        local newVal = icons[newIdx]
        SetNested(sv, def.key, newVal)
        entry.subLabel = ShortPath(newVal)
        entry.icon     = newVal
        reg:_RefreshList()
        if def.onChange then def.onChange(newVal) end
    end

    entry.Activate           = function() CycleBy(1) end
    entry.OnDirectionalInput = function(direction)
        if direction == MOVEMENT_CONTROLLER_DIRECTION_NEGATIVE then
            CycleBy(-1)
        else
            CycleBy(1)
        end
    end

    return { entry }
end

-- ── button ────────────────────────────────────────────────────
EntryBuilders["button"] = function(def, _sv, _reg)
    local entry = ZO_GamepadEntryData:New(def.name or "Button", nil)
    entry.subLabel      = def.subLabel or ""
    entry.tooltip       = def.tooltip
    entry.isInteractive = true
    entry.templateName  = LIST_TEMPLATE

    entry.Activate = function()
        if def.onClick then def.onClick() end
    end

    return { entry }
end

-- ─────────────────────────────────────────────────────────────
--  SETTINGS SCREEN CLASS
-- ─────────────────────────────────────────────────────────────

local SettingsScreen = ZO_Object:Subclass()

function SettingsScreen:New(registration)
    local obj = ZO_Object.New(self)
    obj:Initialize(registration)
    return obj
end

function SettingsScreen:Initialize(registration)
    self.registration = registration
    self.sceneName    = SCENE_NAME_PREFIX
        .. tostring(registration.name):gsub("[%s%p]", "_")

    -- ZO_GamepadParametricScrollScreen is a ZOS stock virtual template.
    -- It provides a full-screen control with a named child
    -- "ParametricScrollList" already set up. No addon XML needed.
    self.control = WINDOW_MANAGER:CreateControlFromVirtual(
        self.sceneName .. "_Control",
        GuiRoot,
        "ZO_GamepadParametricScrollScreen"
    )
    self.control:SetHidden(true)

    self.list = self.control:GetNamedChild("ParametricScrollList")
    if not self.list then
        self.list = ZO_GamepadVerticalParametricScrollList:New(self.control)
    end

    self:_SetupTemplates()
    self:_SetupScene()
    self:_SetupKeybinds()
end

function SettingsScreen:_SetupTemplates()
    -- All templates are ZOS stock, defined in ZOS's own XML.
    self.list:AddDataTemplate(
        LIST_TEMPLATE,
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction)

    self.list:AddDataTemplateWithHeader(
        LIST_TEMPLATE,
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction,
        nil,
        HEADER_TEMPLATE)

    self.list:AddDataTemplate(
        HEADER_TEMPLATE,
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction)

    self.list:AddDataTemplate(
        DIVIDER_TEMPLATE,
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction)
end

function SettingsScreen:_SetupScene()
    self.scene = ZO_Scene:New(self.sceneName, SCENE_MANAGER)
    local screen = self

    self.scene:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            screen.control:SetHidden(false)
            KEYBIND_STRIP:AddKeybindButtonGroup(screen.keybindStripDescriptor)
            screen.list:Activate()
            screen:_PopulateList()
        elseif newState == SCENE_HIDDEN then
            KEYBIND_STRIP:RemoveKeybindButtonGroup(screen.keybindStripDescriptor)
            screen.list:Deactivate()
            screen.control:SetHidden(true)
        end
    end)
end

function SettingsScreen:_SetupKeybinds()
    local screen = self
    self.keybindStripDescriptor = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
            name     = GetString(SI_GAMEPAD_BACK_OPTION),
            keybind  = "UI_SHORTCUT_NEGATIVE",
            callback = function() screen:Hide() end,
            sound    = SOUNDS.GAMEPAD_MENU_BACK,
        },
        {
            name     = GetString(SI_GAMEPAD_SELECT_OPTION),
            keybind  = "UI_SHORTCUT_PRIMARY",
            callback = function()
                local entry = screen.list:GetTargetData()
                if entry and entry.isInteractive and entry.Activate then
                    entry.Activate()
                end
            end,
            sound = SOUNDS.GAMEPAD_MENU_FORWARD,
        },
    }
end

function SettingsScreen:_PopulateList()
    self.list:Clear()
    local sv   = self.registration.savedVars
    local defs = self.registration.controls

    for _, def in ipairs(defs) do
        local builder = EntryBuilders[def.type]
        if builder then
            local entries = builder(def, sv, self.registration)
            for _, entry in ipairs(entries) do
                self.list:AddEntry(entry.templateName or LIST_TEMPLATE, entry)
            end
        else
            d(string.format("[AddonSettings] Unknown control type '%s' in '%s'",
                tostring(def.type), tostring(self.registration.name)))
        end
    end

    self.list:Commit()
end

function SettingsScreen:RefreshList()
    if SCENE_MANAGER:IsShowing(self.sceneName) then
        self:_PopulateList()
    end
end

function SettingsScreen:Show()
    self.control:SetHidden(false)
    SCENE_MANAGER:Push(self.sceneName)
end

function SettingsScreen:Hide()
    SCENE_MANAGER:HideCurrentScene()
end

function SettingsScreen:Toggle()
    if SCENE_MANAGER:IsShowing(self.sceneName) then
        self:Hide()
    else
        self:Show()
    end
end

-- ─────────────────────────────────────────────────────────────
--  PUBLIC API  –  AddonSettings:Register(config)
-- ─────────────────────────────────────────────────────────────

--[[
  ════════════════════════════════════════════════════════════
  AddonSettings:Register(config)  →  registration

  config fields:
    name       (string)   Display name shown as the panel header.
    savedVars  (table)    Your pre-loaded ZO_SavedVars table.
    controls   (table)    Optional seed list of control definitions.
                          Can be omitted and built via :AddOption().
    defaults   (table)    Optional top-level defaults shorthand.

  ════════════════════════════════════════════════════════════
  registration methods:

  ── Display ──────────────────────────────────────────────────
    :Show()     Push settings scene onto the gamepad scene stack.
    :Hide()     Pop / hide the current scene.
    :Toggle()   Show if hidden, hide if showing.

  ── Dynamic option management ────────────────────────────────
    :AddOption(def [, afterName])
        Add a new control. If afterName is given it is inserted
        immediately after the first control with that name;
        otherwise appended. Returns the def table.

    :RemoveOption(nameOrDef)
        Remove a control by name string or def table reference.

    :UpdateOption(nameOrDef, changes)
        Merge a changes table into an existing def and refresh.

    :GetOption(name)
        Return the def for the first control whose .name matches.

  ── Internal (used by entry builders) ────────────────────────
    :_RefreshList()   Repopulate list if scene is currently open.

  ════════════════════════════════════════════════════════════
  Control definition reference:

  Shared fields (all types):
    type      (string)    Required.
    name      (string)    Row label.
    key       (string)    Dot-path into savedVars e.g. "display.scale"
    default   (any)       Written once if key is absent in savedVars.
    tooltip   (string)    Shown in the gamepad tooltip area.
    onChange  (function)  Called with the new value after each change.

  Per-type extras:
    checkbox    – (none)
    slider      – min, max, step  (numbers)
    dropdown    – choices = { "A", "B", "C" }
    colorpicker – default = { r, g, b, a }  (channels 0–1)
    textbox     – maxChars (number, default 256)
    iconchooser – icons = { "/path/to/icon.dds", ... }
    button      – onClick (function), subLabel (string, optional)
    header      – (no key / default / onChange)
    divider     – (no fields needed)
  ════════════════════════════════════════════════════════════
--]]

function AddonSettings:Register(config)
    assert(type(config)           == "table", "[AddonSettings] config must be a table")
    assert(type(config.savedVars) == "table", "[AddonSettings] config.savedVars must be a table")

    config.controls = config.controls or {}
    assert(type(config.controls) == "table", "[AddonSettings] config.controls must be a table")

    if type(config.defaults) == "table" then
        ApplyDefaults(config.savedVars, config.defaults)
    end

    for _, ctrl in ipairs(config.controls) do
        ApplyControlDefault(config.savedVars, ctrl)
    end

    local registration = {
        name      = config.name or "Addon Settings",
        savedVars = config.savedVars,
        controls  = config.controls,
        _screen   = nil,
    }

    local function EnsureScreen()
        if not registration._screen then
            registration._screen = SettingsScreen:New(registration)
        end
    end

    -- ── Display ──────────────────────────────────────────────

    function registration:Show()
        EnsureScreen()
        self._screen:Show()
    end

    function registration:Hide()
        if self._screen then self._screen:Hide() end
    end

    function registration:Toggle()
        EnsureScreen()
        self._screen:Toggle()
    end

    -- Internal: called by entry builders after a value changes.
    function registration:_RefreshList()
        if self._screen then
            self._screen:RefreshList()
        end
    end

    -- ── Dynamic option management ─────────────────────────────

    function registration:AddOption(def, afterName)
        assert(type(def) == "table", "[AddonSettings] AddOption: def must be a table")
        assert(def.type  ~= nil,     "[AddonSettings] AddOption: def.type is required")

        ApplyControlDefault(self.savedVars, def)

        if afterName then
            local idx = FindControl(self.controls, afterName)
            if idx then
                table.insert(self.controls, idx + 1, def)
                self:_RefreshList()
                return def
            end
        end

        table.insert(self.controls, def)
        self:_RefreshList()
        return def
    end

    function registration:RemoveOption(nameOrDef)
        local idx = FindControl(self.controls, nameOrDef)
        if idx then
            table.remove(self.controls, idx)
            self:_RefreshList()
        else
            d(string.format("[AddonSettings] RemoveOption: '%s' not found in '%s'",
                tostring(nameOrDef), tostring(self.name)))
        end
    end

    function registration:UpdateOption(nameOrDef, changes)
        assert(type(changes) == "table", "[AddonSettings] UpdateOption: changes must be a table")
        local _, def = FindControl(self.controls, nameOrDef)
        if def then
            for k, v in pairs(changes) do
                def[k] = v
            end
            ApplyControlDefault(self.savedVars, def)
            self:_RefreshList()
        else
            d(string.format("[AddonSettings] UpdateOption: '%s' not found in '%s'",
                tostring(nameOrDef), tostring(self.name)))
        end
    end

    function registration:GetOption(name)
        local _, def = FindControl(self.controls, name)
        return def
    end

    return registration
end
