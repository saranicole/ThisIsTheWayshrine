local TITW = ThisIsTheWayshrine

local LAM = LibSettingsService

if not LibSettingsService then
    return
end

function TITW:HelperMenu()

  local panel = LAM:AddAddon(TITW.Name, {
    savedVars = self.SV,
    allowDefaults = false,  -- Show "Reset to Defaults" button
    allowRefresh = true    -- Enable automatic control updates
  })

  panel:AddSetting {
    type = "checkbox",
    name = TITW.Lang.ENABLE_JUMPING,
    getFunction = function()
      return self.SV.enableJumping
    end,
    setFunction = function(var)
      self.SV.enableJumping = var
      if var then
        TITW.checkGuildMembersCurrentZoneAndJump()
      end
    end,
    default = self.SV.enableJumping
  }

  panel:AddSetting {
    type = "checkbox",
    name = TITW.Lang.ANNOUNCE,
    getFunction = function()
      return self.SV.announce
    end,
    setFunction = function(var)
      self.SV.announce = var
    end,
    default = self.SV.announce
  }

  panel:AddSetting {
    type = "header",
    name = TITW.Lang.GUILD_ENABLE_HEADER
  }

  for iDex = 1, GetNumGuilds() do
    local guildId = GetGuildId(iDex)
    panel:AddSetting {
      type = "checkbox",
      name = GetGuildName(guildId),
      getFunction = function()
        if not TITW.AV.enableOverrideGuilds[guildId].initial then
          return TITW.AV.enableOverrideGuilds[guildId].enabled
        end
        return true
      end,
      setFunction = function(var)
        if guildId ~= nil then
          if TITW.AV.enableOverrideGuilds[guildId].initial then
            TITW.AV.enableOverrideGuilds[guildId] = { enabled = var }
          end
          TITW.AV.enableOverrideGuilds[guildId].enabled = var
        end
      end,
      default = true
    }
  end

  panel:AddSetting {
    type = "header",
    name = TITW.Lang.TOGGLE_ZONE_DISCOVERY,
  }

  panel:AddSetting {
    type = "checkbox",
    name = TITW.Lang.TOGGLE_ALL_ZONES,
    getFunction = function()
      return self.SV.selectAll
    end,
    setFunction = function(var)
      TITW.toggleAvailableZones(var)
      self.SV.selectAll = var
    end,
    default = self.SV.selectAll
  }

  for i, data in pairs(GAMEPAD_WORLD_MAP_LOCATIONS.data.mapData) do
    local locationName = data.locationName
    local zoneId = TITW:GetZoneIdFromZoneName(locationName)
    panel:AddSetting {
      type = "checkbox",
      name = data.locationName,
      getFunction = function()
        if self.SV.enabledZones[zoneId] ~= nil then
          return self.SV.enabledZones[zoneId].enabled
        end
        return self.SV.selectAll
      end,
      setFunction = function(var)
        if zoneId ~= nil then
          if self.SV.enabledZones[zoneId] == nil then
            self.SV.enabledZones[zoneId] = TITW:enumerateWayshrines(nil, zoneId)
          end
          self.SV.enabledZones[zoneId].enabled = var
        end
      end,
      default = self.SV.selectAll,
      disable = function()
        return not ZONE_STORIES_GAMEPAD.IsZoneCollectibleUnlocked(zoneId) and not TITW:GetZoneFullyDiscovered(zoneId)
      end
    }
  end
end

function TITW.BuildMenu()
  SLASH_COMMANDS["/titwsettings"] = function(args)
    TITW:HelperMenu()
  end
end