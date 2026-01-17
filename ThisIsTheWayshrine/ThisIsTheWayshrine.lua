--Name Space
ThisIsTheWayshrine = {}
local TITW = ThisIsTheWayshrine

--Basic Info
TITW.Name = "ThisIsTheWayshrine"

--Setting
TITW.Default = {
  CV = false,
  enabledZones = {},
}

TITW.showing = false
TITW.hookLock = false

local function setupNoop()
  return
end

function TITW:enumerateWayshrines(zoneIdex)
  local providedZoneId = ZO_ExplorationUtils_GetParentZoneIdByZoneIndex(zoneIdex)
  local totalWayshrines = 0
  local knownWayshrines = 0
  for i = 1, GetNumFastTravelNodes() do
    local known, name, normalizedX, normalizedY, icon, glowIcon, poiType, isLocatedInCurrentMap, linkedCollectibleIsLocked =
        GetFastTravelNodeInfo(i)

    if poiType == POI_TYPE_WAYSHRINE then
      local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(i)
      local checkZId = ZO_ExplorationUtils_GetParentZoneIdByZoneIndex(zoneIndex)
      if checkZId == providedZoneId then
        totalWayshrines = totalWayshrines + 1
        if known then
          knownWayshrines = tonumber(knownWayshrines) + 2^(totalWayshrines-1)
        end
      end
    end
  end
  return {totalWayshrines = totalWayshrines, knownWayshrines = knownWayshrines}
end


function TITW:EnsureGamepadCheckmark(control)
    if control.titwCheckmark then return end

    local check = WINDOW_MANAGER:CreateControl(nil, control, CT_TEXTURE)

    check:SetDimensions(20, 20)
    check:SetAnchor(LEFT, control, LEFT, 12, 0)
    check:SetTexture("/esoui/art/miscellaneous/check.dds")
    check:SetHidden(true)

    control.titwCheckmark = check

    -- Shift the label so it doesn't overlap
    local label = control.label
    if label then
        label:ClearAnchors()
        label:SetAnchor(LEFT, control, LEFT, 44, 0)
    end
end

function TITW:UpdateGamepadZoneCheckmark(control, data)
    -- Ignore category headers
    if data and data.isHeader then
        if control.titwCheckmark then
            control.titwCheckmark:SetHidden(true)
        end
        return
    end

    self:EnsureGamepadCheckmark(control)

    local enabled = self.SV.enabledZones[data.zoneId] ~= nil
    control.titwCheckmark:SetHidden(not enabled)
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
            if not GAMEPAD_WORLD_MAP_LOCATIONS or not GAMEPAD_WORLD_MAP_LOCATIONS.list then
                return
            end

            local list = GAMEPAD_WORLD_MAP_LOCATIONS.list
            local dataList = ZO_ScrollList_GetDataList(list)

            for _, entry in ipairs(dataList) do
                local data = entry.data

                -- Skip category headers
                if not data.isHeader then
                    -- Unlocked zones are not locked
                    if not data.isLocked and data.zoneId then
                        self.SV.enabledZones[data.zoneId] = true
                        GAMEPAD_WORLD_MAP_LOCATIONS.list:RefreshVisible()
                    end
                end
            end
            addParams:SetText(self.Lang.ALL_ZONES_TOGGLED)
            CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(addParams)
            CENTER_SCREEN_ANNOUNCE:DisplayMessage(addParams)
          end,
          visible = function()
            return true
          end
        },
      {
          name = self.Lang.TOGGLE_ZONE_DISCOVERY,
          keybind = "UI_SHORTCUT_QUATERNARY",
          callback = function()
            if TITW.SV.enabledZones[GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.index] then
              TITW.SV.enabledZones[GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.index] = nil
              addParams:SetText(self.Lang.ZONE_ADDED.." - "..GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.text)
              CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(addParams)
              CENTER_SCREEN_ANNOUNCE:DisplayMessage(addParams)
            elseif GAMEPAD_WORLD_MAP_LOCATIONS.selectedData and GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.index then
              TITW.SV.enabledZones[GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.index] = TITW:enumerateWayshrines(GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.index)
              removeParams:SetText(self.Lang.ZONE_REMOVED.." - "..GAMEPAD_WORLD_MAP_LOCATIONS.selectedData.text)
              CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(removeParams)
              CENTER_SCREEN_ANNOUNCE:DisplayMessage(removeParams)
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

local function addZoneHook()
  ZO_PreHook(GAMEPAD_WORLD_MAP_LOCATIONS, "SetupZone", TITW.hookLock)
end

function TITW:addUI()
--   world_map_scene = SCENE_MANAGER:GetScene("gamepad_worldMap")
--   SCENE_MANAGER:RegisterCallback("SceneStateChanged", function(scene, newState)
--     local sceneName = scene:GetName()
--     if sceneName == "gamepad_worldMap" and newState == SCENE_SHOWING then
      TITW.hookLock = setupZoneDisplay
      GAMEPAD_WORLD_MAP_LOCATIONS_FRAGMENT:RegisterCallback(
        "StateChange",
        function(_, newState)
          if newState == SCENE_SHOWING then
            addZoneHook()
            KEYBIND_STRIP:AddKeybindButtonGroup(TITW:controls().ToggleDesiredZone)
          elseif newState == SCENE_HIDDEN then
            KEYBIND_STRIP:RemoveKeybindButtonGroup(TITW:controls().ToggleDesiredZone)
          end
      end) -- end inner register callback
--     end -- end if sceneName
--   end) -- end outer register callback
end -- end function

function TITW:Initialize()
  TITW:addUI()
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
