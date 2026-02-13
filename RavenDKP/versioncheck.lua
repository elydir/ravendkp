-- RavenDKP Version Check
-- Broadcasts version to guild on login and checks for updates

local addonName = "RavenDKP"

-- Get version from TOC file
local versionStr = GetAddOnMetadata(addonName, "Version")
local _, _, major, minor, fix = strfind(versionStr or "0.0.0", "(%d+)%.(%d+)%.(%d+)")
local localVersion = tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(fix)

-- Initialize saved variables
RavenDKPDB = RavenDKPDB or {}
local remoteVersion = RavenDKPDB.updateAvailable or 0

-- Create frame for event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == addonName then
    -- Saved variables are now loaded
    if RavenDKPDB then
      remoteVersion = RavenDKPDB.updateAvailable or 0
    end
    
  elseif event == "CHAT_MSG_ADDON" and arg1 == addonName then
    -- Parse incoming version message: "VER:123"
    local _, _, prefix, version = strfind(arg2, "(%a+):(%d+)")
    if prefix == "VER" then
      local ver = tonumber(version)
      if ver and ver > localVersion and ver > remoteVersion and RavenDKPDB then
        RavenDKPDB.updateAvailable = ver
        remoteVersion = ver
		local remoteMajor = math.floor(remoteVersion / 10000)
        local remoteMinor = math.floor((remoteVersion - math.floor(remoteVersion / 10000) * 10000) / 100)
        local remoteFix = remoteVersion - math.floor(remoteVersion / 100) * 100
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc" .. addonName .. "|r: New version |cff33ffcc" .. remoteMajor .. "." .. remoteMinor .. "." .. remoteFix .. "|r available!")
      end
    end
    
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Check if update is available
    if remoteVersion > localVersion then
      local remoteMajor = math.floor(remoteVersion / 10000)
      local remoteMinor = math.floor((remoteVersion - math.floor(remoteVersion / 10000) * 10000) / 100)
      local remoteFix = remoteVersion - math.floor(remoteVersion / 100) * 100
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc" .. addonName .. "|r: New version |cff33ffcc" ..
        remoteMajor .. "." .. remoteMinor .. "." .. remoteFix .. "|r available!")
      if RavenDKPDB then
        RavenDKPDB.updateAvailable = 0
      end
    end
    
    -- Broadcast version to guild
    SendAddonMessage(addonName, "VER:" .. localVersion, "GUILD")
  end
end)
