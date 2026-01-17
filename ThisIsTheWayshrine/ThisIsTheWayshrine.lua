--Name Space
ThisIsTheWayshrine = {}
local TITW = ThisIsTheWayshrine

--Basic Info
TITW.Name = "ThisIsTheWayshrine"

--Setting
TITW.Default = {
  CV = true,
  enabledZones = {},
}

TITW.showing = false
TITW.hookLock = false

TITW.zoneNameToId = {}
TITW.zoneIds = {}
TITW.controlList = {}

local function setupNoop()
  return
end

function TITW.BuildZoneNameCache()
    ZO_ClearTable(TITW.zoneNameToId)

    local numZones = GetNumZones()
    for zoneIndex = 1, numZones do
        local zoneId = GetZoneId(zoneIndex)
        if zoneId then
            local zoneName = GetZoneNameById(zoneId)
            if zoneName and zoneName ~= "" then
                TITW.zoneNameToId[zo_strlower(zoneName)] = zoneId
                TITW.zoneIds[zoneId] = zoneName
            end
        end
    end
end

function TITW:GetZoneIdFromZoneName(targetName)
    return self.zoneNameToId[zo_strlower(targetName)]
end

function TITW:enumerateWayshrines(zoneIdex, providedZoneId)
  if providedZoneId == nil then
    if zoneIdex then
      providedZoneId = ZO_ExplorationUtils_GetParentZoneIdByZoneIndex(zoneIdex)
    else
      return {enabled = false, totalWayshrines = 0, knownWayshrines = 0}
    end
  end
  local totalWayshrines = 0
  local knownWayshrines = 0
  for i = 1, GetNumFastTravelNodes() do
    local known, name, normalizedX, normalizedY, icon, glowIcon, poiType, isLocatedInCurrentMap, linkedCollectibleIsLocked =
        GetFastTravelNodeInfo(i)

    if poiType == POI_TYPE_WAYSHRINE then
      local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(i)
      local checkZId = ZO_ExplorationUtils_GetParentZoneIdByZoneIndex(zoneIndex)
      if checkZId == providedZoneId and not linkedCollectibleIsLocked then
        totalWayshrines = totalWayshrines + 1
        if known then
          knownWayshrines = tonumber(knownWayshrines) + 2^(totalWayshrines-1)
        end
      end
    end
  end
  return {enabled = true, totalWayshrines = totalWayshrines, knownWayshrines = knownWayshrines}
end

function TITW:EnsureGamepadCheckmark(control, zoneId)
    if zoneId == nil then return end
    local controlName = "check_"..zoneId
    if TITW.controlList[controlName] and TITW.controlList[controlName].titwCheckmark then return end

    if not GetControl(controlName) then
      local check = WINDOW_MANAGER:CreateControl(controlName, control, CT_TEXTURE)

      check:SetDimensions(30, 30)
      check:SetAnchor(LEFT, control, LEFT, 40, 0)
      check:SetHidden(true)
      check:SetTexture("/esoui/art/miscellaneous/check.dds")
      TITW.controlList[controlName] = check
    else
      TITW.controlList[controlName] = GetControl(controlName)
    end
    local enabled = self.SV.enabledZones[zoneId] ~= nil and self.SV.enabledZones[zoneId].enabled
    TITW.controlList[controlName]:SetHidden(not enabled)
end

function TITW:UpdateGamepadZoneCheckmark(control, data)
    -- Ignore category headers
    if data and data.isHeader then
        if TITW.controlList[controlName].titwCheckmark then
            TITW.controlList[controlName].titwCheckmark:SetHidden(true)
        end
        return
    end
    local list = GAMEPAD_WORLD_MAP_LOCATIONS.list
    if not list then
      return
    end
    local locationName = list.selectedData.locationName
    local zoneId = TITW:GetZoneIdFromZoneName(locationName)
    self:EnsureGamepadCheckmark(control, zoneId)
end


function TITW:controls()
  local addParams = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(CSA_CATEGORY_SMALL_TEXT, SOUNDS.MAP_PING)
  addParams:SetCSAType(CENTER_SCREEN_ANNOUNCE_TYPE_POI_DISCOVERED)
  local removeParams = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(CSA_CATEGORY_SMALL_TEXT, SOUNDS.MAP_PING_REMOVE)
  removeParams:SetCSAType(CENTER_SCREEN_ANNOUNCE_TYPE_POI_DISCOVERED)
  return {
    ToggleDesiredZone = {
      alignment = KEYBIND_STRIP_ALIGN_LEFT,
      {
          name = self.Lang.TOGGLE_ALL_ZONES,
          keybind = "UI_SHORTCUT_TERTIARY",
          callback = function()

            for zoneId, zoneName in pairs(TITW.zoneIds) do
                if ZO_ZoneStories_Shared.IsZoneCollectibleUnlocked(zoneId) then
                  if self.SV.enabledZones[zoneId] == nil then
                    self.SV.enabledZones[zoneId] = TITW:enumerateWayshrines(nil, zoneId)
                  else
                    self.SV.enabledZones[zoneId].enabled = not self.SV.enabledZones[zoneId].enabled
                  end
                end
            end
            GAMEPAD_WORLD_MAP_LOCATIONS.list:RefreshVisible()
            addParams:SetText(self.Lang.ALL_ZONES_TOGGLED)
            CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(addParams)
          end,
          visible = function()
            return true
          end
        },
      {
          name = self.Lang.TOGGLE_ZONE_DISCOVERY,
          keybind = "UI_SHORTCUT_QUATERNARY",
          callback = function()
            local list = GAMEPAD_WORLD_MAP_LOCATIONS.list
            if not list then
              return
            end
            local locationName = list.selectedData.locationName
            local zoneId = TITW:GetZoneIdFromZoneName(locationName)
            if TITW.SV.enabledZones[zoneId] then
              TITW.SV.enabledZones[zoneId] = nil
              removeParams:SetText(self.Lang.ZONE_REMOVED.." - "..locationName)
              CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(removeParams)
            else
              TITW.SV.enabledZones[zoneId] = TITW:enumerateWayshrines(nil, zoneId)
              addParams:SetText(self.Lang.ZONE_ADDED.." - "..locationName)
              CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(addParams)
            end
            GAMEPAD_WORLD_MAP_LOCATIONS.list:RefreshVisible()
          end,
          visible = function()
            return true
          end
        },
      }
  }
end

--Account/Character Setting
function TITW.SwitchSV()
  if TITW.CV.CV then
    TITW.SV = TITW.CV
  else
    TITW.SV = TITW.AV
  end
end

local function isKeyInTable(table, element)
  for k, v in pairs(table) do
    if element == k then
      return true
    end
  end
  return false
end

local function setupZoneDisplay(self, control, data)
  TITW:UpdateGamepadZoneCheckmark(control, data)
  TITW.hookLock = setupNoop
end

function TITW.addUI()
  GAMEPAD_WORLD_MAP_LOCATIONS_FRAGMENT:RegisterCallback(
    "StateChange",
    function(_, newState)
      if newState == SCENE_SHOWING then
        TITW.hookLock = setupZoneDisplay
        ZO_PreHook(GAMEPAD_WORLD_MAP_LOCATIONS, "SetupLocation", TITW.hookLock)
        KEYBIND_STRIP:AddKeybindButtonGroup(TITW:controls().ToggleDesiredZone)
      elseif newState == SCENE_HIDDEN then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(TITW:controls().ToggleDesiredZone)
      end
  end) -- end inner register callback
end -- end function

function TITW:Initialize()
  zo_callLater(self.BuildZoneNameCache, 1500)
  zo_callLater(self.addUI, 1800)
end

--When Loaded
local function OnAddOnLoaded(eventCode, addonName)
  if addonName ~= TITW.Name then return end
	EVENT_MANAGER:UnregisterForEvent(TITW.Name, EVENT_ADD_ON_LOADED)

  --Get Account/Character Setting
  TITW.AV = ZO_SavedVars:NewAccountWide("ThisIsTheWayshrine_Vars", 1, nil, TITW.Default)
  TITW.CV = ZO_SavedVars:NewCharacterIdSettings("ThisIsTheWayshrine_Vars", 1, nil, TITW.Default)
  TITW.SwitchSV()
  TITW:Initialize()

end

local function travelToDesiredZone(zone)

end

local function TITW_Event_Player_Activated(event, isA)
	EVENT_MANAGER:UnregisterForEvent("TITW_PLAYER_ACTIVATED", EVENT_PLAYER_ACTIVATED)
	local currentZoneIndex = GetUnitZoneIndex("player")
	if TITW.SV.enabledZones[currentZoneIndex] and next(TITW.SV.enabledZones[currentZoneIndex]) and TITW.SV.enabledZones[currentZoneIndex][knownWayshrines] then
    local prevWayshrines = TITW.SV.enabledZones[currentZoneIndex][knownWayshrines]
    local currentWayshrineStats = TITW:enumerateWayshrines(currentZoneIndex)
    if currentWayshrineStats[knownWayshrines] > prevWayshrines then
      d(TITW.Lang.DISCOVERED_NEW)
    end
    if currentWayshrineStats[knownWayshrines] == 2 ^ currentWayshrineStats[totalWayshrines] then
      d(TITW.Lang.DISCOVERED_ALL)
    end
	end
end

local function TITW_Event_Social_Jump_Activated(event, isA)
  d(event.zoneId)
  if isKeyInTable(TITW.CV.enabledZones, event.zoneId) then
    d("Would travel to zone "..event.zoneId)
    d(GetZoneNameById(event.zoneId))
  end
end

-- Start Here
EVENT_MANAGER:RegisterForEvent(TITW.Name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
EVENT_MANAGER:RegisterForEvent("TITW_PLAYER_ACTIVATED", EVENT_PLAYER_ACTIVATED, TITW_Event_Player_Activated)
EVENT_MANAGER:RegisterForEvent("TITW_GUILDEE_JUMPED", EVENT_GUILD_MEMBER_ZONE_CHANGED, TITW_Event_Social_Jump_Activated)
