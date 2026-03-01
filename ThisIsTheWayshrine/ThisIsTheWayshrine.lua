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
  announce = true,
  selectAll = true,
  firstTimeLoad = true,
}

TITW.Account = {
  numGuilds = 0,
  enableOverrideGuilds = {},
}

TITW.showing = false
TITW.hookLock = false

TITW.zoneNameToId = {}
TITW.zoneIds = {}
TITW.controlList = {}
TITW.toggle = false
TITW.alreadyJumpedTo = {}
TITW.memberIndex = 1
TITW.guildIndex = 1
TITW.isTeleporting = false
TITW.errorJumpingTo = {}
TITW.prevJumps = 0
TITW.numJumps = 0
TITW.stalledCounter = 0
TITW.waitToJumpDuration = 2500
TITW.zoneExceptions = { 181, 584, 643 }
TITW.guildCompositions = {}

if IsConsoleUI() then
  TITW.waitToJumpDuration = 10000
end

function TITW.isValueInTable(table, element)
  for _, v in ipairs(table) do
    if element == v then
      return true
    end
  end
return false
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

function TITW.toggleAvailableZones(var)
  for i, data in pairs(GAMEPAD_WORLD_MAP_LOCATIONS.data.mapData) do
    local location = data.locationName
    local zoneI = TITW:GetZoneIdFromZoneName(location)
    if zoneI and ZONE_STORIES_GAMEPAD.IsZoneCollectibleUnlocked(zoneI) and not TITW.isValueInTable(TITW.zoneExceptions, zoneI) then
      if TITW.SV.enabledZones[zoneI] == nil then
        TITW.SV.enabledZones[zoneI] = TITW:enumerateWayshrines(nil, zoneI)
      end
      TITW.SV.enabledZones[zoneI].enabled = var
    end
  end
end

function TITW.toggleAvailableGuilds()
  for i = 1, GetNumGuilds() do
    local guildId = GetGuildId(i)
    TITW.AV.enableOverrideGuilds[guildId] = TITW.AV.enableOverrideGuilds[guildId] or { initial = true }
  end
end

function TITW:triggerJump(displayName, zoneId, memberIndex)
  TITW.isTeleporting = true
  JumpToGuildMember(displayName)
  TITW.alreadyJumpedTo[displayName] = zoneId
  TITW.memberIndex = memberIndex
  TITW.numJumps = TITW.numJumps + 1
end

local function validateTravel(zoneId)
  return not IsUnitInCombat("player") and
    not TITW.isValueInTable(TITW.zoneExceptions, zoneId) and
    CanLeaveCurrentLocationViaTeleport() and
    not IsInCampaign() and
    not IsUnitDead("player") and
    ZONE_STORIES_GAMEPAD.IsZoneCollectibleUnlocked(zoneId) and
    not TITW:GetZoneFullyDiscovered(zoneId) and
    CanJumpToPlayerInZone(zoneId) and
    TITW.SV.enabledZones[zoneId] ~= nil and
    TITW.SV.enabledZones[zoneId].enabled and
    not TITW.isTeleporting
end

function TITW.checkStalled()
  if TITW.SV.enableJumping then
    if TITW.prevJumps == TITW.numJumps then
      TITW.stalledCounter = TITW.stalledCounter + 1
    end
    if TITW.stalledCounter > 0 then
      TITW.isTeleporting = false
      TITW.checkGuildMembersCurrentZoneAndJump()
      TITW.stalledCounter = 0
    end
    TITW.prevJumps = TITW.numJumps
  end
end

function TITW.checkGuildMembersCurrentZoneAndJump()
  if TITW.SV.enableJumping then
      if next(TITW.alreadyJumpedTo) ~= nil then
        EVENT_MANAGER:UnregisterForUpdate("TITW_CheckAndJump")
      end
      local guildId = GetGuildId(TITW.guildIndex)
      TITW.guildCompositions[guildId] = { active = 0, inactive = 0 }
      if TITW.AV.enableOverrideGuilds[guildId].initial or TITW.AV.enableOverrideGuilds[guildId].enabled then
        for memberIndex = TITW.memberIndex, GetNumGuildMembers(guildId) do
          local displayName, _, _, status, secsSinceLogoff = GetGuildMemberInfo(guildId, memberIndex)
          local online = (status ~= PLAYER_STATUS_OFFLINE)
          local _, _, _, _, _, _, _, zoneId = GetGuildMemberCharacterInfo(guildId, memberIndex)

          -- six months in seconds
          if secsSinceLogoff > 15638400 then
            TITW.guildCompositions[guildId].inactive = TITW.guildCompositions[guildId].inactive + 1
          else
            TITW.guildCompositions[guildId].active = TITW.guildCompositions[guildId].active + 1
          end

          -- Online check
          if online then
            if displayName ~= GetDisplayName() and TITW.alreadyJumpedTo[displayName] ~= zoneId and TITW.errorJumpingTo[displayName] ~= zoneId then
                local okToTravel = validateTravel(zoneId)
                if okToTravel then
                  if TITW.SV.announce then
                    d(TITW.Lang.GUILD_NAME.." "..TITW.guildIndex..": "..GetGuildName(guildId)..", "..TITW.Lang.TRAVELING_TO.." "..displayName.." "..TITW.Lang.IN.." "..GetZoneNameById(zoneId))
                  end
                  TITW:triggerJump(displayName, zoneId, memberIndex)
                  -- validJumpsAvailable = true
                  break
                end
            end
          end
        end
      end
      -- Do not try to jump to unpopulated guilds
      if (GetNumGuildMembers(guildId) == 1 or TITW.guildCompositions[guildId].active < 4) and TITW.AV.enableOverrideGuilds[guildId].initial then
        TITW.AV.enableOverrideGuilds[guildId] = { enabled = false, initial = false }
      end
      TITW.memberIndex = 1
      TITW.guildIndex = TITW.guildIndex + 1
      if TITW.guildIndex > GetNumGuilds() then
        TITW.guildIndex = 1
      end
      if not TITW.AV.enableOverrideGuilds[guildId].enabled then
        TITW.checkStalled()
      end
    end
end

--When Loaded
local function OnAddOnLoaded(eventCode, addonName)
  if addonName ~= TITW.Name then return end
	EVENT_MANAGER:UnregisterForEvent(TITW.Name, EVENT_ADD_ON_LOADED)

  --Get Account/Character Setting
  TITW.AV = ZO_SavedVars:NewAccountWide("ThisIsTheWayshrine_Vars", 1, nil, TITW.Account)
  TITW.CV = ZO_SavedVars:NewCharacterIdSettings("ThisIsTheWayshrine_Vars", 1, nil, TITW.Default)
  TITW.SwitchSV()
  TITW.BuildZoneNameCache()
  zo_callLater(function()
    if TITW.SV.firstTimeLoad or select(1, TITW.AV.enableOverrideGuilds).initial == nil then
      TITW.toggleAvailableZones(true)
      TITW.toggleAvailableGuilds()
      TITW.SV.firstTimeLoad = false
      EVENT_MANAGER:RegisterForUpdate("TITW_CheckAndJump", 10000, TITW.checkGuildMembersCurrentZoneAndJump)
    end
    EVENT_MANAGER:RegisterForUpdate("TITW_CheckStalled", 45000, TITW.checkStalled)
  end, 1500)
end

-- Start Here
EVENT_MANAGER:RegisterForEvent(TITW.Name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
EVENT_MANAGER:RegisterForEvent("TITW_PlayerActivated", EVENT_PLAYER_ACTIVATED, function()
    TITW:BuildMenu()
    TITW.isTeleporting = false
    zo_callLater(TITW.checkGuildMembersCurrentZoneAndJump, TITW.waitToJumpDuration)
end
)
