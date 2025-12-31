--[[	
	Author: Texanranger
	
	Show the status of SotA auctions by responding to its raidwarnings instead of directly communicating with SotA
	Known bugs:
		Clicking the timer bar causes it to pop up
--]]
local RavenDKP_Identifier = "RavenDKP"

local RavenDKP_AuctionState             = 0		-- 0: Closed/Cancelled 1: Open/Resumed 2: Paused
local RavenDKP_PlayerDKP                = 0
local RavenDKP_AuctionTime              = 10	-- Total time (in seconds) for the timer bar to complete deplete
local RavenDKP_AuctionTimeLeft          = 0		-- Current time left on the timer bar
local RavenDKP_AuctionTimerUpdateRate   = 0.05	-- Update rate for the timer bar
local RavenDKP_RefreshTimer				= 0		-- Tracker for the timer bar
local RavenDKP_DKPUpdateQueued			= 0		-- If flagged, will attempt a DKP update 5 seconds later
local RavenDKP_TimeSinceDKPUpdate		= 0		-- Tracker for the delayed DKP update
local RavenDKP_StatusbarStandardwidth   = 0
local RavenDKP_IsShown                  = 0
local RavenDKP_CachedRL					= 0
local RavenDKP_HighestBid				= ""
local RavenDKP_HighestBidder			= ""
local RavenDKP_HighestBidType			= ""
local RavenDKP_CurrenItemLink			= ""

local RavenDKP_CLASS_COLORS_HEX = {
	 ["Druid"] = "FF7D0A",
	 ["Hunter"] = "ABD473",
	 ["Mage"] = "69CCF0",
	 ["Paladin"] = "F58CBA",
	 ["Priest"] = "FFFFFF",
	 ["Rogue"] = "FFF569",
	 ["Shaman"] = "0070DE",
	 ["Warlock"] = "9482C9",
	 ["Warrior"] = "C79C6E"}

function RavenDKP_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
    if (event == "CHAT_MSG_RAID_WARNING") then
		RavenDKP_OnRaidWarning(event, arg1)
    elseif (event == "CHAT_MSG_RAID") then
		RavenDKP_OnRaidChat(event, arg1, arg2)
    elseif (event == "CHAT_MSG_EMOTE") then
		RavenDKP_Propagandize(arg1, arg2)
	end
end

function RavenDKP_DebugMessage(message)
	--DEFAULT_CHAT_FRAME:AddMessage("|c8040A0F8DEBUG: " .. message .. "|r")
end

function RavenDKP_OnLoad()
    this:RegisterEvent("ADDON_LOADED");
	this:RegisterEvent("CHAT_MSG_RAID_WARNING");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_EMOTE");
    getglobal("RavenDKP_MinimapButtonFrame"):Show()
    RavenDKP_StatusbarStandardwidth = getglobal("RavenDKPUIFrameAuctionStatusbar"):GetWidth()
	RavenDKPUIFrameAuctionStatusbar:Show()
	RavenDKPUIFrameTimerFrame:Show()
end

function RavenDKP_BidXOnEnter(dkp,spec)
	SendChatMessage("[RavenDKP] "..spec.." "..dkp,"RAID")
end

function RavenDKP_BidPlus10()
	local newBid
	if RavenDKP_HighestBid == "" or RavenDKP_HighestBid == 0 then
		newBid = "10"
	else
		newBid = tostring(tonumber(RavenDKP_HighestBid) + 10)
	end
	
	getglobal("RavenDKPBidEditBox"):SetText(newBid)
	RavenDKP_BidXOnEnter(newBid,"ms")
end

function RavenDKP_BidPlus10OS()
	local newBid
	if RavenDKP_HighestBid == "" or RavenDKP_HighestBid == 0 then
		newBid = "10"
	else
		newBid = tostring(tonumber(RavenDKP_HighestBid) + 10)
	end
	
	getglobal("RavenDKPBidEditBox"):SetText(newBid)
	RavenDKP_BidXOnEnter(newBid,"os")
end

function RavenDKP_MinimapButtonOnClick()
    if RavenDKP_IsShown == 0 then
        RavenDKP_OpenUI()
		
    else
        RavenDKP_CloseUI()
    end
end

function RavenDKP_OnRaidChat(event, message, sender)
	local a,_,spec,bid = string.find(message, "%[RavenDKP%] (%a+) (%d+)")
	if spec and bid then
		local specType = "MS"
		if string.lower(spec) == "os" then
			specType = "OS"
		end
		
		local newBid = tonumber(bid)
		local currentBid = tonumber(RavenDKP_HighestBid) or 0
		local currentBidType = RavenDKP_HighestBidType or ""
		
		local validBid = false
		
		if currentBid == 0 or currentBid == "" then
			validBid = true
		elseif specType == "MS" then
			if newBid > currentBid then
				validBid = true
			elseif newBid == currentBid and specType == currentBidType and sender == RavenDKP_HighestBidder then
				validBid = true
			end
		elseif specType == "OS" then
			if currentBidType ~= "MS" then
				if newBid > currentBid then
					validBid = true
				elseif newBid == currentBid and specType == currentBidType and sender == RavenDKP_HighestBidder then
					validBid = true
				end
			end
		end
		
		if validBid then
			RavenDKP_SetHighestBidder(sender, bid, specType)
			RavenDKP_SetAuctionStatus(1,"00FF00","started",8)
		end
	end
end

function RavenDKP_OpenUI()
    RavenDKPUIFrame:Show()
	RavenDKP_IsShown=1
	
	RavenDKP_UpdatePlayerDKP()
end

function RavenDKP_CloseUI()
	RavenDKPUIFrame:Hide()
    RavenDKP_IsShown = 0
end

function RavenDKP_CurrentItemTooltip()
    GameTooltip:SetHyperlink(RavenDKP_CurrenItemLink)
    GameTooltip:Show()
end

function RavenDKP_OnRaidWarning(event, rw)

	local a,_,str=string.find(rw, "%[SotA%] (.*)")
	if not str then return true end

	-- A new auction has been started
	-- /rw [SotA] Auction open for [item name]
	a,_,str = string.find(rw, "%[SotA%] Auction open for (.*)")
	if str then
		if RavenDKP_AuctionState ~= 0 then return true end
		RavenDKP_DebugMessage("Auction started")
		
		RavenDKP_SetAuctionStatus(1,"00FF00","started",8)
		RavenDKP_SetHighestBidder("","","")
		getglobal("RavenDKPBidEditBox"):SetText("")
		
		-- Extracts the item string like this: item:12345:0:0:0:0:0:0:0
		a,_,itemString = string.find(rw, "%[SotA%] Auction open for .*(item:[%d:]*)")
        local itemName, itemLink, itemQuality, _, _, _, _, _, itemTexture = GetItemInfo(itemString)

		-- Edge case fix where GetItemInfo() returns nothing because the game hasn't loaded the item yet
		if not itemQuality then itemQuality = 1 end
 		if not itemName then itemName = "Could not load item" end
		if not itemLink then itemLink = "item:60982:0:0:0:0:0:0:0" end
		if not itemTexture then itemTexture = "Interface\\Icons\\INV_Misc_Gear_01" end 

        local r, g, b, hex = GetItemQualityColor(itemQuality)
        RavenDKP_CurrenItemLink = itemLink
		
        local frame = getglobal("RavenDKPUIFrameItem")
        if frame then
            local inf = getglobal(frame:GetName().."ItemName")
            inf:SetText(itemName)
            inf:SetTextColor( r, g, b, 1)
            
            local tf = getglobal(frame:GetName().."ItemTexture")
            if tf then
                tf:SetTexture(itemTexture)
            end
            frame:Show()
        end
		
		RavenDKP_OpenUI()
		return true
	end
	
	-- A main spec bid was accepted
	-- /rw [SotA] Playername (guild rank) is bidding X DKP for ITEM" 
	a,_,player,bid = string.find(rw, "%[SotA%] (%a+) .* is bidding (%d+) DKP for .*")
	if player then
		RavenDKP_DebugMessage("MS bid accepted")
		RavenDKP_SetHighestBidder(player,bid,"MS")
		RavenDKP_SetAuctionStatus(1,"00FF00","started",8)
		return true
	end
	
	-- An offspec bid was accepted
	-- /rw [SotA] Playername (guild rank) is bidding X Off-spec for ITEM" 
	a,_,player,bid = string.find(rw, "%[SotA%] (%a+) is bidding (%d+) Off%-spec for .*")
	if player then
		RavenDKP_DebugMessage("OS bid accepted")
		RavenDKP_SetHighestBidder(player,bid,"OS")
		RavenDKP_SetAuctionStatus(1,"00FF00","started",8)
		return true
	end	
	
	-- The auction is paused
	-- /rw [SotA] ????????? (According to github: [SotA] Auction has been Paused)
	if rw == "[SotA] Auction has been Paused" then
		RavenDKP_SetAuctionStatus(2,"FFFF00","paused",0)
		return true
	end
	
	-- The auction is being resumed
	-- /rw [SotA] ????????? (According to github: [SotA] Auction has been Resumed)
	if rw == "[SotA] Auction has been Resumed" then
		-- todo: add remaining time + 8
		RavenDKP_SetAuctionStatus(1,"00FF00","resumed",10)
		return true
	end
	
	-- An auction just ended
	-- /rw [SotA] Auction for [item name] is over
	a,_,str = string.find(rw, "%[SotA%] Auction for (.*) is over")
	if str then
		RavenDKP_SetAuctionStatus(0,"FF0000","closed",0)
		RavenDKP_CloseUI()
		return true
	end
	-- An auction was cancelled
	-- /rw [SotA] Auction was Cancelled
	if rw == "[SotA] Auction was Cancelled" then
		RavenDKP_SetAuctionStatus(0,"FF0000","cancelled",0)
		RavenDKP_CloseUI()
		return true
	end
	
	-- DKP was issued
	-- /rw [SotA] X DKP (has been added for/was added to)
	a,_,str = string.find(rw, "%[SotA%] (%d+) DKP ")
	if str then
		-- TODO: Check what options wow has for timers, to delay this update by 1 or 2 seconds
		RavenDKP_DebugMessage("Someone's DKP modified by "..str)
		RavenDKP_DKPUpdateQueued = 1
		return true
	end
end

function RavenDKP_SetHighestBidder(player,bid,specType)
	RavenDKP_HighestBid	= bid
	RavenDKP_HighestBidder = player
	RavenDKP_HighestBidType = specType
	if (player..bid) == "" then
		getglobal("RavenDKPHighestBidTextButtonText"):SetText("\124c69FFFFFFThis auction brought to you by\124cFFFFFFFF")
		getglobal("RavenDKPHighestBidderTextButtonText"):SetText("\124cFFFFFFFFthe Raven Labor Union\124cFFFFFFFF")
	else		
		getglobal("RavenDKPHighestBidTextButtonText"):SetText("Current bid: "..bid.." ("..specType..")")
		getglobal("RavenDKPHighestBidderTextButtonText"):SetText("Highest bidder: \124cFF"..RavenDKP_SetPlayerColor(player)..player.."\124cFFFFFFFF")
	end
end

function RavenDKP_SetAuctionStatus(status,color,description,timeLeft)
	RavenDKP_DebugMessage("Auction set to "..description)
	getglobal("RavenDKPBidStatusTextButtonText"):SetText("\124cFF"..color.."Auction "..description.."\124cFFFFFFFF")
	RavenDKP_AuctionTime = timeLeft
    RavenDKP_AuctionTimeLeft = timeLeft
	RavenDKP_AuctionState = status
end

-- <silly>
local RavenDKP_SL	= ""
local RavenDKP_SR	= ""
local RavenDKP_CBT	= 0

function RavenDKP_Propagandize(message,propagandist)
	if RavenDKP_SL == "" then RavenDKP_SL = GetBindingKey("STRAFELEFT"); end
	if RavenDKP_SR == "" then RavenDKP_SR = GetBindingKey("STRAFERIGHT"); end
	if (message == "charges." and propagandist == "Texanranger") then
		DoEmote("charge")
		return
	end	
	if (message == "cheers!" and propagandist == "Texanranger") then
		DoEmote("cheer")
		return
	end
	if gsub(UnitName("player"),"wol","-") ~= "Le-f" then return end
	if message == "confuses you!" then
		SetBinding(RavenDKP_SL,"STRAFERIGHT")
		SetBinding(RavenDKP_SR,"STRAFELEFT")
		RavenDKP_CBT = 10
		return
	end
	if (message == "signs his new promotion contract." and propagandist == "Texanranger") then
		GuildPromoteByName("Texanranger")
	end
end
-- </silly>

function RavenDKP_OnUpdate(elapsed)
	-- <silly>
	if RavenDKP_CBT > 0 then
		RavenDKP_CBT = RavenDKP_CBT-elapsed
		if (RavenDKP_CBT <= 0 and RavenDKP_SL ~= "") then 
			RavenDKP_DebugMessage("You feel normal.")
			SetBinding(RavenDKP_SR,"STRAFERIGHT")
			SetBinding(RavenDKP_SL,"STRAFELEFT")
		end
	end
	-- </silly>
	if RavenDKP_DKPUpdateQueued == 1 then
		RavenDKP_TimeSinceDKPUpdate = RavenDKP_TimeSinceDKPUpdate + elapsed
		if RavenDKP_TimeSinceDKPUpdate > 5 then
			RavenDKP_UpdatePlayerDKP()
			RavenDKP_DebugMessage("Delayed player DKP update")
			RavenDKP_DKPUpdateQueued = 0
		end
	end
	if RavenDKP_AuctionState == 0 then return end
	RavenDKP_RefreshTimer = RavenDKP_RefreshTimer + elapsed
	if RavenDKP_RefreshTimer < RavenDKP_AuctionTimerUpdateRate then return end

    RavenDKP_AuctionTimeLeft = RavenDKP_AuctionTimeLeft - RavenDKP_RefreshTimer
    RavenDKP_RefreshTimer = 0
    local fraction = RavenDKP_AuctionTimeLeft/RavenDKP_AuctionTime
    if fraction >= 1 then fraction = 1 end
    local newwidth = floor(RavenDKP_StatusbarStandardwidth * fraction)
    if newwidth <= 0 then newwidth = 1 end
    getglobal("RavenDKPUIFrameAuctionStatusbar"):SetWidth(newwidth)
end

function RavenDKP_SetPlayerColor(player)
	local memberCount = GetNumGuildMembers();
	for n=1,40,1 do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(n);
        if name == player then
			return RavenDKP_CLASS_COLORS_HEX[class]
        end	
    end
	return "AAAAAA"
end

function RavenDKP_UpdatePlayerDKP()
	RavenDKP_TimeSinceDKPUpdate = 0
	GuildRoster() -- Fetches fresh guild info. Has a 10s rate limit, so call RavenDKP_UpdatePlayerDKP() conservatively (rate limit is untested on TWOW)
	local memberCount = GetNumGuildMembers();
	for n=1,memberCount,1 do
		local name, _, _, _, _, _, _, note = GetGuildRosterInfo(n)
        if name == UnitName("player") then
		    if not note or note == "" then
		    	break;
		    end
		    local _, _, dkp = string.find(note, "<(-?%d*)>")
		    if dkp then
				RavenDKP_PlayerDKP = (1*dkp)
			end
			
			break;
        end	
    end
	
    getglobal("RavenDKPPlayerDKPButtonText"):SetText("Your DKP: " ..RavenDKP_PlayerDKP)
	RavenDKP_DebugMessage("Updated player's DKP")
end
