--Name Space
ThisIsTheWayshrine = {}
local TITW = ThisIsTheWayshrine

--Basic Info
TITW.Name = "ThisIsTheWayshrine"

--Setting
TITW.Default = {
  CV = true,
  enabledZones = {},
  enableJumping = false,
}

TITW.showing = false
TITW.hookLock = false

TITW.zoneNameToId = {}
TITW.zoneIds = {}
TITW.controlList = {}
TITW.toggle = false
TITW.selectAll = false
TITW.alreadyJumpedTo = {}
TITW.memberIndex = 1
TITW.guildIndex = 1

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

function TITW:GetZoneFullyDiscovered(zoneId)
  local zone = TITW.SV.enabledZones[zoneId]
  if zone and zone[totalWayshrines] and zone[knownWayshrines] then
    return zone[knownWayshrines] == 2 ^ zone[totalWayshrines]
  end
  return false
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

local function isZoneEnabled(table, element)
  for k, v in pairs(table) do
    if k == element and v.enabled then
      return v.enabled
    end
  end
  return false
end

function TITW:triggerJump(displayName, zoneId, memberIndex, guildIndex)
  JumpToGuildMember(displayName)
  TITW.alreadyJumpedTo[displayName] = zoneId
  TITW.memberIndex = memberIndex
  TITW.guildIndex = guildIndex
end

local function validateTravel(zoneId)
  return not IsUnitInCombat("player") and
    zoneId ~= 181 and
    not IsUnitDead("player") and
    ZONE_STORIES_GAMEPAD.IsZoneCollectibleUnlocked(zoneId) and
    not TITW:GetZoneFullyDiscovered(zoneId) and
    CanJumpToPlayerInZone(zoneId) and
    TITW.SV.enabledZones[zoneId] ~= nil and
    TITW.SV.enabledZones[zoneId].enabled
end

function TITW.checkGuildMembersCurrentZoneAndJump()
  if TITW.enableJumping then
    for guildIndex = TITW.guildIndex, GetNumGuilds() do
      local guildId = GetGuildId(guildIndex)
      for memberIndex = TITW.memberIndex, GetNumGuildMembers(guildId) do
          local displayName, _, _, status, _ = GetGuildMemberInfo(guildId, memberIndex)
          local online = (status ~= PLAYER_STATUS_OFFLINE)
          local _, _, _, _, _, _, _, zoneId = GetGuildMemberCharacterInfo(guildId, memberIndex)

          -- Online check
          if online and displayName ~= GetDisplayName() and TITW.alreadyJumpedTo[displayName] ~= zoneId then

              local okToTravel = validateTravel(zoneId)
              if okToTravel then
                d("considering "..displayName.." in "..GetZoneNameById(zoneId))
              end
              if okToTravel then
                if not TITW.SV.promptToJump then
                  TITW:triggerJump(displayName, zoneId, memberIndex, guildIndex)
                  break
                else
                  ZO_Dialogs_ShowPlatformDialog("TITW_CONFIRM_JUMP", { PLAYERNAME = displayName, ZONEID = zoneId, MEMBERINDEX = memberIndex, GUILDINDEX = guildIndex }, {mainTextParams = { PLAYERNAME, ZONEID, MEMBERINDEX, GUILDINDEX }})
                end
              end
          end
        end
      end
      TITW.memberIndex = 1
      TITW.guildIndex = 1
    end
    zo_callLater(TITW.checkGuildMembersCurrentZoneAndJump, 45000) -- 2.5 minutes
end

function TITW:Initialize()
  zo_callLater(self.BuildZoneNameCache, 1500)
  zo_callLater(self.BuildMenu, 1800)
  TITW.checkGuildMembersCurrentZoneAndJump()
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

-- Start Here
EVENT_MANAGER:RegisterForEvent(TITW.Name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
