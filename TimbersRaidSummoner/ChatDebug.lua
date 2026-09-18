local TRS = _G["TimbersRaidSummoner"]
local Debug = { enabled = false, live = false, lines = {}, buttons = {} }
TRS.ChatDebug = Debug

function Debug:Log(message)
    if not self.enabled then return end
    table.insert(self.lines, string.format("%.3f %s", GetTime(), tostring(message)))
    if #self.lines > 200 then table.remove(self.lines, 1) end
    if self.logBox then
        self.logBox:SetText(table.concat(self.lines, "\n"))
        self.logBox:SetCursorPosition(#self.logBox:GetText())
    end
end

function Debug:LogEnvironment()
    local version, build, _, interface = GetBuildInfo()
    local _, class = UnitClass("player")
    self:Log("TRS " .. tostring(TRS.VERSION) .. " WoW=" .. tostring(version)
        .. " build=" .. tostring(build) .. " interface=" .. tostring(interface)
        .. " locale=" .. GetLocale() .. " class=" .. tostring(class))
    self:Log("Group=" .. (IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "solo")
        .. " zone=" .. tostring(GetRealZoneText()))
    local settings = TimbersRaidSummonerDB.settings
    self:Log("Saved settings: group=" .. tostring(settings.sendRaidMessage)
        .. " say=" .. tostring(settings.sendSayMessage) .. " whisper=" .. tostring(settings.autoWhisper))
end

function Debug:GetSettings(channel)
    local saved = TimbersRaidSummonerDB.settings
    local settings = {
        sendRaidMessage = saved.sendRaidMessage,
        sendSayMessage = saved.sendSayMessage,
        autoWhisper = saved.autoWhisper,
        raidMessage = saved.raidMessage or "Summoning %s",
        sayMessage = saved.sayMessage or "Summoning %s",
        whisperMessage = saved.whisperMessage or "Summoning you now",
    }
    if channel ~= "all" then
        settings.sendRaidMessage = channel == "group"
        settings.sendSayMessage = channel == "say"
        settings.autoWhisper = channel == "whisper"
    end
    for _, key in ipairs({ "raidMessage", "sayMessage", "whisperMessage" }) do
        -- A test macro must contain only chat, even if saved text has line breaks.
        settings[key] = "[TRS TEST] " .. settings[key]:gsub("[\r\n]", " ")
    end
    return settings
end

function Debug:RefreshButtons()
    if InCombatLockdown() then
        self:Log("Refresh deferred until combat ends; tests unavailable in combat")
        return
    end
    local target = self.targetBox:GetText():match("^%s*(.-)%s*$")
    local valid = target ~= "" and not target:find("[%s%c|/\\:;%%]")
    for _, button in ipairs(self.buttons) do
        button.testTarget = valid and target or nil
        button.testLive = self.live
        button.testSettings = self:GetSettings(button.channel)
        button.sayMacro = ""
        if valid and button.source == "queue" then
            button.sayMacro = TRS:BuildQueueSayMacro(target, button.testSettings)
        end
        local macroText = self.live and valid and button.sayMacro ~= ""
            and "/stopmacro [combat]\n" .. button.sayMacro or ""
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", macroText)
        button:SetAttribute("type2", "macro")
        button:SetAttribute("macrotext2", macroText)
    end
    self.modeButton:SetText(self.live and "Mode: LIVE CHAT" or "Mode: DRY RUN")
    local s = TimbersRaidSummonerDB.settings
    self.status:SetText("Saved settings: group " .. (s.sendRaidMessage and "on" or "off")
        .. ", say " .. (s.sendSayMessage and "on" or "off")
        .. ", whisper " .. (s.autoWhisper and "on" or "off"))
end

function Debug:Run(button)
    if not self.enabled then return end
    if InCombatLockdown() then
        self:Log("SKIP test: leave combat before running chat diagnostics")
        return
    end
    if not button.testTarget then
        self:Log("Enter a character name first (Name-Realm is accepted)")
        return
    end

    local target, live, settings = button.testTarget, button.testLive, button.testSettings
    local source, channel = button.source, button.channel
    local session = self.session
    self:LogEnvironment()
    self:Log((live and "LIVE" or "DRY RUN") .. " simulated " .. source .. " summon -> " .. target
        .. "; channels=" .. channel .. "; no spell cast or queue change")
    self:Log("Test settings: group=" .. tostring(settings.sendRaidMessage)
        .. " say=" .. tostring(settings.sendSayMessage) .. " whisper=" .. tostring(settings.autoWhisper))

    if source == "queue" then
        if button.sayMacro ~= "" then
            self:Log((live and "MACRO attempted (check nearby receiver): " or "WOULD RUN MACRO: ")
                .. button.sayMacro:gsub("\n", ""))
        else
            self:Log("SKIP queue SAY macro: disabled for this test")
        end
    end

    self:Log("Simulated " .. (source == "queue" and "cast start" or "meeting-stone channel start")
        .. ": dispatch in 0.1 seconds; real event timing not tested")
    C_Timer.After(0.1, function()
        if not self.enabled or self.session ~= session then return end
        local ok, err = pcall(function()
            TRS:SendSummonMessages(target, source, settings, function(message, destination, recipient)
                if not live then
                    self:Log("WOULD SEND " .. destination .. (recipient and " -> " .. recipient or "")
                        .. ": " .. message)
                elseif (destination == "PARTY" or destination == "RAID") and not IsInGroup() then
                    self:Log("SKIP " .. destination .. ": join a real party/raid for live delivery")
                else
                    TRS:SendSummonChat(message, destination, recipient)
                end
            end)
        end)
        if not ok then self:Log("Test stopped on error: " .. tostring(err)) end
    end)
end

function Debug:CreateFrame()
    local frame = CreateFrame("Frame", "TRSChatDebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(650, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("TRS Chat Diagnostics")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() self:Disable() end)

    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", 20, -50)
    instructions:SetWidth(610)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Any class/level. Dry run previews only. LIVE CHAT sends real [TRS TEST] messages.\n"
        .. "Use a second account to confirm delivery. No summon is cast. Test out of combat.\n"
        .. "Click a test (left or right). All uses saved settings; individual tests enable only that channel.")

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 20, -108)
    label:SetText("Recipient:")
    local target = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    target:SetSize(200, 25)
    target:SetPoint("TOPLEFT", 100, -100)
    target:SetAutoFocus(false)
    target:SetMaxLetters(100)
    target:SetText(UnitName("target") or "TestPlayer")
    target:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    target:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.targetBox = target

    local mode = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    mode:SetSize(150, 25)
    mode:SetPoint("TOPLEFT", 315, -100)
    mode:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        self.live = not self.live
        self.session = (self.session or 0) + 1
        self:RefreshButtons()
        self:Log(self.live and "LIVE CHAT enabled: test buttons send real messages" or "Dry run enabled")
    end)
    self.modeButton = mode

    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(150, 25)
    refresh:SetPoint("TOPLEFT", 475, -100)
    refresh:SetText("Refresh settings")
    refresh:SetScript("OnClick", function() self:RefreshButtons() end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", 20, -138)
    self.status = status

    for row, source in ipairs({ "queue", "stone" }) do
        local rowLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rowLabel:SetPoint("TOPLEFT", 20, -172 - (row - 1) * 35)
        rowLabel:SetText(source == "queue" and "Queue" or "Meeting stone")
        for col, channel in ipairs({ "all", "group", "say", "whisper" }) do
            local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate,SecureUnitButtonTemplate")
            button:SetSize(112, 25)
            button:SetPoint("TOPLEFT", 145 + (col - 1) * 120, -165 - (row - 1) * 35)
            button:SetText(channel == "all" and "All (settings)" or channel)
            button:RegisterForClicks("AnyUp")
            button.source = source
            button.channel = channel
            button:SetScript("PostClick", function(b, mouseButton)
                if mouseButton == "LeftButton" or mouseButton == "RightButton" then self:Run(b) end
            end)
            table.insert(self.buttons, button)
        end
    end
    target:SetScript("OnTextChanged", function() self:RefreshButtons() end)

    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", 20, -245)
    logLabel:SetText("Log (last 200 lines): click inside, Ctrl+A then Ctrl+C to copy.")
    local scroll = CreateFrame("ScrollFrame", "TRSChatDebugScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -265)
    scroll:SetSize(580, 280)
    local logBox = CreateFrame("EditBox", nil, scroll)
    logBox:SetMultiLine(true)
    logBox:SetAutoFocus(false)
    logBox:SetFontObject(ChatFontNormal)
    logBox:SetWidth(580)
    logBox:SetHeight(280)
    logBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    scroll:SetScrollChild(logBox)
    self.logBox = logBox

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(100, 25)
    clear:SetPoint("BOTTOMLEFT", 20, 15)
    clear:SetText("Clear log")
    clear:SetScript("OnClick", function()
        self.lines = {}
        self:LogEnvironment()
    end)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    note:SetText("Refresh settings after edits. Close or /trs debug off stops logging.")
    self.frame = frame
end

function Debug:Disable()
    if InCombatLockdown() then
        print("TRS: Close chat diagnostics after combat ends.")
        return
    end
    self.enabled = false
    self.live = false
    self.session = (self.session or 0) + 1
    if self.frame then
        self:RefreshButtons()
        self.frame:Hide()
    end
end

function Debug:HandleSlash(input)
    local command, rest = input:match("^(%S+)%s*(.-)%s*$")
    if not command or command:lower() ~= "debug" then return false end
    if rest:lower() == "off" then
        self:Disable()
    elseif rest ~= "" then
        print("TRS: /trs debug opens chat diagnostics; /trs debug off stops them.")
    elseif InCombatLockdown() then
        print("TRS: Open chat diagnostics outside combat.")
    else
        self.enabled = true
        self.live = false
        self.session = (self.session or 0) + 1
        if not self.frame then self:CreateFrame() end
        self:RefreshButtons()
        self.frame:Show()
        self:LogEnvironment()
        self:Log("Dry run selected. Actual spell events are logged separately from simulated tests.")
    end
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, ...)
    if not Debug.enabled then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Debug:RefreshButtons()
    elseif event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        Debug:Log("GAME ERROR: " .. tostring(message))
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, action = ...
        Debug:Log(event .. " addon=" .. tostring(addon) .. " action=" .. tostring(action))
    else
        local unit, _, spellID = ...
        if unit == "player" then
            Debug:Log("ACTUAL " .. event .. " id=" .. tostring(spellID)
                .. " name=" .. tostring(spellID and TRS.GetSpellInfo(spellID)))
        end
    end
end)
