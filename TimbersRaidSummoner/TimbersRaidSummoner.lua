-- Timber's Raid Summoner Addon for WoW Classic Era
-- Main addon file

local addonName = "TimbersRaidSummoner"
local TRS = _G[addonName]

-- TRS.NAME    = ADDON_NAME
TRS.NAME    = C_AddOns.GetAddOnMetadata("TimbersRaidSummoner", "Title")
TRS.VERSION = C_AddOns.GetAddOnMetadata("TimbersRaidSummoner", "Version")

local RITUAL_OF_SUMMONING_ID = 698

-- Saved variables initialization
TimbersRaidSummonerDB = TimbersRaidSummonerDB or {
    keywords = {"*123"},
    settings = {
        playSoundOnAdd = true,
        showToastNotification = true, -- Show toast notification when someone requests a summon
        autoWhisper = false,
        sendRaidMessage = true,
        raidMessage = "Summoning %s, please help click!",
        sendSayMessage = false,
        sayMessage = "Summoning %s, please help click!",
        whisperMessage = "Summons incoming. Be ready to accept it. If you don't receive it within 30 seconds, let me know!",
        checkMana = false,
        checkShards = false,
        shamanColor = "default", -- "default" = expansion default, "blue", "pink"
        rangeOpacity = 0.5, -- Opacity for out-of-range raid members (0.1 - 1.0)
        showLoadedMessage = true -- Show "addon loaded" message on login
    },
    summonQueue = {},
    minimap = {}
}

-- Per-character saved variables
TimbersRaidSummonerCharDB = TimbersRaidSummonerCharDB or {
    settings = {
        raidListCollapsed = false
    }
}

-- Local references
local db
local currentlySummoning = nil -- Track who we're currently summoning
local summonFromQueue = false -- Track if summon was initiated from queue
local summonChannelActive = false -- Track if summon channel is active
local summonStartShardCount = 0 -- Track shard count when summon starts
local activeSummons = {} -- Track active summons: [summonerName] = targetName
local wasChanneling = {} -- Track if someone was channeling last frame: [summonerName] = true/false
local meetingStoneStartTime = nil -- Track when Meeting Stone channel started
local meetingStoneTarget = nil -- Track who we're summoning via Meeting Stone

-- Constants
local QUEUE_TIMEOUT = 300 -- Time in seconds

-- Frame references
TRS.mainFrame = nil
TRS.raidListFrame = nil
TRS.summonQueueFrame = nil
TRS.settingsFrame = nil
TRS.settingsVisible = false
TRS.toastFrame = nil
TRS.raidListCollapsed = false
TRS.hasAddon = {}  -- Track which group members have the addon installed

-- StaticPopup for restoring default keywords
StaticPopupDialogs["TIMBERSRAIDSUMMONER_RESTORE_KEYWORDS"] = {
    text = "Are you sure you want to restore the default keywords? This will delete all your existing keywords.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        local db = TimbersRaidSummonerDB
        if db then
            db.keywords = {"*123"}
            TRS:UpdateSettingsKeywords()
            print("|cFF00FF00Timber's Raid Summoner:|r Keywords restored to defaults")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Check if player can summon (is warlock with Ritual of Summoning)
function TRS:CanSummon()
    local _, class = UnitClass("player")
    if class ~= "WARLOCK" then
        return false
    end
       -- Check if player has Ritual of Summoning spell
    local spellName = TRS.GetSpellInfo(RITUAL_OF_SUMMONING_ID) -- Ritual of Summoning spell ID
    if not spellName then
        return false
    end
       -- Check if the player knows the spell
    if IsSpellKnown(RITUAL_OF_SUMMONING_ID) then
        return true
    end
       return false
end

-- Get formatted zone text for a unit, including subzone if applicable
-- Returns "Subzone, Zone" or just "Zone" if no subzone
-- playerName is optional, used to look up raid roster info
function TRS:GetFormattedZoneForUnit(unitId, playerName)
    -- For the player, we can use GetSubZoneText() for more detailed info
    if UnitIsUnit(unitId, "player") then
        local subZone = GetSubZoneText()
        local zone = GetRealZoneText()
        if subZone and subZone ~= "" and zone and zone ~= "" and subZone ~= zone then
            return subZone .. ", " .. zone
        elseif zone and zone ~= "" then
            return zone
        end
    end

    -- For raid members, GetRaidRosterInfo returns subzone-level info (e.g., "Ammen Vale")
    -- Combine it with C_Map zone info to get "Ammen Vale, Azuremyst Isle"
    if IsInRaid() and playerName then
        local rosterZone = nil
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
            if name == playerName then
                rosterZone = zone
                break
            end
        end

        if rosterZone and rosterZone ~= "" then
            -- Try to get the parent zone from C_Map
            local mapID = C_Map.GetBestMapForUnit(unitId)
            if mapID then
                local mapInfo = C_Map.GetMapInfo(mapID)
                if mapInfo and mapInfo.name and mapInfo.name ~= rosterZone then
                    -- rosterZone is the subzone, mapInfo.name is the zone
                    return rosterZone .. ", " .. mapInfo.name
                end
            end
            -- Fallback to just the roster zone if we can't get parent
            return rosterZone
        end
    end

    -- For party members or fallback, try C_Map
    local mapID = C_Map.GetBestMapForUnit(unitId)
    if not mapID then
        return nil
    end

    local mapInfo = C_Map.GetMapInfo(mapID)
    if not mapInfo or not mapInfo.name then
        return nil
    end

    local zoneName = mapInfo.name
    local parentMapID = mapInfo.parentMapID

    -- Check if there's a parent zone (not continent)
    if parentMapID then
        local parentInfo = C_Map.GetMapInfo(parentMapID)
        if parentInfo and parentInfo.name then
            -- Only append parent if it's a zone (mapType 3) not a continent (mapType 2)
            -- mapType: 2 = Continent, 3 = Zone, 5 = Micro (subzone)
            if parentInfo.mapType and parentInfo.mapType == 3 then
                return zoneName .. ", " .. parentInfo.name
            end
        end
    end

    return zoneName
end

-- Initialize the addon
local function Initialize()
    db = TimbersRaidSummonerDB
    TimbersRaidSummonerCharDB = TimbersRaidSummonerCharDB or { settings = { raidListCollapsed = false } }
    if TimbersRaidSummonerCharDB.settings == nil then
        TimbersRaidSummonerCharDB.settings = { raidListCollapsed = false }
    end
    if TimbersRaidSummonerCharDB.settings.raidListCollapsed == nil then
        TimbersRaidSummonerCharDB.settings.raidListCollapsed = false
    end
       -- Ensure new settings exist (for existing saved variables)
    if db.settings.sendSayMessage == nil then
        db.settings.sendSayMessage = false
    end
    if db.settings.sayMessage == nil then
        db.settings.sayMessage = "Summoning %s, please help click!"
    end
    if db.settings.showLoadedMessage == nil then
        db.settings.showLoadedMessage = true
    end
    if db.settings.showToastNotification == nil then
        db.settings.showToastNotification = true
    end
    -- Migrate old shamanColorVanilla boolean to new shamanColor string
    if db.settings.shamanColorVanilla ~= nil then
        -- true was the old default, so migrate to "default"
        -- false was explicitly set by user, so migrate to "blue"
        db.settings.shamanColor = db.settings.shamanColorVanilla and "default" or "blue"
        db.settings.shamanColorVanilla = nil
    end
    if db.settings.shamanColor == nil then
        db.settings.shamanColor = "default"
    end
    if db.settings.rangeOpacity == nil then
        db.settings.rangeOpacity = 0.5
    end
    TRS:CreateMainFrame()

    -- Hide the addon dot whenever GameTooltip is cleared for non-addon use
    GameTooltip:HookScript("OnTooltipCleared", function(self)
        if self.TRSAddonDot then self.TRSAddonDot:Hide() end
    end)

    -- Set up keybindings
    BINDING_HEADER_TIMBERSRAIDSUMMONER = "Timber's Raid Summoner"
    BINDING_NAME_TIMBERSRAIDSUMMONER_TOGGLE = "Toggle Timber's Raid Summoner"

    -- Show loaded message if enabled
    if db.settings.showLoadedMessage then
        print("|cFF00FF00Timber's Raid Summoner|r loaded. Type /trs or /timbersraidsummoner to toggle the interface.")
    end
       -- Initialize minimap button
    TRS:InitializeMinimapButton()
end

-- ========================================================================
-- Minimap Button Functions
-- ========================================================================

-- Ensure minimap database exists
local function ensureMinimapDB()
    TimbersRaidSummonerDB = TimbersRaidSummonerDB or {}
    TimbersRaidSummonerDB.minimap = TimbersRaidSummonerDB.minimap or {}
    if TimbersRaidSummonerDB.minimap.hide == nil then
        TimbersRaidSummonerDB.minimap.hide = false
    end
end

-- Toggle main window
local function toggleMainWindow()
    TRS:ToggleFrame()
end

-- Show minimap button
local function showMinimapButton()
    ensureMinimapDB()
       local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if icon then
        TimbersRaidSummonerDB.minimap.hide = false
        icon:Show("TimbersRaidSummoner")
    end
end

-- Hide minimap button
local function hideMinimapButton()
    ensureMinimapDB()
       local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if icon then
        TimbersRaidSummonerDB.minimap.hide = true
        icon:Hide("TimbersRaidSummoner")
    end
end

-- Toggle minimap button
local function toggleMinimapButton()
    ensureMinimapDB()
    if TimbersRaidSummonerDB.minimap.hide then
        showMinimapButton()
    else
        hideMinimapButton()
    end
end

-- Open minimap menu
local function openMinimapMenu(anchorFrame)
    ensureMinimapDB()
       if not TRS._minimapDropdown then
        TRS._minimapDropdown = CreateFrame("Frame", "TRS_MinimapDropdown", UIParent, "UIDropDownMenuTemplate")
    end
       local function initMenu(self, level)
        level = level or 1
        if level ~= 1 then return end
               local info = UIDropDownMenu_CreateInfo()
        info.text = "Timber's Raid Summoner"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
               info = UIDropDownMenu_CreateInfo()
        info.text = "Hide minimap button"
        info.notCheckable = true
            info.func = function()
                TRS:HideMinimapButton()
                print("|cFF00FF00Timber's Raid Summoner:|r minimap button hidden. To show it again, type /trs minimap show")
                CloseDropDownMenus()
            end
        UIDropDownMenu_AddButton(info, level)
               info = UIDropDownMenu_CreateInfo()
        info.text = "Close"
        info.notCheckable = true
        info.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)
    end
       UIDropDownMenu_Initialize(TRS._minimapDropdown, initMenu, "MENU")
    ToggleDropDownMenu(1, nil, TRS._minimapDropdown, "cursor", 0, 0)
end

-- Create launcher data object
local function createLauncher()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not ldb then
        return nil
    end

    -- Use the spell_shadow_twilight icon
    -- local iconPath = "Interface\\Icons\\Spell_shadow_twilight"
    -- local iconPath = "Interface\\Icons\\inv_misc_gem_amethyst_02"
    -- Use the addon's bundled minimap icon
    local iconPath = "Interface\\AddOns\\TimbersRaidSummoner\\Media\\icon"

    local launcher = ldb:NewDataObject("TimbersRaidSummoner", {
        type = "launcher",
        text = "Timber's Raid Summoner",
        icon = iconPath,
        OnClick = function(clickedFrame, button)
            if button == "LeftButton" then
                toggleMainWindow()
            elseif button == "RightButton" then
                openMinimapMenu(clickedFrame)
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip then return end
            tooltip:AddLine("Timber's Raid Summoner")
            if TRS.VERSION then
                tooltip:AddLine(tostring(TRS.VERSION), 0.8, 0.8, 0.8)
            end
            tooltip:AddLine(" ")
            tooltip:AddLine("Left-click: Toggle window", 1, 1, 1)
            tooltip:AddLine("Right-click: Options", 1, 1, 1)
        end,
    })
    return launcher
end

-- Register minimap icon
local function registerMinimapIcon()
    ensureMinimapDB()
       local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not icon then
        return
    end
       if not TRS._ldbLauncher then
        TRS._ldbLauncher = createLauncher()
    end
       if not TRS._ldbLauncher then
        return
    end
       -- Register once. LibDBIcon will handle showing/hiding based on the db.
    if not TRS._minimapRegistered then
        icon:Register("TimbersRaidSummoner", TRS._ldbLauncher, TimbersRaidSummonerDB.minimap)
        TRS._minimapRegistered = true
    end
       -- Safety net: ensure right-click opens our menu even if this LibDBIcon version
    -- doesn't forward RightButton clicks to the LDB OnClick handler.
    local btn = icon.GetMinimapButton and icon:GetMinimapButton("TimbersRaidSummoner")
    if btn and not btn._trsHooked then
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:HookScript("OnClick", function(self, button)
            if button == "RightButton" then
                openMinimapMenu(self)
            end
        end)
        btn._trsHooked = true
    end
       if TimbersRaidSummonerDB.minimap.hide then
        icon:Hide("TimbersRaidSummoner")
    else
        icon:Show("TimbersRaidSummoner")
    end
end

-- Initialize minimap button
function TRS:InitializeMinimapButton()
    registerMinimapIcon()
end

-- Show minimap button (public API)
function TRS:ShowMinimapButton()
    showMinimapButton()
    -- Keep settings checkbox in sync if settings UI is present
    if TRS.settingsFrame and TRS.settingsFrame.minimapCheck and TimbersRaidSummonerDB and TimbersRaidSummonerDB.minimap then
        TRS.settingsFrame.minimapCheck:SetChecked(not TimbersRaidSummonerDB.minimap.hide)
    end
end

-- Hide minimap button (public API)
function TRS:HideMinimapButton()
    hideMinimapButton()
    -- Keep settings checkbox in sync if settings UI is present
    if TRS.settingsFrame and TRS.settingsFrame.minimapCheck and TimbersRaidSummonerDB and TimbersRaidSummonerDB.minimap then
        TRS.settingsFrame.minimapCheck:SetChecked(not TimbersRaidSummonerDB.minimap.hide)
    end
end

-- Toggle minimap button (public API)
function TRS:ToggleMinimapButton()
    toggleMinimapButton()
end

-- Handle minimap slash commands
function TRS:HandleMinimapSlash(args)
    args = (args or "")
    args = (strtrim and strtrim(args)) or args
    args = args:lower()
       -- Accept only commands that start with "minimap".
    local head, tail = string.match(args, "^(%S+)%s*(.*)$")
    if head ~= "minimap" then
        return false
    end
       tail = tail or ""
    tail = (strtrim and strtrim(tail)) or tail
       if tail == "" then
        self:ToggleMinimapButton()
        if TimbersRaidSummonerDB and TimbersRaidSummonerDB.minimap and TimbersRaidSummonerDB.minimap.hide then
            print("|cFF00FF00Timber's Raid Summoner:|r minimap button hidden")
        else
            print("|cFF00FF00Timber's Raid Summoner:|r minimap button shown")
        end
        return true
    end
       if tail == "show" then
        self:ShowMinimapButton()
        print("|cFF00FF00Timber's Raid Summoner:|r minimap button shown")
        return true
    end
       if tail == "hide" then
        self:HideMinimapButton()
        print("|cFF00FF00Timber's Raid Summoner:|r minimap button hidden")
        return true
    end
       -- Unrecognized minimap subcommand, but we still consumed "minimap".
    print("|cFF00FF00Timber's Raid Summoner:|r usage: /trs minimap [show|hide]")
    return true
end

-- ========================================================================
-- End Minimap Button Functions
-- ========================================================================

-- Create toast notification for new summon requests
function TRS:CreateToastNotification()
    if TRS.toastFrame then return end
       local toast = CreateFrame("Frame", "TimbersRaidSummonerToast", UIParent, "BackdropTemplate")
    toast:SetSize(350, 80)
    toast:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    toast:SetFrameStrata("DIALOG")
    toast:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    toast:SetBackdropColor(0, 0, 0, 0.9)
    toast:EnableMouse(true)
    toast:SetMovable(false)
    toast:Hide()
       -- Make clickable
    toast:SetScript("OnMouseDown", function(self)
        if TRS.mainFrame and not TRS.mainFrame:IsShown() then
            TRS.mainFrame:Show()
        end
        self:Hide()
    end)
       -- Player name text
    local nameText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOP", toast, "TOP", 0, -15)
    nameText:SetTextColor(1, 0.82, 0, 1) -- Gold color
    toast.nameText = nameText
       -- Request text
    local requestText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    requestText:SetPoint("TOP", nameText, "BOTTOM", 0, -5)
    requestText:SetText("has requested a summon")
    requestText:SetTextColor(1, 1, 1, 1)
       -- Click instruction
    local clickText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clickText:SetPoint("BOTTOM", toast, "BOTTOM", 0, 15)
    clickText:SetText("Click here to see the summoning queue")
    clickText:SetTextColor(0.8, 0.8, 0.8, 1)
       -- Highlight on hover
    toast:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    end)
       toast:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.9)
    end)
       TRS.toastFrame = toast
end

-- Show toast notification
function TRS:ShowToast(playerName)
    if not TRS.toastFrame then
        TRS:CreateToastNotification()
    end
       local toast = TRS.toastFrame
    toast.nameText:SetText(playerName)
    toast:Show()
       -- Auto-hide after 5 seconds
    C_Timer.After(5, function()
        if toast:IsShown() then
            toast:Hide()
        end
    end)
end

-- Toggle raid members panel visibility (collapse/expand)
function TRS:SetRaidListCollapsed(collapsed)
    TRS.raidListCollapsed = collapsed and true or false

    if TimbersRaidSummonerCharDB and TimbersRaidSummonerCharDB.settings then
        TimbersRaidSummonerCharDB.settings.raidListCollapsed = TRS.raidListCollapsed
    end

    if TRS.raidListFrame then
        if TRS.raidListFrame.header then
            if TRS.raidListCollapsed then
                TRS.raidListFrame.header:Hide()
            else
                TRS.raidListFrame.header:Show()
            end
        end
        if TRS.raidListFrame.container then
            if TRS.raidListCollapsed then
                TRS.raidListFrame.container:Hide()
            else
                TRS.raidListFrame.container:Show()
            end
        end
    end

    if TRS.instructionText then
        if TRS.raidListCollapsed then
            TRS.instructionText:Hide()
        else
            TRS.instructionText:Show()
        end
    end

    if TRS.collapseButton then
        local iconPath = TRS.raidListCollapsed and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
        TRS.collapseButton:SetNormalTexture(iconPath)
    end

    TRS:UpdateMainFrameLayout()
end

-- Update main frame size and column positions based on settings visibility and raid list collapse
function TRS:UpdateMainFrameLayout()
    if not TRS.mainFrame then return end

    local topButtonYOffset = -13
    local closeButtonYOffset = -5
    if TRS.raidListCollapsed and not TRS.settingsVisible then
        topButtonYOffset = topButtonYOffset - 26
        closeButtonYOffset = closeButtonYOffset - 26
    end

    local baseWidth = TRS.raidListCollapsed and 260 or 725
    if TRS.settingsVisible then
        baseWidth = baseWidth + 396
    end
    TRS.mainFrame:SetSize(baseWidth, 602)

    if TRS.collapseButton then
        TRS.collapseButton:ClearAllPoints()
        TRS.collapseButton:SetPoint("TOPRIGHT", TRS.mainFrame, "TOPRIGHT", -62, topButtonYOffset)
    end
    if TRS.gearButton then
        TRS.gearButton:ClearAllPoints()
        TRS.gearButton:SetPoint("TOPRIGHT", TRS.mainFrame, "TOPRIGHT", -40, topButtonYOffset)
    end
    if TRS.closeButton then
        TRS.closeButton:ClearAllPoints()
        TRS.closeButton:SetPoint("TOPRIGHT", TRS.mainFrame, "TOPRIGHT", -5, closeButtonYOffset)
    end

    if TRS.summonQueueFrame and TRS.summonQueueFrame.header and TRS.summonQueueFrame.container then
        local queueX = TRS.raidListCollapsed and 20 or 477
        TRS.summonQueueFrame.header:ClearAllPoints()
        TRS.summonQueueFrame.header:SetPoint("TOPLEFT", TRS.mainFrame, "TOPLEFT", queueX, -70)
        TRS.summonQueueFrame.container:ClearAllPoints()
        TRS.summonQueueFrame.container:SetPoint("TOPLEFT", TRS.mainFrame, "TOPLEFT", queueX, -90)
    end

    if TRS.settingsFrame and TRS.settingsFrame.frame then
        local settingsX = TRS.raidListCollapsed and 260 or 717
        TRS.settingsFrame.frame:ClearAllPoints()
        TRS.settingsFrame.frame:SetPoint("TOPLEFT", TRS.mainFrame, "TOPLEFT", settingsX, -70)
    end
end

-- Create the main frame with three scrollable columns
function TRS:CreateMainFrame()
    -- Main container frame (starts smaller, expands when settings shown)
    local mainFrame = CreateFrame("Frame", "TimbersRaidSummonerMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(725, 602) -- Start with just columns 1 and 2 (20 + 447 + 10 + 230 + 10 = 717)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.9)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()
       -- OnUpdate to track active summons continuously
    mainFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Update activeSummons table by checking all members for active casts/channels
        local numMembers = GetNumGroupMembers()
        local isRaid = IsInRaid()
        local stateChanged = false  -- Track if we need to update UI
               if numMembers > 0 then
            -- Check player first
            local playerName = UnitName("player")
            local channelName = UnitChannelInfo("player")
            local castName = UnitCastingInfo("player")
            local isCurrentlyChanneling = (channelName or castName) ~= nil
                       if isCurrentlyChanneling then
                local spellName = channelName or castName
                local lowerName = string.lower(spellName)
                if string.find(lowerName, "summon") or string.find(lowerName, "meeting") or string.find(lowerName, "ritual") then
                    -- Use currentlySummoning if we know who we're summoning, otherwise try target
                    local targetName = currentlySummoning or UnitName("playertarget")
                    if targetName and activeSummons[playerName] ~= targetName then
                        activeSummons[playerName] = targetName
                        stateChanged = true
                    end
                    wasChanneling[playerName] = true
                else
                    if activeSummons[playerName] then
                        activeSummons[playerName] = nil
                        stateChanged = true
                    end
                    wasChanneling[playerName] = false
                end
            else
                -- Don't clear activeSummons if currentlySummoning is set (handles cast-to-channel transition gap)
                if activeSummons[playerName] and not currentlySummoning then
                    activeSummons[playerName] = nil
                    stateChanged = true
                end
                wasChanneling[playerName] = false
            end
                       -- Check other raid/party members
            for j = 1, (isRaid and numMembers or numMembers - 1) do
                local summoner = isRaid and "raid"..j or "party"..j
                local summonerUnitName = UnitName(summoner)
                               if summonerUnitName then
                    channelName = UnitChannelInfo(summoner)
                    castName = UnitCastingInfo(summoner)
                    isCurrentlyChanneling = (channelName or castName) ~= nil
                                       if isCurrentlyChanneling then
                        local spellName = channelName or castName
                        local lowerName = string.lower(spellName)
                        if string.find(lowerName, "summon") or string.find(lowerName, "meeting") or string.find(lowerName, "ritual") then
                            -- Only store target if this is a NEW channel (wasn't channeling last frame)
                            if not wasChanneling[summonerUnitName] then
                                local targetName = UnitName(summoner .. "target")
                                if targetName then
                                    activeSummons[summonerUnitName] = targetName
                                    stateChanged = true
                                end
                            end
                            -- If already channeling, keep the existing target stored
                        else
                            if activeSummons[summonerUnitName] then
                                activeSummons[summonerUnitName] = nil
                                stateChanged = true
                            end
                            wasChanneling[summonerUnitName] = false
                        end
                        wasChanneling[summonerUnitName] = true
                    else
                        if activeSummons[summonerUnitName] then
                            activeSummons[summonerUnitName] = nil
                            stateChanged = true
                        end
                        wasChanneling[summonerUnitName] = false
                    end
                end
            end
        end
               -- Only update UI when channeling state actually changes
        if stateChanged and TRS.mainFrame and TRS.mainFrame:IsShown() and not InCombatLockdown() then
            TRS:UpdateRaidList()
            TRS:UpdateSummonQueue()
        end
    end)

    TRS.mainFrame = mainFrame

    -- Register with UI special frames so Escape closes the window
    table.insert(UISpecialFrames, "TimbersRaidSummonerMainFrame")

    -- Title texture (like FieldGuide)
    local titleTexture = mainFrame:CreateTexture(nil, "OVERLAY")
    titleTexture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTexture:SetSize(500, 69)
    titleTexture:SetPoint("TOP", mainFrame, "TOP", 0, 12)

    -- Title text
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", titleTexture, "TOP", 0, -16)
    title:SetText("Timber's Raid Summoner")
    title:SetTextColor(1, 0.82, 0, 1) -- Gold color

    -- Collapse/expand button (raid members panel)
    local collapseButton = CreateFrame("Button", nil, mainFrame)
    collapseButton:SetSize(20, 20)
    collapseButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -62, -13)
    collapseButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    collapseButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    collapseButton:SetScript("OnClick", function()
        TRS:SetRaidListCollapsed(not TRS.raidListCollapsed)
    end)
    collapseButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if TRS.raidListCollapsed then
            GameTooltip:SetText("Expand Raid Members")
        else
            GameTooltip:SetText("Collapse Raid Members")
        end
        GameTooltip:Show()
    end)
    collapseButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    TRS.collapseButton = collapseButton

    -- Gear button (settings toggle)
    local gearButton = CreateFrame("Button", nil, mainFrame)
    gearButton:SetSize(20, 20)
    gearButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -40, -13)
    gearButton:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    gearButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    gearButton:SetScript("OnClick", function()
        TRS:ToggleSettings()
    end)
    gearButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle Settings")
        GameTooltip:Show()
    end)
    gearButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    TRS.gearButton = gearButton

    -- Info bar below title
    -- Soul Shard icon
    local shardIcon = mainFrame:CreateTexture(nil, "OVERLAY")
    shardIcon:SetSize(16, 16)
    shardIcon:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -40)
    shardIcon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Amethyst_02") -- Soul Shard icon
    TRS.shardIcon = shardIcon

    local shardCountText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shardCountText:SetPoint("LEFT", shardIcon, "RIGHT", 5, 0)
    shardCountText:SetText("Soul Shards: 0")
    TRS.shardCountText = shardCountText

    local instructionText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructionText:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -20, -40)
    instructionText:SetText("Left click to select, right click to summon, middle click to remove")
    TRS.instructionText = instructionText

    -- Close button
    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)
    TRS.closeButton = closeButton

    -- Column 1: Raid Members List (360px wide, 400px tall)
    TRS:CreateRaidListColumn(mainFrame)

    -- Column 2: Summon Queue (160px wide, 400px tall)
    TRS:CreateSummonQueueColumn(mainFrame)

    -- Column 3: Settings (360px wide, 400px tall) - hidden by default
    TRS:CreateSettingsColumn(mainFrame)

    -- Ensure initial state matches saved per-character setting
    local savedCollapsed = false
    if TimbersRaidSummonerCharDB and TimbersRaidSummonerCharDB.settings then
        savedCollapsed = TimbersRaidSummonerCharDB.settings.raidListCollapsed and true or false
    end
    TRS:SetRaidListCollapsed(savedCollapsed)
end

-- Column 1: Raid Members List
function TRS:CreateRaidListColumn(parent)
    local xOffset = 20
    local yOffset = -70 -- 20px gap below info bar

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    header:SetText("Raid Members")

    -- Container frame for border (includes scrollbar)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(448, 494)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset - 20)
    container:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Background for entire container
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(container)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    -- Scroll frame (5px padding inside border)
    local scrollFrame = CreateFrame("ScrollFrame", "TimbersRaidSummonerRaidListScroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(416, 484)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(400, 484)
    scrollFrame:SetScrollChild(content)

    TRS.raidListFrame = {
        header = header,
        container = container,
        scrollFrame = scrollFrame,
        content = content,
        buttons = {}
    }

    TRS:UpdateRaidList()
end

-- Column 2: Summon Queue
function TRS:CreateSummonQueueColumn(parent)
    local xOffset = 477 -- 20 + 447 + 10
    local yOffset = -70 -- 20px gap below info bar

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    header:SetText("Summon Queue")

    -- Container frame for border (includes scrollbar)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(230, 494)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset - 20)
    container:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Background for entire container
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(container)
    bg:SetColorTexture(0.1, 0.15, 0.1, 0.5)

    -- Scroll frame (5px padding inside border)
    local scrollFrame = CreateFrame("ScrollFrame", "TimbersRaidSummonerSummonQueueScroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(200, 484)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(180, 484)
    scrollFrame:SetScrollChild(content)

    TRS.summonQueueFrame = {
        header = header,
        container = container,
        scrollFrame = scrollFrame,
        content = content,
        buttons = {}
    }

    TRS:UpdateSummonQueue()
end

-- Column 3: Keywords List
-- Column 3: Settings Panel
function TRS:CreateSettingsColumn(parent)
    local xOffset = 717 -- 20 + 447 + 10 + 230 + 10
    local yOffset = -70 -- 20px gap below info bar

    -- Settings container frame
    local settingsFrame = CreateFrame("Frame", nil, parent)
    settingsFrame:SetSize(385, 430)
    settingsFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    settingsFrame:Hide()

    -- Header
    local header = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 0, 0)
    header:SetText("Settings")
       -- Version text
    local versionText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", 0, 0)
    versionText:SetText(tostring(TRS.VERSION))
    versionText:SetTextColor(0.7, 0.7, 0.7)

    -- Container frame for border (includes scrollbar)
    local container = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
    container:SetSize(385, 494)
    container:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 0, -20)
    container:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Background for entire container
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(container)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    -- Scroll frame for settings (5px padding inside border)
    local scrollFrame = CreateFrame("ScrollFrame", "TimbersRaidSummonerSettingsScroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(354, 484)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(340, 905)
    scrollFrame:SetScrollChild(content)

    local yPos = -10

    -- Keywords Section
    local kwHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kwHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    kwHeader:SetText("Keywords")
    yPos = yPos - 20

    -- Keyword explanation text
    local kwExplain = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kwExplain:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    kwExplain:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, yPos)
    kwExplain:SetJustifyH("LEFT")
    kwExplain:SetText("Use * prefix to match anywhere (e.g., *123). Plain text matches exact message. Use ^ or $ for regex patterns.")
    kwExplain:SetTextColor(0.8, 0.8, 0.8)
    yPos = yPos - 30

    -- Keyword input
    local inputBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    inputBox:SetSize(200, 25)
    inputBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(50)

    local addButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addButton:SetSize(60, 25)
    addButton:SetPoint("LEFT", inputBox, "RIGHT", 5, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function()
        local keyword = inputBox:GetText()
        if keyword and keyword ~= "" then
            table.insert(db.keywords, keyword)
            inputBox:SetText("")
            TRS:UpdateSettingsKeywords()
        end
    end)
    yPos = yPos - 31

    -- Keywords list container with border
    local kwContainer = CreateFrame("Frame", nil, content, "BackdropTemplate")
    kwContainer:SetSize(319, 163)
    kwContainer:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    kwContainer:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    kwContainer:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Background for keyword container
    local kwBg = kwContainer:CreateTexture(nil, "BACKGROUND")
    kwBg:SetAllPoints(kwContainer)
    kwBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)

    -- Keywords list scroll frame (padding inside border to avoid overlap)
    local kwScrollFrame = CreateFrame("ScrollFrame", nil, kwContainer, "UIPanelScrollFrameTemplate")
    kwScrollFrame:SetSize(286, 148)
    kwScrollFrame:SetPoint("TOPLEFT", kwContainer, "TOPLEFT", 5, -6)

    -- Content frame inside scroll frame
    local kwListFrame = CreateFrame("Frame", nil, kwScrollFrame)
    kwListFrame:SetSize(286, 150)
    kwScrollFrame:SetScrollChild(kwListFrame)

    -- Restore Defaults button
    yPos = yPos - 169
    local restoreButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    restoreButton:SetSize(120, 25)
    restoreButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, yPos)
    restoreButton:SetText("Restore Defaults")
    restoreButton:SetScript("OnClick", function()
        StaticPopup_Show("TIMBERSRAIDSUMMONER_RESTORE_KEYWORDS")
    end)
    yPos = yPos - 40

    -- Divider
    local divider1 = content:CreateTexture(nil, "ARTWORK")
    divider1:SetSize(320, 1)
    divider1:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    divider1:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    yPos = yPos - 15

    -- Messages Section
    local msgHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    msgHeader:SetText("Messages")
    yPos = yPos - 25

    -- Send raid message checkbox
    local raidMsgCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    raidMsgCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    raidMsgCheck:SetChecked(db.settings.sendRaidMessage)
    raidMsgCheck:SetScript("OnClick", function(self)
        db.settings.sendRaidMessage = self:GetChecked()
    end)
    local raidMsgCheckLabel = raidMsgCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidMsgCheckLabel:SetPoint("LEFT", raidMsgCheck, "RIGHT", 5, 0)
    raidMsgCheckLabel:SetText("Send raid message when casting")
    yPos = yPos - 30

    -- Send say message checkbox
    local sayMsgCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    sayMsgCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    sayMsgCheck:SetChecked(db.settings.sendSayMessage)
    sayMsgCheck:SetScript("OnClick", function(self)
        db.settings.sendSayMessage = self:GetChecked()
    end)
    local sayMsgCheckLabel = sayMsgCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sayMsgCheckLabel:SetPoint("LEFT", sayMsgCheck, "RIGHT", 5, 0)
    sayMsgCheckLabel:SetText("Send a '/s' message when casting")
    yPos = yPos - 30

    -- Auto whisper checkbox
    local whisperCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    whisperCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    whisperCheck:SetChecked(db.settings.autoWhisper)
    whisperCheck:SetScript("OnClick", function(self)
        db.settings.autoWhisper = self:GetChecked()
    end)
    local whisperLabel = whisperCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whisperLabel:SetPoint("LEFT", whisperCheck, "RIGHT", 5, 0)
    whisperLabel:SetText("Auto-whisper summoned players")
    yPos = yPos - 30

    -- Raid message label
    local raidMsgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidMsgLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    raidMsgLabel:SetText("Raid message:")
    yPos = yPos - 20

    local raidMsgBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    raidMsgBox:SetSize(300, 25)
    raidMsgBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    raidMsgBox:SetAutoFocus(false)
    raidMsgBox:SetText(db.settings.raidMessage)
    raidMsgBox:SetScript("OnTextChanged", function(self)
        db.settings.raidMessage = self:GetText()
    end)
    yPos = yPos - 35

    -- Say message label
    local sayMsgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sayMsgLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    sayMsgLabel:SetText("Say message:")
    yPos = yPos - 20

    local sayMsgBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    sayMsgBox:SetSize(300, 25)
    sayMsgBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    sayMsgBox:SetAutoFocus(false)
    sayMsgBox:SetText(db.settings.sayMessage or "Summoning %s")
    sayMsgBox:SetScript("OnTextChanged", function(self)
        db.settings.sayMessage = self:GetText()
    end)
    yPos = yPos - 35

    -- Whisper message label
    local whisperMsgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whisperMsgLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    whisperMsgLabel:SetText("Whisper message:")
    yPos = yPos - 20

    local whisperMsgBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    whisperMsgBox:SetSize(300, 25)
    whisperMsgBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    whisperMsgBox:SetAutoFocus(false)
    whisperMsgBox:SetText(db.settings.whisperMessage)
    whisperMsgBox:SetScript("OnTextChanged", function(self)
        db.settings.whisperMessage = self:GetText()
    end)
    yPos = yPos - 55

    -- Interface section divider
    local divider3 = content:CreateTexture(nil, "ARTWORK")
    divider3:SetSize(320, 1)
    divider3:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    divider3:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    yPos = yPos - 15

    -- Interface header
    local interfaceHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interfaceHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    interfaceHeader:SetText("Interface")
    yPos = yPos - 30

    -- Shaman color dropdown
    local shamanColorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shamanColorLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    shamanColorLabel:SetText("Shaman Class Color:")
    yPos = yPos - 20

    local shamanColorDropdown = CreateFrame("Frame", "TRS_ShamanColorDropdown", content, "UIDropDownMenuTemplate")
    shamanColorDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", -5, yPos)
    UIDropDownMenu_SetWidth(shamanColorDropdown, 150)

    local shamanColorOptions = {
        { value = "default", text = "Expansion Default", color = nil },
        { value = "blue", text = "Blue", color = "0070DE" },
        { value = "pink", text = "Pink", color = "F58CBA" }
    }

    local function GetExpansionDefaultColor()
        if TRS.Client.shamanDefaultColor == "pink" then
            return "F58CBA"
        else
            return "0070DE" -- blue
        end
    end

    local function GetShamanColorText(value, useColor)
        for _, option in ipairs(shamanColorOptions) do
            if option.value == value then
                if useColor then
                    local color = option.color or GetExpansionDefaultColor()
                    return "|cFF" .. color .. option.text .. "|r"
                end
                return option.text
            end
        end
        return "Expansion Default"
    end

    UIDropDownMenu_SetText(shamanColorDropdown, GetShamanColorText(db.settings.shamanColor, true))

    UIDropDownMenu_Initialize(shamanColorDropdown, function(self, level)
        for _, option in ipairs(shamanColorOptions) do
            local info = UIDropDownMenu_CreateInfo()
            local color = option.color or GetExpansionDefaultColor()
            info.text = "|cFF" .. color .. option.text .. "|r"
            info.value = option.value
            info.checked = (db.settings.shamanColor == option.value)
            info.func = function()
                db.settings.shamanColor = option.value
                UIDropDownMenu_SetText(shamanColorDropdown, "|cFF" .. color .. option.text .. "|r")
                CloseDropDownMenus()
                if TRS.mainFrame and TRS.mainFrame:IsShown() then
                    TRS:UpdateRaidList()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    yPos = yPos - 30

    yPos = yPos - 10  -- Extra spacing before slider section

    -- Range opacity slider
    local rangeOpacityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rangeOpacityLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    rangeOpacityLabel:SetText("Range opacity (out-of-range):")
    yPos = yPos - 20

    local rangeOpacitySlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    rangeOpacitySlider:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yPos)
    rangeOpacitySlider:SetMinMaxValues(0.1, 1.0)
    rangeOpacitySlider:SetValueStep(0.05)
    rangeOpacitySlider:SetObeyStepOnDrag(true)
    rangeOpacitySlider:SetWidth(200)
    rangeOpacitySlider:SetHeight(16)
    rangeOpacitySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local rangeOpacitySliderBg = rangeOpacitySlider:CreateTexture(nil, "BACKGROUND")
    rangeOpacitySliderBg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    rangeOpacitySliderBg:SetPoint("CENTER", rangeOpacitySlider, "CENTER", 0, 0)
    rangeOpacitySliderBg:SetSize(200, 8)

    local rangeOpacityValue = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    rangeOpacityValue:SetSize(40, 20)
    rangeOpacityValue:SetPoint("LEFT", rangeOpacitySlider, "RIGHT", 10, 0)
    rangeOpacityValue:SetAutoFocus(false)
    rangeOpacityValue:SetNumeric(true)
    rangeOpacityValue:SetMaxLetters(3)

    local function ClampOpacity(value)
        value = tonumber(value) or 0.4
        if value < 0.1 then value = 0.1 end
        if value > 1.0 then value = 1.0 end
        return value
    end

    local function UpdateRangeOpacity(value)
        value = ClampOpacity(value)
        db.settings.rangeOpacity = value
        rangeOpacitySlider:SetValue(value)
        rangeOpacityValue:SetText(tostring(math.floor(value * 100 + 0.5)))
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
        end
    end

    rangeOpacitySlider:SetScript("OnValueChanged", function(self, value)
        if rangeOpacityValue:HasFocus() then
            return
        end
        UpdateRangeOpacity(value)
    end)

    rangeOpacityValue:SetScript("OnEnterPressed", function(self)
        local percent = tonumber(self:GetText()) or 40
        UpdateRangeOpacity(percent / 100)
        self:ClearFocus()
    end)
    rangeOpacityValue:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        UpdateRangeOpacity(db.settings.rangeOpacity or 0.4)
    end)

    UpdateRangeOpacity(db.settings.rangeOpacity or 0.4)
    yPos = yPos - 30

    -- Extra spacing below Interface group
    yPos = yPos - 20

    -- Misc section divider
    local divider4 = content:CreateTexture(nil, "ARTWORK")
    divider4:SetSize(320, 1)
    divider4:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    divider4:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    yPos = yPos - 20

    -- Misc header
    local miscHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    miscHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    miscHeader:SetText("Misc")
    yPos = yPos - 25

    -- Play sound checkbox
    local soundCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    soundCheck:SetChecked(db.settings.playSoundOnAdd)
    soundCheck:SetScript("OnClick", function(self)
        db.settings.playSoundOnAdd = self:GetChecked()
    end)
    local soundLabel = soundCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundLabel:SetPoint("LEFT", soundCheck, "RIGHT", 5, 0)
    soundLabel:SetText("Play sound when player added to queue")
    yPos = yPos - 25

    local soundTestButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    soundTestButton:SetSize(50, 20)
    soundTestButton:SetPoint("TOPLEFT", content, "TOPLEFT", 50, yPos)
    soundTestButton:SetText("Test")
    soundTestButton:SetScript("OnClick", function()
        PlaySound(8959)
    end)
    yPos = yPos - 25

    -- Show toast notification checkbox
    local toastCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    toastCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    toastCheck:SetChecked(db.settings.showToastNotification)
    toastCheck:SetScript("OnClick", function(self)
        db.settings.showToastNotification = self:GetChecked()
    end)
    local toastLabel = toastCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toastLabel:SetPoint("LEFT", toastCheck, "RIGHT", 5, 0)
    toastLabel:SetText("Show popup notification when player added to queue")
    yPos = yPos - 25

    local toastTestButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    toastTestButton:SetSize(50, 20)
    toastTestButton:SetPoint("TOPLEFT", content, "TOPLEFT", 50, yPos)
    toastTestButton:SetText("Test")
    toastTestButton:SetScript("OnClick", function(self)
        if db.settings.playSoundOnAdd then
            PlaySound(8959)
        end
        TRS:ShowToast("TestPlayer")
        self:Disable()
        C_Timer.After(5, function()
            self:Enable()
        end)
    end)
    yPos = yPos - 25

    -- Show loaded message checkbox
    local loadedMsgCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    loadedMsgCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    loadedMsgCheck:SetChecked(db.settings.showLoadedMessage)
    loadedMsgCheck:SetScript("OnClick", function(self)
        db.settings.showLoadedMessage = self:GetChecked()
    end)
    local loadedMsgLabel = loadedMsgCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loadedMsgLabel:SetPoint("LEFT", loadedMsgCheck, "RIGHT", 5, 0)
    loadedMsgLabel:SetText("Show 'addon loaded' message on login")

    -- Minimap show/hide checkbox
    local minimapCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos - 30)
    -- Ensure minimap DB exists and set checked state accordingly
    ensureMinimapDB()
    minimapCheck:SetChecked(not TimbersRaidSummonerDB.minimap.hide)
    minimapCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            TRS:ShowMinimapButton()
        else
            TRS:HideMinimapButton()
        end
    end)
    local minimapLabel = minimapCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 5, 0)
    minimapLabel:SetText("Show minimap button")

    yPos = yPos - 30

    TRS.settingsFrame = {
        frame = settingsFrame,
        kwListFrame = kwListFrame,
        kwButtons = {},
        minimapCheck = minimapCheck
    }

    TRS:UpdateSettingsKeywords()
end

-- Lightweight refresh of raid list visuals (doesn't hide/reposition buttons)
function TRS:RefreshRaidListVisuals()
    if not TRS.raidListFrame or not TRS.raidListFrame.buttons then return end
       local buttons = TRS.raidListFrame.buttons
       -- Update only the visual state of visible buttons
    for _, button in ipairs(buttons) do
        if button:IsShown() and button.memberName then
            local memberName = button.memberName
                       -- Check if this member is being summoned
            local isBeingSummoned = false
            local summonerName = nil
            for summoner, target in pairs(activeSummons) do
                if target == memberName then
                    isBeingSummoned = true
                    summonerName = summoner
                    break
                end
            end
                       -- Update display
            if button.isSummoning or isBeingSummoned then
                button.levelText:SetText("Summoning...")
                button.levelText:SetTextColor(0, 1, 0)
            else
                -- Restore original level text (stored when button was created)
                if button.originalLevel then
                    button.levelText:SetText(button.originalLevel)
                    button.levelText:SetTextColor(1, 1, 1)
                end
            end
                       button.summonerName = summonerName
        end
    end
end

-- Update raid members list
function TRS:UpdateRaidList()
    if not TRS.raidListFrame then return end

    local content = TRS.raidListFrame.content
    local buttons = TRS.raidListFrame.buttons
    local groupHeaders = TRS.raidListFrame.groupHeaders

    -- Initialize group headers if needed
    if not groupHeaders then
        groupHeaders = {}
        TRS.raidListFrame.groupHeaders = groupHeaders
    end

    -- Clear existing buttons
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end

    -- Hide all group headers initially
    for _, header in ipairs(groupHeaders) do
        header:Hide()
    end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()

    -- Build member data by group
    local groups = {}
    for g = 1, 8 do
        groups[g] = {}
    end

    for i = 1, numMembers do
        local name, rank, subgroup, level, class, classToken
        local unitId
        local isOnline = true
        local isLeader = false
        local isAssistant = false
        if isRaid then
            local fileName, zone, online, isDead, role, isML
            name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
            unitId = "raid"..i
            _, classToken = UnitClass(unitId)
            isOnline = UnitIsConnected(unitId)
            isLeader = (rank == 2)  -- rank 2 = leader
            isAssistant = (rank == 1)  -- rank 1 = assistant
            -- Fallback to UnitLevel if GetRaidRosterInfo didn't provide it
            if not level or level == 0 then
                level = UnitLevel(unitId)
            end
        else
            if i == 1 then
                name = UnitName("player")
                class, classToken = UnitClass("player")
                level = UnitLevel("player")
                unitId = "player"
                subgroup = 1
                isOnline = true
                isLeader = UnitIsGroupLeader("player")
            elseif i <= numMembers then
                unitId = "party"..(i-1)
                name = UnitName(unitId)
                class, classToken = UnitClass(unitId)
                level = UnitLevel(unitId)
                subgroup = 1
                isOnline = UnitIsConnected(unitId)
                isLeader = UnitIsGroupLeader(unitId)
            end
        end

        if name and subgroup then
            table.insert(groups[subgroup], {
                name = name,
                unitId = unitId,
                level = level,
                class = class,
                classToken = classToken,
                isOnline = isOnline,
                isLeader = isLeader,
                isAssistant = isAssistant
            })
        end
    end

    -- TestMode hook: augment group data with fake members
    if TRS.TestMode and TRS.TestMode.active and TRS.TestMode.AugmentGroups then
        TRS.TestMode:AugmentGroups(groups)
    end

    -- Layout constants
    local buttonHeight = 20
    local headerHeight = 18
    local groupSpacing = 3
    local column1X = 0
    local column2X = 210
    local columnWidth = 200

    local buttonIndex = 0

    -- Display groups in rows: 1-2, 3-4, 5-6, 7-8
    for groupNum = 1, 8 do
        -- Calculate row (0-3) and column (1 or 2)
        local row = math.floor((groupNum - 1) / 2)
        local col = ((groupNum - 1) % 2) + 1

        local xPos = (col == 1) and column1X or column2X

        -- Calculate Y offset based on row
        -- Each row contains: header + 5 buttons + spacing
        local rowHeight = headerHeight + (5 * buttonHeight) + groupSpacing
        local yOffset = row * rowHeight

        -- Create or show group header
        local header = groupHeaders[groupNum]
        if not header then
            header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            groupHeaders[groupNum] = header
        end
        header:SetPoint("TOPLEFT", content, "TOPLEFT", xPos, -yOffset)
        header:SetText("Group " .. groupNum)
        header:SetTextColor(0.7, 0.7, 0.7)
        header:Show()

        -- Display members in this group (up to 5 slots)
        for slot = 1, 5 do
            buttonIndex = buttonIndex + 1
            local member = groups[groupNum][slot]

            local button = buttons[buttonIndex]
            if not button then
                button = CreateFrame("Button", "TRSRaidButton"..buttonIndex, content, "SecureUnitButtonTemplate")
                button:SetSize(columnWidth, buttonHeight)
                button:SetNormalTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                button:GetNormalTexture():SetAlpha(0.3)
                button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                               -- Register for clicks
                button:RegisterForClicks("AnyUp")
                button:EnableMouse(true)
                               -- PostClick handler for UI updates (doesn't block secure actions)
                button:SetScript("PostClick", function(self, btn)
                    TRS:DebugChat("Roster click: " .. btn .. " target=" .. tostring(self.playerName)
                        .. "; roster summons do not request chat announcements")
                    if btn == "RightButton" and self.playerName and TRS:CanSummon() and self.storedIsOnline then
                        -- Don't allow clicking if already casting/channeling
                        if UnitCastingInfo("player") or UnitChannelInfo("player") then
                            return
                        end
                                               -- Clear any previous summoning state before setting new one
                        if currentlySummoning and currentlySummoning ~= self.playerName then
                            TRS:ClearSummoningState(currentlySummoning)
                        end
                                               currentlySummoning = self.playerName
                        summonFromQueue = false
                        TRS:UpdateSummoningStateUI(self.playerName, true, UnitName("player"))
                        TRS:BroadcastSummoningState(self.playerName, true)
                    elseif btn == "LeftButton" and self.isFake and self.playerName
                            and TRS.TestMode and TRS.TestMode.active then
                        if currentlySummoning and currentlySummoning ~= self.playerName then
                            TRS:ClearSummoningState(currentlySummoning)
                        end
                        currentlySummoning = self.playerName
                        summonFromQueue = false
                        TRS:UpdateSummoningStateUI(self.playerName, true, UnitName("player"))
                    end
                end)

                -- Name text (left-aligned)
                local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nameText:SetPoint("LEFT", button, "LEFT", 5, 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetWidth(100)
                button.nameText = nameText

                -- Leader icon (crown) - to the left of level
                local leaderIcon = button:CreateTexture(nil, "OVERLAY")
                leaderIcon:SetSize(12, 12)
                leaderIcon:SetPoint("LEFT", nameText, "RIGHT", -7, 0)
                leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                leaderIcon:Hide()
                button.leaderIcon = leaderIcon

                -- Addon presence dot (circular, shown when member has TRS installed)
                local addonDot = button:CreateTexture(nil, "OVERLAY")
                addonDot:SetSize(8, 8)
                addonDot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                addonDot:SetVertexColor(0.85, 0.35, 1.0)
                addonDot:SetPoint("RIGHT", nameText, "RIGHT", 0, 0)
                addonDot:Hide()
                button.addonDot = addonDot

                -- Level text (centered)
                local levelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                levelText:SetPoint("LEFT", nameText, "RIGHT", 5, 0)
                levelText:SetJustifyH("CENTER")
                levelText:SetWidth(25)
                button.levelText = levelText

                -- Class text (right-aligned)
                local classText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                classText:SetPoint("LEFT", levelText, "RIGHT", 5, 0)
                classText:SetJustifyH("LEFT")
                classText:SetWidth(60)
                button.classText = classText
                               -- Add tooltip handlers
                button:SetScript("OnEnter", function(self)
                    if self.unitId or self.isFake then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if GameTooltip.TRSAddonDot then GameTooltip.TRSAddonDot:Hide() end
                        GameTooltip:SetText(self.playerName, 1, 1, 1)
                        if self.unitId then
                                               -- Show zone/location using C_Map for detailed subzone info
                            local zoneText = TRS:GetFormattedZoneForUnit(self.unitId, self.playerName)
                            if zoneText then
                                GameTooltip:AddLine(zoneText, 0.8, 0.8, 0.8)
                            elseif IsInRaid() then
                                -- Fallback to raid roster info if C_Map didn't work
                                local numMembers = GetNumGroupMembers()
                                for i = 1, numMembers do
                                    local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
                                    if name == self.playerName then
                                        if zone and zone ~= "" then
                                            GameTooltip:AddLine(zone, 0.8, 0.8, 0.8)
                                        else
                                            GameTooltip:AddLine("Zone: Unknown", 0.6, 0.6, 0.6)
                                        end
                                        break
                                    end
                                end
                            else
                                GameTooltip:AddLine("Zone: Unknown", 0.6, 0.6, 0.6)
                            end
                        end
                                               -- Show who is summoning them if applicable
                        if self.summonerName then
                            GameTooltip:AddLine(" ", 1, 1, 1)
                            local summonerText = "Being summoned by " .. self.summonerName
                            GameTooltip:AddLine(summonerText, 0, 1, 0)
                        end
                        -- Show addon indicator if this member has TRS installed
                        if TRS.hasAddon[self.playerName] then
                            GameTooltip:AddLine(" ", 1, 1, 1)
                            -- Leading spaces reserve room for the dot texture
                            GameTooltip:AddLine("    Has TRS Addon Installed", 0.85, 0.35, 1.0)
                            local lineNum = GameTooltip:NumLines()
                            local lineFS = _G["GameTooltipTextLeft" .. lineNum]
                            if lineFS then
                                if not GameTooltip.TRSAddonDot then
                                    local d = GameTooltip:CreateTexture(nil, "OVERLAY")
                                    d:SetSize(10, 10)
                                    d:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                                    d:SetVertexColor(0.85, 0.35, 1.0)
                                    GameTooltip.TRSAddonDot = d
                                end
                                GameTooltip.TRSAddonDot:ClearAllPoints()
                                GameTooltip.TRSAddonDot:SetPoint("LEFT", lineFS, "LEFT", 0, 0)
                                GameTooltip.TRSAddonDot:Show()
                            end
                        end
                                               GameTooltip:Show()
                    end
                end)
                               button:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)

                buttons[buttonIndex] = button
            end

            -- Position button (yOffset + header height + slot position)
            local buttonY = yOffset + headerHeight + ((slot - 1) * buttonHeight)
            button:SetPoint("TOPLEFT", content, "TOPLEFT", xPos, -buttonY)

            if member then
                -- Store the unit ID and name on the button
                button.unitId = member.unitId
                button.playerName = member.name
                button.memberName = member.name  -- For RefreshRaidListVisuals
                               -- Store level, class, and classToken for later restoration
                button.storedLevel = member.level
                button.storedClass = member.class
                button.storedClassToken = member.classToken
                button.storedIsOnline = member.isOnline
                button.isFake = member.isFake
                button.originalLevel = tostring(member.level or 0)  -- For RefreshRaidListVisuals

                -- Set unit attribute and click behaviors
                if not InCombatLockdown() then
                    button:SetAttribute("unit", member.unitId)
                    button:SetAttribute("type1", "target")  -- Left click = target
                    button:SetAttribute("type2", "macro")   -- Right click = macro (for summoning)
                                       -- Get localized spell name for Ritual of Summoning
                    local summonSpellName = TRS.GetSpellInfo(RITUAL_OF_SUMMONING_ID) or "Ritual of Summoning"
                                       -- Build macro text - only include /s if not from queue (queue clicks handled in PostClick)
                    local macroText = "/target " .. member.name .. "\n/cast " .. summonSpellName
                    button:SetAttribute("macrotext2", macroText)
                end

                -- Set individual column texts
                button.nameText:SetText(member.name)

                -- Show addon dot right after the name text if this member has TRS installed
                if button.addonDot then
                    if TRS.hasAddon[member.name] then
                        button.addonDot:ClearAllPoints()
                        button.addonDot:SetPoint("LEFT", button.nameText, "LEFT", button.nameText:GetStringWidth() + 3, 0)
                        button.addonDot:Show()
                    else
                        button.addonDot:Hide()
                    end
                end

                -- Show leader crown or assistant star, or hide if neither
                if member.isLeader then
                    button.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                    button.leaderIcon:Show()
                elseif member.isAssistant then
                    button.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                    button.leaderIcon:Show()
                else
                    button.leaderIcon:Hide()
                end

                -- Check if this member is being summoned by anyone in activeSummons
                local isBeingSummoned = false
                local summonerName = nil

                -- First check if local player is summoning this member
                if currentlySummoning == member.name then
                    isBeingSummoned = true
                    summonerName = UnitName("player")
                else
                    -- Check activeSummons for other summoners
                    for summoner, target in pairs(activeSummons) do
                        if target == member.name then
                            isBeingSummoned = true
                            summonerName = summoner
                            break
                        end
                    end
                end
                               -- Update summoner name if detected via channeling (for tooltip)
                if isBeingSummoned and summonerName then
                    button.summonerName = summonerName
                elseif not isBeingSummoned and not button.isSummoning then
                    button.summonerName = nil
                end
                               -- Check if this member is being summoned (either via addon tracking OR detected channeling)
                local showSummoning = button.isSummoning or isBeingSummoned

                -- Only update level/class if not currently summoning or being summoned
                if showSummoning then
                    -- Keep the "Summoning..." text
                    button.levelText:SetWidth(85)
                    button.classText:SetWidth(0)
                    button.levelText:SetText("Summoning...")
                    button.classText:SetText("")
                    button.levelText:SetTextColor(1, 1, 0)
                    button.classText:SetTextColor(1, 1, 0)
                else
                    -- Show normal level/class info
                    button.levelText:SetWidth(25)
                    button.classText:SetWidth(60)
                                       -- Check if player is offline
                    if not member.isOnline then
                        button.levelText:SetText("")
                        button.classText:SetText("Offline")
                        button.levelText:SetTextColor(0.5, 0.5, 0.5)
                        button.classText:SetTextColor(0.5, 0.5, 0.5)
                    else
                        button.levelText:SetText(tostring(member.level or 0))
                        button.classText:SetText(member.class or member.classToken or "")
                                               -- Set class color using the English token
                        local r, g, b = TRS:GetClassColor(member.classToken)
                        button.levelText:SetTextColor(r, g, b)
                        button.classText:SetTextColor(r, g, b)
                    end
                end
                               -- Name always gets class color
                local r, g, b = TRS:GetClassColor(member.classToken)
                button.nameText:SetTextColor(r, g, b)

                -- Set opacity based on range (if enabled)
                if (member.inRange ~= nil and member.inRange) or (member.unitId and UnitInRange(member.unitId)) then
                    button:SetAlpha(1.0)
                else
                    local dimAlpha = db.settings.rangeOpacity or 0.8
                    if dimAlpha < 0.1 then dimAlpha = 0.1 end
                    if dimAlpha > 1.0 then dimAlpha = 1.0 end
                    button:SetAlpha(dimAlpha)
                end

                button:Show()
            else
                -- Empty slot
                button.nameText:SetText("")
                button.levelText:SetText("")
                button.classText:SetText("")
                button.leaderIcon:Hide()
                if button.addonDot then button.addonDot:Hide() end
                button.unitId = nil
                button.playerName = nil
                button:SetScript("PreClick", nil)
                button:Show()
            end
        end
    end

    -- Calculate total height needed (4 rows of groups)
    local rowHeight = headerHeight + (5 * buttonHeight) + groupSpacing
    local totalHeight = 4 * rowHeight
    content:SetHeight(math.max(484, totalHeight))
end

-- Update summon queue
function TRS:UpdateSummonQueue()
    if not TRS.summonQueueFrame then return end

    local content = TRS.summonQueueFrame.content
    local buttons = TRS.summonQueueFrame.buttons

    -- Clear existing buttons
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end

    local yOffset = 0
    local buttonHeight = 30

    local _displayQueue = (TRS.TestMode and TRS.TestMode.active and TRS.TestMode.GetDisplayQueue) and TRS.TestMode:GetDisplayQueue() or db.summonQueue
    for i, entry in ipairs(_displayQueue) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "TRSQueueButton"..i, content, "SecureUnitButtonTemplate")
            button:SetSize(200, buttonHeight)
            button:SetNormalTexture("Interface\\Buttons\\UI-Listbox-Highlight")
            button:GetNormalTexture():SetAlpha(0.3)
            button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                       -- Register for clicks
            button:RegisterForClicks("AnyUp")
            button:EnableMouse(true)

            -- Name text (left-aligned)
            local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("LEFT", button, "LEFT", 5, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetWidth(100)
            button.nameText = nameText

            -- Level text (centered)
            local levelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            levelText:SetPoint("LEFT", nameText, "RIGHT", 5, 0)
            levelText:SetJustifyH("CENTER")
            levelText:SetWidth(25)
            button.levelText = levelText

            -- Class text (right-aligned)
            local classText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            classText:SetPoint("LEFT", levelText, "RIGHT", 5, 0)
            classText:SetJustifyH("LEFT")
            classText:SetWidth(60)
            button.classText = classText

            -- Register for all mouse buttons
            button:RegisterForClicks("AnyUp")
            button:EnableMouse(true)

            -- Function to update tooltip content
            local function UpdateTooltipContent(self)
                if not self.queueEntry then return end

                GameTooltip:ClearLines()

                -- Show player name
                GameTooltip:AddLine(self.playerName, 1, 1, 1)

                -- Find the player's unit ID to get their zone
                local playerName = self.playerName
                local numMembers = GetNumGroupMembers()
                local isRaid = IsInRaid()
                local zone = "Unknown"
                               if isRaid then
                    for j = 1, numMembers do
                        if UnitName("raid"..j) == playerName then
                            local name, rank, subgroup, level, class, fileName, raidZone = GetRaidRosterInfo(j)
                            zone = raidZone or "Unknown"
                            break
                        end
                    end
                else
                    if UnitName("player") == playerName then
                        zone = GetRealZoneText() or "Unknown"
                    else
                        for j = 1, numMembers - 1 do
                            local partyUnit = "party"..j
                            if UnitName(partyUnit) == playerName then
                                zone = GetRealZoneText() or "Unknown"
                                break
                            end
                        end
                    end
                end
                               -- Show zone
                GameTooltip:AddLine(zone, 0.8, 0.8, 0.8)
                               -- Blank line
                GameTooltip:AddLine(" ", 1, 1, 1)

                -- Show timestamp
                local timestamp = self.queueEntry.timestamp or 0
                local timeAdded = date("%I:%M:%S %p", timestamp)
                GameTooltip:AddLine("Added: " .. timeAdded, 0.8, 0.8, 0.8)

                -- Show countdown
                local currentTime = time()
                local timeInQueue = currentTime - timestamp
                local timeRemaining = QUEUE_TIMEOUT - timeInQueue

                if timeRemaining > 0 then
                    local minutes = math.floor(timeRemaining / 60)
                    local seconds = timeRemaining % 60
                    GameTooltip:AddLine(string.format("Expires in: %d:%02d", minutes, seconds), 1, 1, 0)
                else
                    GameTooltip:AddLine("Expiring soon...", 1, 0, 0)
                end

                -- Show who is summoning them if applicable
                if self.summonerName then
                    GameTooltip:AddLine(" ", 1, 1, 1)
                    local summonerText = "Being summoned by " .. self.summonerName
                    GameTooltip:AddLine(summonerText, 0, 1, 0)
                end

                GameTooltip:Show()
            end

            -- Add tooltip handlers
            button:SetScript("OnEnter", function(self)
                if self.queueEntry then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    UpdateTooltipContent(self)

                    -- Set up OnUpdate to refresh tooltip every 0.1 seconds
                    self.tooltipUpdateTime = 0
                    self:SetScript("OnUpdate", function(self, elapsed)
                        self.tooltipUpdateTime = (self.tooltipUpdateTime or 0) + elapsed
                        if self.tooltipUpdateTime >= 0.1 then
                            self.tooltipUpdateTime = 0
                            UpdateTooltipContent(self)
                        end
                    end)
                end
            end)

            button:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetScript("OnUpdate", nil)
            end)

            buttons[i] = button
        end

        -- Store the queue entry for tooltip access
        button.queueEntry = entry

        -- Store player name and index for lookup
        button.playerName = entry.name
        button.queueIndex = i
               -- Find the unit for this player
        local targetUnit = nil
        local numMembers = GetNumGroupMembers()
        local isRaid = IsInRaid()
               if isRaid then
            for j = 1, numMembers do
                if UnitName("raid"..j) == entry.name then
                    targetUnit = "raid"..j
                    break
                end
            end
        else
            if UnitName("player") == entry.name then
                targetUnit = "player"
            else
                for j = 1, numMembers - 1 do
                    if UnitName("party"..j) == entry.name then
                        targetUnit = "party"..j
                        break
                    end
                end
            end
        end
               -- Set unit attribute and click behaviors
        if targetUnit and not InCombatLockdown() then
            button:SetAttribute("unit", targetUnit)
            button:SetAttribute("type1", "target")  -- Left click = target
            button:SetAttribute("type2", "macro")   -- Right click = macro (for summoning)
                       -- Get localized spell name for Ritual of Summoning
            local summonSpellName = TRS.GetSpellInfo(RITUAL_OF_SUMMONING_ID) or "Ritual of Summoning"
                       -- Build macro text - include /s message if enabled
            local macroText = TRS:BuildQueueSayMacro(entry.name)
            macroText = macroText .. "/target " .. entry.name .. "\n/cast " .. summonSpellName
                       button:SetAttribute("macrotext2", macroText)
        end

        -- Handle clicks with PostClick for UI updates
        button:SetScript("PostClick", function(self, btn)
            TRS:DebugChat("Queue click: " .. btn .. " target=" .. tostring(self.playerName))
            if btn == "MiddleButton" then
                TRS:RemoveFromSummonQueue(self.playerName)
            elseif btn == "RightButton" then
                local playerName = self.playerName
                TRS:DebugChat("Queue macro attempted: " .. (self:GetAttribute("macrotext2") or "")
                    :gsub("\n", " | ") .. "; delivery not confirmed")
                               -- Check if player can summon
                if not TRS:CanSummon() then
                    TRS:DebugChat("SKIP queue state: Ritual of Summoning not known on a warlock")
                    return
                end
                               -- Find the unit to check online status
                local numMembers = GetNumGroupMembers()
                local isRaid = IsInRaid()
                local targetUnit = nil
                               if isRaid then
                    for j = 1, numMembers do
                        if UnitName("raid"..j) == playerName then
                            targetUnit = "raid"..j
                            break
                        end
                    end
                else
                    if UnitName("player") == playerName then
                        targetUnit = "player"
                    else
                        for j = 1, numMembers - 1 do
                            if UnitName("party"..j) == playerName then
                                targetUnit = "party"..j
                                break
                            end
                        end
                    end
                end
                if not targetUnit then
                    TRS:DebugChat("SKIP queue state: target not in group")
                    print("|cFF00FF00Timber's Raid Summoner:|r |cFFFF0000[ERROR]|r " .. playerName .. " is not in your group")
                    return
                end
                if not UnitIsConnected(targetUnit) then
                    TRS:DebugChat("SKIP queue state: target offline")
                    return
                end
                               local currentMana = UnitPower("player", 0)
                if currentMana < 300 then
                    TRS:DebugChat("SKIP queue state: mana=" .. tostring(currentMana) .. " after click")
                    print("|cFF00FF00Timber's Raid Summoner:|r |cFFFF0000[ERROR]|r Not enough mana to summon (need 300 mana)")
                    return
                end

                if not UnitExists("target") then
                    TRS:DebugChat("SKIP queue state: no current target")
                    print("|cFF00FF00Timber's Raid Summoner:|r |cFFFF0000[ERROR]|r You must have a target to summon")
                    return
                end

                currentlySummoning = playerName
                summonFromQueue = true
                TRS:UpdateSummoningStateUI(playerName, true, UnitName("player"))
                TRS:BroadcastSummoningState(playerName, true)
            end
        end)

        button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)

        -- Get player info for this queue entry
        local playerName = entry.name
        local classToken = nil
        local level = nil
        local class = nil
        local isOnline = true
        local numMembers = GetNumGroupMembers()
        local isRaid = IsInRaid()

        if isRaid then
            for j = 1, numMembers do
                if UnitName("raid"..j) == playerName then
                    class, classToken = UnitClass("raid"..j)
                    level = UnitLevel("raid"..j)
                    isOnline = UnitIsConnected("raid"..j)
                    break
                end
            end
        else
            if UnitName("player") == playerName then
                class, classToken = UnitClass("player")
                level = UnitLevel("player")
                isOnline = true
            else
                for j = 1, numMembers - 1 do
                    if UnitName("party"..j) == playerName then
                        class, classToken = UnitClass("party"..j)
                        level = UnitLevel("party"..j)
                        isOnline = UnitIsConnected("party"..j)
                        break
                    end
                end
            end
        end

        -- Use data embedded in entry as fallback (supports test mode fake entries)
        classToken = classToken or entry.classToken
        level      = level      or entry.level
        class      = class      or entry.class

        -- Store the level, class, and classToken on the button for later restoration
        button.storedLevel = level
        button.storedClass = class
        button.storedClassToken = classToken

        -- Set individual column texts
        button.nameText:SetText(playerName)
               -- Check if someone is summoning this player (use shared activeSummons table)
        local isBeingSummoned = false
        local summonerName = nil

        -- First check if local player is summoning this member
        if currentlySummoning == playerName then
            isBeingSummoned = true
            summonerName = UnitName("player")
        else
            -- Check activeSummons for other summoners
            for summoner, target in pairs(activeSummons) do
                if target == playerName then
                    isBeingSummoned = true
                    summonerName = summoner
                    break
                end
            end
        end
               -- Update summoner name if detected via channeling (for tooltip)
        if isBeingSummoned and summonerName then
            button.summonerName = summonerName
        elseif not isBeingSummoned and not button.isSummoning then
            button.summonerName = nil
        end
               -- Check if this member is being summoned (either via addon tracking OR detected channeling)
        local showSummoning = button.isSummoning or isBeingSummoned

        -- Only update level/class if not currently summoning or being summoned
        if showSummoning then
            -- Keep the "Summoning..." text
            button.levelText:SetWidth(85)
            button.classText:SetWidth(0)
            button.levelText:SetText("Summoning...")
            button.classText:SetText("")
            button.levelText:SetTextColor(1, 1, 0)
            button.classText:SetTextColor(1, 1, 0)
        else
            -- Show normal level/class info
            button.levelText:SetWidth(25)
            button.classText:SetWidth(60)
                       -- Check if player is offline
            if not isOnline then
                button.levelText:SetText("")
                button.classText:SetText("Offline")
                button.levelText:SetTextColor(0.5, 0.5, 0.5)
                button.classText:SetTextColor(0.5, 0.5, 0.5)
            else
                button.levelText:SetText(tostring(level or 0))
                button.classText:SetText(class or classToken or "")

                -- Set class color
                local r, g, b = TRS:GetClassColor(classToken)
                button.levelText:SetTextColor(r, g, b)
                button.classText:SetTextColor(r, g, b)
            end
        end

        -- Name always gets class color
        local r, g, b = TRS:GetClassColor(classToken)
        button.nameText:SetTextColor(r, g, b)

        -- Dim out-of-range entries (used by test mode fake entries)
        if entry.inRange == false then
            local dimAlpha = db.settings.rangeOpacity or 0.5
            if dimAlpha < 0.1 then dimAlpha = 0.1 end
            button:SetAlpha(dimAlpha)
        else
            button:SetAlpha(1.0)
        end

        button:Show()

        yOffset = yOffset + buttonHeight
    end

    content:SetHeight(math.max(400, yOffset))
end

-- Broadcast summoning state to raid
function TRS:BroadcastSummoningState(playerName, isSummoning)
    if IsInRaid() or IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        local state = isSummoning and "1" or "0"
        local summoner = UnitName("player") or ""
        local msg = "SUMMONING:" .. playerName .. ":" .. state .. ":" .. summoner
        TRS.SendAddonMessage("TRS", msg, channel)
    end
end

-- Update summoning state in UI (both raid list and queue)
function TRS:UpdateSummoningStateUI(playerName, isSummoning, summonerName)
    -- Update summon queue buttons
    if TRS.summonQueueFrame then
        local buttons = TRS.summonQueueFrame.buttons
        for _, button in ipairs(buttons) do
            if button.playerName == playerName then
                button.isSummoning = isSummoning
                button.summonerName = summonerName

                if isSummoning then
                    -- Show "Summoning..." text
                    button.levelText:SetWidth(85)
                    button.classText:SetWidth(0)
                    button.levelText:SetText("Summoning...")
                    button.classText:SetText("")
                    button.levelText:SetTextColor(1, 1, 0)
                    button.classText:SetTextColor(1, 1, 0)
                else
                    -- Restore level and class using stored data
                    if button.storedLevel and button.storedClass and button.storedClassToken then
                        button.levelText:SetWidth(25)
                        button.classText:SetWidth(60)
                        button.levelText:SetText(tostring(button.storedLevel or 0))
                        button.classText:SetText(button.storedClass or button.storedClassToken or "")

                        -- Restore class color for both level and class text
                        local r, g, b = TRS:GetClassColor(button.storedClassToken)
                        button.levelText:SetTextColor(r, g, b)
                        button.classText:SetTextColor(r, g, b)
                    end
                end
                break
            end
        end
    end

    -- Update raid list buttons
    if TRS.raidListFrame then
        local buttons = TRS.raidListFrame.buttons
        for _, button in ipairs(buttons) do
            if button.playerName == playerName then
                button.isSummoning = isSummoning
                button.summonerName = summonerName

                if isSummoning then
                    -- Show "Summoning..." text
                    button.levelText:SetWidth(85)
                    button.classText:SetWidth(0)
                    button.levelText:SetText("Summoning...")
                    button.classText:SetText("")
                    button.levelText:SetTextColor(1, 1, 0)
                    button.classText:SetTextColor(1, 1, 0)
                else
                    -- Restore level and class using stored data
                    if button.storedLevel and button.storedClass and button.storedClassToken then
                        button.levelText:SetWidth(25)
                        button.classText:SetWidth(60)

                        button.levelText:SetText(tostring(button.storedLevel or 0))
                        button.classText:SetText(button.storedClass or button.storedClassToken or "")

                        -- Restore class color for both level and class text
                        local r, g, b = TRS:GetClassColor(button.storedClassToken)
                        button.levelText:SetTextColor(r, g, b)
                        button.classText:SetTextColor(r, g, b)
                    end
                end
                break
            end
        end
    end
end

-- Broadcast queue removal to raid
function TRS:BroadcastQueueRemoval(removedPlayer, removerName, reason)
    if IsInRaid() or IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        local msg = "REMOVED:" .. removedPlayer .. ":" .. removerName .. ":" .. reason
        TRS.SendAddonMessage("TRS", msg, channel)
    end
end

-- Clear summoning state for a player
function TRS:ClearSummoningState(playerName)
    local wasCleared = false
       -- Clear in summon queue
    if TRS.summonQueueFrame then
        local buttons = TRS.summonQueueFrame.buttons
        for _, button in ipairs(buttons) do
            if button.playerName == playerName and button.isSummoning then
                button.isSummoning = false
                wasCleared = true
                -- Restore using stored data
                if button.storedLevel and button.storedClass and button.storedClassToken then
                    button.levelText:SetWidth(25)
                    button.classText:SetWidth(60)

                    button.levelText:SetText(tostring(button.storedLevel or 0))
                    button.classText:SetText(button.storedClass or button.storedClassToken or "")

                    -- Restore class color
                    local r, g, b = TRS:GetClassColor(button.storedClassToken)
                    button.levelText:SetTextColor(r, g, b)
                    button.classText:SetTextColor(r, g, b)
                end
                break
            end
        end
    end
       -- Clear in raid list
    if TRS.raidListFrame then
        local buttons = TRS.raidListFrame.buttons
        for _, button in ipairs(buttons) do
            if button.playerName == playerName and button.isSummoning then
                button.isSummoning = false
                wasCleared = true
                -- Restore using stored data
                if button.storedLevel and button.storedClass and button.storedClassToken then
                    button.levelText:SetWidth(25)
                    button.classText:SetWidth(60)

                    button.levelText:SetText(tostring(button.storedLevel or 0))
                    button.classText:SetText(button.storedClass or button.storedClassToken or "")

                    -- Restore class color
                    local r, g, b = TRS:GetClassColor(button.storedClassToken)
                    button.levelText:SetTextColor(r, g, b)
                    button.classText:SetTextColor(r, g, b)
                end
                break
            end
        end
    end
       -- Broadcast the state change if we cleared anything
    if wasCleared then
        TRS:BroadcastSummoningState(playerName, false)
    end
end

-- Update keywords list
-- Update keywords in settings panel
function TRS:UpdateSettingsKeywords()
    if not TRS.settingsFrame then return end

    local content = TRS.settingsFrame.kwListFrame
    local buttons = TRS.settingsFrame.kwButtons

    -- Clear existing buttons
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end

    local yOffset = 0
    local buttonHeight = 25

    for i, keyword in ipairs(db.keywords) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", nil, content)
            button:SetSize(286, buttonHeight)
            button:SetNormalTexture("Interface\\Buttons\\UI-Listbox-Highlight")
            button:GetNormalTexture():SetAlpha(0.3)
            button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")

            local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", button, "LEFT", 5, 0)
            button.text = text

            -- Delete button
            local deleteBtn = CreateFrame("Button", nil, button, "UIPanelCloseButton")
            deleteBtn:SetSize(20, 20)
            deleteBtn:SetPoint("RIGHT", button, "RIGHT", 0, 0)
            deleteBtn:SetScript("OnClick", function()
                table.remove(db.keywords, i)
                TRS:UpdateSettingsKeywords()
            end)
            button.deleteBtn = deleteBtn

            buttons[i] = button
        end

        button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
        button.text:SetText(keyword)
        button:Show()

        yOffset = yOffset + buttonHeight
    end

    -- Update scroll height to fit all keywords
    content:SetHeight(math.max(150, yOffset))
end

-- Toggle settings panel
function TRS:ToggleSettings()
    TRS.settingsVisible = not TRS.settingsVisible

    if TRS.settingsVisible then
        -- Show settings, expand frame
        TRS.settingsFrame.frame:Show()
    else
        -- Hide settings, shrink frame
        TRS.settingsFrame.frame:Hide()
    end

    TRS:UpdateMainFrameLayout()
end

-- Summon a player
function TRS:SummonPlayer(playerName, unitId, silentMode)
    -- Send messages first
    if not silentMode then
        TRS.SendChatMessage(string.format(db.settings.raidMessage, playerName), "RAID")
        if db.settings.autoWhisper then
            TRS.SendChatMessage(db.settings.whisperMessage, "WHISPER", nil, playerName)
        end
    end

    -- Use secure button to target and cast
    if TRS.secureButton and unitId and not InCombatLockdown() then
        TRS.secureButton:SetAttribute("type", "macro")
        TRS.secureButton:SetAttribute("macrotext", "/target " .. playerName .. "\n/cast Ritual of Summoning")
        TRS.secureButton:Click()
    end

    if not silentMode then
        print("Summoning " .. playerName)
    else
        print("Summoning " .. playerName .. " (silent mode)")
    end
end

-- Slash command handler
SLASH_TIMBERSRAIDSUMMONER1 = "/TRS"
SLASH_TIMBERSRAIDSUMMONER2 = "/trs"
SLASH_TIMBERSRAIDSUMMONER3 = "/raidsummoner"
SLASH_TIMBERSRAIDSUMMONER4 = "/timbersraidsummoner"
SlashCmdList["TIMBERSRAIDSUMMONER"] = function(msg)
    local input = (strtrim and strtrim(msg or "")) or (msg or "")
       -- Check for minimap commands
    if TRS.HandleMinimapSlash and TRS:HandleMinimapSlash(input) then
        return
    end
       -- Check for test mode commands
    if TRS.TestMode and TRS.TestMode.HandleSlash and TRS.TestMode:HandleSlash(input) then
        return
    end
    if TRS.ChatDebug and TRS.ChatDebug:HandleSlash(input) then
        return
    end
    -- Default behavior: toggle frame
    TRS:ToggleFrame()
end

-- Keybind function
function TimbersRaidSummoner_ToggleFrame()
    TRS:ToggleFrame()
end

-- Get class color based on settings
function TRS:GetClassColor(class)
    if not class then return 1, 1, 1 end

    local colors = {
        WARRIOR = {0.78, 0.61, 0.43},
        PALADIN = {0.96, 0.55, 0.73},
        HUNTER = {0.67, 0.83, 0.45},
        ROGUE = {1.00, 0.96, 0.41},
        PRIEST = {1.00, 1.00, 1.00},
        SHAMAN = (function()
            local setting = db.settings.shamanColor or "default"
            if setting == "pink" then
                return {0.96, 0.55, 0.73}
            elseif setting == "blue" then
                return {0.00, 0.44, 0.87}
            else -- "default" - based on expansion
                if TRS.Client.shamanDefaultColor == "pink" then
                    return {0.96, 0.55, 0.73} -- pink (vanilla)
                else
                    return {0.00, 0.44, 0.87} -- blue (TBC+)
                end
            end
        end)(),
        MAGE = {0.41, 0.80, 0.94},
        WARLOCK = {0.58, 0.51, 0.79},
        DRUID = {1.00, 0.49, 0.04}
    }

    local color = colors[class] or {1, 1, 1}
    return color[1], color[2], color[3]
end

-- Toggle frame function
function TRS:ToggleFrame()
    if TRS.mainFrame then
        if TRS.mainFrame:IsShown() then
            TRS.mainFrame:Hide()
        else
            TRS.mainFrame:Show()
            TRS:UpdateRaidList()
            TRS:UpdateSummonQueue()
            TRS:UpdateShardCount()
            if TRS.settingsVisible then
                TRS:UpdateSettingsKeywords()
            end
        end
    end
end

-- Add player to summon queue
function TRS:AddToSummonQueue(playerName)
    -- Check if player is already in queue
    for _, entry in ipairs(db.summonQueue) do
        if entry.name == playerName then
            return -- Already in queue
        end
    end

    -- Add to queue
    table.insert(db.summonQueue, {
        name = playerName,
        timestamp = time()
    })

    -- Play sound if enabled
    if db.settings.playSoundOnAdd then
        PlaySound(8959) -- SOUNDKIT.RAID_WARNING
    end

    -- Update UI if visible, otherwise show toast notification
    if TRS.mainFrame and TRS.mainFrame:IsShown() then
        TRS:UpdateSummonQueue()
    else
        -- Show toast notification when addon is not open (if enabled)
        if db.settings.showToastNotification then
            local _, class = UnitClass("player")
            if class == "WARLOCK" then
                TRS:ShowToast(playerName)
            end
        end
    end

    -- Broadcast the updated queue to raid
    TRS:SendQueueData()

    -- Only show message for warlocks
    local _, class = UnitClass("player")
    if class == "WARLOCK" then
        print("|cFF00FF00Timber's Raid Summoner:|r Added " .. playerName .. " to summon queue")
    end
end

-- Remove player from summon queue
function TRS:RemoveFromSummonQueue(playerName, reason)
    for i, entry in ipairs(db.summonQueue) do
        if entry.name == playerName then
            table.remove(db.summonQueue, i)

            -- Clear summoning state if they were being summoned
            TRS:ClearSummoningState(playerName)

            -- Broadcast removal with reason
            local removerName = UnitName("player")
            TRS:BroadcastQueueRemoval(playerName, removerName, reason or "manual")

            -- Update UI if visible
            if TRS.mainFrame and TRS.mainFrame:IsShown() then
                TRS:UpdateSummonQueue()
            end

            -- Broadcast the updated queue to raid
            TRS:SendQueueData()

            print("|cFF00FF00Timber's Raid Summoner:|r Removed " .. playerName .. " from summon queue")
            return
        end
    end
end

-- Parse chat message for keywords
function TRS:ParseChatMessage(message, sender)
    -- Normalize sender name (remove realm)
    local playerName = strsplit("-", sender)

    -- Check if message matches any keywords
    local lowerMessage = string.lower(message)
    for _, keyword in ipairs(db.keywords) do
        local lowerKeyword = string.lower(keyword)
        local matched = false

        -- Check for special prefixes and patterns
        if string.sub(lowerKeyword, 1, 1) == "*" then
            -- Asterisk prefix: match if keyword appears anywhere in message
            local searchTerm = string.sub(lowerKeyword, 2) -- Remove the *
            local escapedTerm = searchTerm:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            local success, result = pcall(string.find, lowerMessage, escapedTerm)
            if success and result then
                matched = true
            end
        elseif string.match(lowerKeyword, "^%^") or string.match(lowerKeyword, "%$$") then
            -- User specified regex anchors (^ or $), use as pattern
            local success, result = pcall(string.match, lowerMessage, lowerKeyword)
            if success and result then
                matched = true
            end
        else
            -- Plain text keyword - must match entire message exactly
            local exactPattern = "^" .. lowerKeyword:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "$"
            local success, result = pcall(string.match, lowerMessage, exactPattern)
            if success and result then
                matched = true
            end
        end

        if matched then
            TRS:DebugChat("REQUEST " .. playerName .. " matched keyword " .. keyword)
            TRS:AddToSummonQueue(playerName)
            return
        end
    end
end

-- Count soul shards in bags
function TRS:CountSoulShards()
    -- Item counts go through the compat wrapper (global vs C_Item)
    -- Soul Shard item ID: 6265
    local count = TRS.GetItemCount(6265, false) -- false = don't include bank
    return count or 0
end

-- Update soul shard count display
function TRS:UpdateShardCount()
    if TRS.shardCountText then
        local count = TRS:CountSoulShards()
        TRS.shardCountText:SetText("Soul Shards: " .. count)
    end
end

-- Request queue sync from raid members
function TRS:RequestQueueSync()
    if IsInRaid() or IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        TRS.SendAddonMessage("TRS", "SYNC_REQUEST", channel)
    end
end

-- Broadcast addon presence so others can detect us
function TRS:BroadcastHello()
    if IsInRaid() then
        TRS.SendAddonMessage("TRS", "HELLO", "RAID")
    elseif IsInGroup() then
        TRS.SendAddonMessage("TRS", "HELLO", "PARTY")
    end
end

-- Send queue data to raid
function TRS:SendQueueData(target)
    local db = TimbersRaidSummonerDB
    if not db or not db.summonQueue then return end

    local channel = IsInRaid() and "RAID" or "PARTY"

    -- Check if anyone is currently being summoned by us
    local summoningTarget = currentlySummoning or ""
    local summonerName = currentlySummoning and UnitName("player") or ""

    -- Send queue count first (includes our summoning state)
    local countMsg = "SYNC_COUNT:" .. #db.summonQueue .. ":" .. summoningTarget .. ":" .. summonerName
    TRS.SendAddonMessage("TRS", countMsg, channel)

    -- Send each queue entry
    for i, entry in ipairs(db.summonQueue) do
        local msg = "SYNC_ENTRY:" .. i .. ":" .. entry.name .. ":" .. (entry.timestamp or 0)
        TRS.SendAddonMessage("TRS", msg, channel)
    end
end

-- Handle incoming addon messages
function TRS:HandleAddonMessage(message, sender)
    local db = TimbersRaidSummonerDB
    if not db then return end

    -- Don't process our own messages (strip realm suffix from sender)
    local senderName = strsplit("-", sender)
    if senderName == UnitName("player") then
        return
    end

    if message == "HELLO" then
        -- Sender has the addon; record them and reply so they know we have it too
        TRS.hasAddon[senderName] = true
        local channel = IsInRaid() and "RAID" or "PARTY"
        TRS.SendAddonMessage("TRS", "HELLO_ACK", channel)
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
        end
    elseif message == "HELLO_ACK" then
        -- Sender confirmed they have the addon
        TRS.hasAddon[senderName] = true
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
        end
    elseif message == "SYNC_REQUEST" then
        -- Someone requested queue sync, send our data
        TRS:SendQueueData()
    elseif string.match(message, "^SYNC_COUNT:") then
        -- Receiving queue sync (format: SYNC_COUNT:count:summoningTarget:summonerName)
        local count, summoningTarget, summonerName = string.match(message, "^SYNC_COUNT:(%d+):([^:]*):?(.*)$")
        count = tonumber(count) or 0

        -- Store the summoning info
        TRS.receivedSummoningTarget = (summoningTarget and summoningTarget ~= "") and summoningTarget or nil
        TRS.receivedSummonerName = (summonerName and summonerName ~= "") and summonerName or nil
        TRS.receivedQueue = {}
        TRS.expectedQueueSize = count

        -- If queue is empty but someone is summoning, still apply the summoning state
        if count == 0 and TRS.receivedSummoningTarget then
            TRS:UpdateSummoningStateUI(TRS.receivedSummoningTarget, true, TRS.receivedSummonerName)
        end
    elseif string.match(message, "^SYNC_ENTRY:") then
        -- Receiving a queue entry
        local index, name, timestamp = string.match(message, "^SYNC_ENTRY:(%d+):([^:]+):(%d+)$")
        index = tonumber(index)
        timestamp = tonumber(timestamp)

        if TRS.receivedQueue and index then
            TRS.receivedQueue[index] = {
                name = name,
                timestamp = timestamp
            }

            -- Check if we've received all entries
            if #TRS.receivedQueue == TRS.expectedQueueSize then
                TRS:MergeReceivedQueue()
            end
        end
    elseif string.match(message, "^SUMMONING:") then
        -- Receiving summoning state update
        local playerName, stateStr, summonerName = string.match(message, "^SUMMONING:([^:]+):(%d+):(.*)$")
        local isSummoning = stateStr == "1"

        if playerName then
            -- Update UI for both panes
            TRS:UpdateSummoningStateUI(playerName, isSummoning, summonerName)
        end
    elseif string.match(message, "^REMOVED:") then
        -- Receiving queue removal notification
        local removedPlayer, removerName, reason = string.match(message, "^REMOVED:([^:]+):([^:]+):([^:]+)$")

        if removedPlayer and removerName and reason then
            -- Remove from local queue
            for i, entry in ipairs(db.summonQueue) do
                if entry.name == removedPlayer then
                    table.remove(db.summonQueue, i)

                    -- Clear summoning state if they were being summoned
                    TRS:ClearSummoningState(removedPlayer)

                    -- Update UI if visible
                    if TRS.mainFrame and TRS.mainFrame:IsShown() then
                        TRS:UpdateSummonQueue()
                    end
                    break
                end
            end

            -- Check if current player is a warlock for chat message
            local _, class = UnitClass("player")

            if class == "WARLOCK" then
                local msg
                if reason == "timeout" then
                    msg = "|cFF00FF00Timber's Raid Summoner:|r |cFFFF0000[WARNING]|r " .. removedPlayer .. " timed out of the summon queue"
                elseif reason ~= "summoned" then
                    msg = "|cFF00FF00Timber's Raid Summoner:|r " .. removedPlayer .. " was removed from the summoning queue by " .. removerName
                end
                if msg then
                    print(msg)
                end
            end
        end
    end
end

-- Merge received queue with local queue
function TRS:MergeReceivedQueue()
    local db = TimbersRaidSummonerDB
    if not db or not TRS.receivedQueue then return end

    -- Merge entries from received queue
    for _, receivedEntry in ipairs(TRS.receivedQueue) do
        local exists = false
        -- Check if this player is already in our queue
        for _, localEntry in ipairs(db.summonQueue) do
            if localEntry.name == receivedEntry.name then
                exists = true
                -- Update timestamp if received one is older (was added first)
                if receivedEntry.timestamp < localEntry.timestamp then
                    localEntry.timestamp = receivedEntry.timestamp
                end
                break
            end
        end

        -- Add if not already in queue
        if not exists then
            table.insert(db.summonQueue, receivedEntry)
        end
    end

    -- Sort queue by timestamp (oldest first)
    table.sort(db.summonQueue, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)

    -- Update UI if visible
    if TRS.mainFrame and TRS.mainFrame:IsShown() then
        TRS:UpdateSummonQueue()
    end

    -- If someone is being summoned, mark it in the UI (both queue and raid list)
    if TRS.receivedSummoningTarget then
        TRS:UpdateSummoningStateUI(TRS.receivedSummoningTarget, true, TRS.receivedSummonerName)
    end

    -- Clear received data
    TRS.receivedQueue = nil
    TRS.expectedQueueSize = nil
    TRS.receivedSummoningTarget = nil
    TRS.receivedSummonerName = nil
end

-- Clean up expired summon queue entries
function TRS:CleanupExpiredQueue()
    local db = TimbersRaidSummonerDB
    if not db or not db.summonQueue then return end

    local currentTime = time()
    local removedAny = false

    -- Check queue in reverse order so we can remove safely
    for i = #db.summonQueue, 1, -1 do
        local entry = db.summonQueue[i]
        local timeInQueue = currentTime - (entry.timestamp or 0)

        -- Check if this entry is currently being summoned
        local isSummoning = false
        if TRS.summonQueueFrame and TRS.summonQueueFrame.buttons then
            for _, button in ipairs(TRS.summonQueueFrame.buttons) do
                if button.playerName == entry.name and button.isSummoning then
                    isSummoning = true
                    break
                end
            end
        end

        -- Remove if expired and not currently being summoned
        if timeInQueue >= QUEUE_TIMEOUT and not isSummoning then
            -- Check if current player is a warlock for chat message
            local _, class = UnitClass("player")
            if class == "WARLOCK" then
                print("|cFF00FF00Timber's Raid Summoner:|r |cFFFF0000[WARNING]|r " .. entry.name .. " timed out of the summon queue")
            end

            -- Broadcast that this player was removed due to timeout so other clients update
            local removerName = UnitName("player") or ""
            TRS:BroadcastQueueRemoval(entry.name, removerName, "timeout")

            table.remove(db.summonQueue, i)
            removedAny = true
        end
    end

    -- Update UI if anything was removed
    if removedAny then
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateSummonQueue()
        end

        -- Broadcast the updated queue after removals so all clients can resync
        TRS:SendQueueData()
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_CONNECTION")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            Initialize()
            -- Mark the local player as having the addon
            TRS.hasAddon[UnitName("player")] = true
            -- In Classic Era, addon message prefixes don't need to be registered
            -- Request queue sync and announce addon presence after a short delay
            C_Timer.After(2, function()
                TRS:RequestQueueSync()
                TRS:BroadcastHello()
            end)
        end
    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        -- Check if player left the group
        if not IsInRaid() and not IsInGroup() then
            -- Clear the summon queue when leaving group
            if db and db.summonQueue and #db.summonQueue > 0 then
                db.summonQueue = {}
                if TRS.mainFrame and TRS.mainFrame:IsShown() then
                    TRS:UpdateSummonQueue()
                end
            end
            -- Clear addon detection table (keep only self)
            TRS.hasAddon = {}
            TRS.hasAddon[UnitName("player")] = true
        else
            -- Announce our presence to any new members
            TRS:BroadcastHello()
        end

        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
            TRS:UpdateSummonQueue()
        end
    elseif event == "UNIT_CONNECTION" then
        -- Update UI when a unit connects or disconnects
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
            TRS:UpdateSummonQueue()
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == "TRS" then
            TRS:HandleAddonMessage(message, sender)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local systemMessage = ...
        -- Check if this is a summon acceptance message
        -- Common patterns: "PlayerName has accepted your summon."
        -- Or in some locales it might be different
        if currentlySummoning and summonFromQueue then
            -- Try to match summon acceptance pattern
            local playerName = string.match(systemMessage, "(.+) has accepted your summon")
            if not playerName then
                -- Try alternate pattern
                playerName = string.match(systemMessage, "(.+) accepts your summon")
            end
                       if playerName and playerName == currentlySummoning then
                -- Successfully summoned via Meeting Stone!
                TRS:RemoveFromSummonQueue(currentlySummoning, "summoned")
            end
        end
    elseif event == "UNIT_SPELLCAST_START" then
        local unitTarget, castGUID, spellID = ...
        if unitTarget == "player" then
            local spellName = TRS.GetSpellInfo(spellID)
            TRS:DebugChat("ACTUAL CAST_START id=" .. tostring(spellID) .. " name=" .. tostring(spellName)
                .. " target=" .. tostring(currentlySummoning) .. " fromQueue=" .. tostring(summonFromQueue))
            if spellID == RITUAL_OF_SUMMONING_ID then
                -- If currentlySummoning not set (manual cast), detect target
                if not currentlySummoning then
                    local targetName = UnitName("target")
                    if targetName and (UnitInRaid(targetName) or UnitInParty(targetName)) then
                        currentlySummoning = targetName
                        summonFromQueue = false  -- Manual cast, not from queue
                    end
                end

                -- Cast actually started! Set the UI state and broadcast immediately
                if currentlySummoning then
                    TRS:UpdateSummoningStateUI(currentlySummoning, true, UnitName("player"))
                    TRS:BroadcastSummoningState(currentlySummoning, true)

                    -- Use C_Timer with delay to avoid "Interface action failed" error when sending chat
                    -- This breaks out of the protected call chain from secure button clicks
                    -- Note: Say message is handled via macro text, not here
                    C_Timer.After(0.1, function()
                        TRS:DebugChat("Queue chat timer: target=" .. tostring(currentlySummoning)
                            .. " fromQueue=" .. tostring(summonFromQueue))
                        if summonFromQueue then
                            TRS:SendSummonMessages(currentlySummoning, "queue")
                        else
                            TRS:DebugChat("SKIP group/whisper: summon not from queue")
                        end
                    end)
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Note: UNIT_SPELLCAST_STOP is NOT included here because it fires when cast
        -- successfully transitions to channel (e.g., Ritual of Summoning cast -> channel)
        local unitTarget, castGUID, spellID = ...
        if unitTarget == "player" then
            -- Clear summoning state for failed/interrupted cast
            if currentlySummoning then
                if spellID == RITUAL_OF_SUMMONING_ID then
                    TRS:ClearSummoningState(currentlySummoning)
                    currentlySummoning = nil
                    summonFromQueue = false
                else
                    -- For any other spell failure while summoning (like Meeting Stone)
                    -- Clear the summoning state
                    TRS:ClearSummoningState(currentlySummoning)
                    currentlySummoning = nil
                    summonFromQueue = false
                    meetingStoneStartTime = nil
                    meetingStoneTarget = nil
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- Note: We intentionally do NOT clear state here because STOP fires when cast
        -- successfully transitions to channel (e.g., Ritual of Summoning cast -> channel)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget, castGUID, spellID = ...
        if unitTarget == "player" then
            if spellID == RITUAL_OF_SUMMONING_ID then
                -- Cast succeeded, about to transition to channel
                -- Store current shard count to compare later
                summonStartShardCount = TRS:CountSoulShards()
            end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unitTarget, castGUID, spellID = ...
        if unitTarget == "player" then
            if spellID == RITUAL_OF_SUMMONING_ID then
                -- Channel started - keep player in queue showing "Summoning..."
                -- They'll be removed if shards decrease or timeout expires
                summonChannelActive = true
            else
                -- Check if it's Meeting Stone Summon
                local channelName = UnitChannelInfo("player")
                if channelName then
                    local lowerName = string.lower(channelName)
                    if string.find(lowerName, "meeting") or string.find(lowerName, "summon") then
                        -- Meeting Stone channel started
                        -- Check if target is in the queue
                        local targetName = UnitName("playertarget")
                        if targetName then
                            -- Check if this person is in the summon queue
                            local db = TimbersRaidSummonerDB
                            for i, entry in ipairs(db.summonQueue) do
                                if entry.name == targetName then
                                    -- Target is in queue! Set up summoning state immediately
                                    currentlySummoning = targetName
                                    summonFromQueue = true
                                    meetingStoneStartTime = GetTime()  -- Track when channel started
                                    meetingStoneTarget = targetName
                                    TRS:UpdateSummoningStateUI(targetName, true, UnitName("player"))
                                                                       -- Use C_Timer with delay to avoid "Interface action failed" error when sending chat
                                    -- Note: Meeting Stone doesn't use macro, so we send say message here
                                    C_Timer.After(0.1, function()
                                        TRS:SendSummonMessages(targetName, "stone")
                                    end)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unitTarget, castGUID, spellID = ...
        if unitTarget == "player" then
            if spellID == RITUAL_OF_SUMMONING_ID and summonChannelActive then
                summonChannelActive = false

                -- Check if shard count decreased (summon successful)
                local currentShardCount = TRS:CountSoulShards()
                local shardsUsed = summonStartShardCount - currentShardCount

                if currentlySummoning then
                    if shardsUsed >= 1 then
                        -- Shard was consumed - summon was successful
                        TRS:ClearSummoningState(currentlySummoning)
                        TRS:RemoveFromSummonQueue(currentlySummoning, "summoned")
                    else
                        -- No shard consumed - summon was interrupted/failed
                        TRS:ClearSummoningState(currentlySummoning)
                    end
                    currentlySummoning = nil
                end
                summonStartShardCount = 0
            else
                -- Check if it's Meeting Stone Summon stopping
                -- Meeting Stone doesn't give us a spellID, so we need to check the channel name
                -- Since channel has stopped, we can't call UnitChannelInfo, but we can check if we were summoning
                if currentlySummoning and summonFromQueue and meetingStoneStartTime then
                    local channelDuration = GetTime() - meetingStoneStartTime
                                       -- If channel lasted more than 5 seconds, assume they accepted and remove from queue
                    if channelDuration > 5 then
                        TRS:RemoveFromSummonQueue(currentlySummoning, "summoned")
                    end
                                       -- Clear the summoning state
                    TRS:ClearSummoningState(currentlySummoning)
                    currentlySummoning = nil
                    summonFromQueue = false
                    meetingStoneStartTime = nil
                    meetingStoneTarget = nil
                end
            end
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local messageType, message = ...
        -- Error messages are already shown by the game, no need to print them
    elseif event == "BAG_UPDATE" then
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateShardCount()
        end
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or
           event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        local message, sender = ...
        if sender and sender ~= UnitName("player") then
            TRS:ParseChatMessage(message, sender)
        end
    end
end)

-- Set up timer to check for expired queue entries and update range
local timeSinceLastCheck = 0
local timeSinceRangeUpdate = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastCheck = timeSinceLastCheck + elapsed
    timeSinceRangeUpdate = timeSinceRangeUpdate + elapsed

    -- Check every 5 seconds
    if timeSinceLastCheck >= 5 then
        timeSinceLastCheck = 0
        TRS:CleanupExpiredQueue()
    end
       -- Update range opacity every 1 second
    if timeSinceRangeUpdate >= 1 then
        timeSinceRangeUpdate = 0
        if TRS.mainFrame and TRS.mainFrame:IsShown() then
            TRS:UpdateRaidList()
        end
    end
end)
