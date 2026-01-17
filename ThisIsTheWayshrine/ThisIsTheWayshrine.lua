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
TITW.toggle = false
TITW.selectAll = false

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

function TITW:Initialize()
  zo_callLater(self.BuildZoneNameCache, 1500)
  zo_callLater(self.BuildMenu, 1800)
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
