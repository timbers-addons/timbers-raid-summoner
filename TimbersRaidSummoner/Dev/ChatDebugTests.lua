-- Run from the repository root: lua TimbersRaidSummoner/Dev/ChatDebugTests.lua
-- WoW stubs verify routing and state. Secure macro execution needs an in-game check.
local sent, timers, frames = {}, {}, {}
local group, combat, failSend = "party", false, false
local playerClass, spellName = "MAGE", "Ritual of Summoning"
local now, checks = 100, 0
local Frame = {}
Frame.__index = Frame
local function frame()
    return setmetatable({ scripts = {}, attributes = {}, text = "", shown = true }, Frame)
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn) self.scripts[name] = fn end
function Frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function Frame:SetAttribute(key, value)
    assert(not combat, "Secure attributes changed in combat")
    self.attributes[key] = value
end
function Frame:GetAttribute(key) return self.attributes[key] end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function Frame:GetText() return self.text end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:CreateFontString() return frame() end
function Frame:CreateTexture() return frame() end
function Frame:GetNormalTexture() return frame() end
for _, method in ipairs({ "SetSize", "SetPoint", "SetFrameStrata", "SetBackdrop", "EnableMouse",
    "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetWidth", "SetHeight",
    "SetJustifyH", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
    "SetMultiLine", "SetFontObject", "SetScrollChild", "SetCursorPosition", "SetNormalTexture",
    "SetHighlightTexture", "SetAlpha", "SetTextColor" }) do
    Frame[method] = function() end
end
function CreateFrame(_, name)
    local result = frame()
    table.insert(frames, result)
    if name then _G[name] = result end
    return result
end
C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "test" or "TRS" end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() end }
C_Timer = { After = function(delay, fn) table.insert(timers, { delay = delay, fn = fn }) end }
StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}
UIParent, GameTooltip = frame(), frame()
function IsInRaid() return group == "raid" end
function IsInGroup() return group ~= "solo" end
function InCombatLockdown() return combat end
function GetTime() return now end
function GetBuildInfo() return "1.15.9", "test-build", "", 11509 end
function GetLocale() return "enUS" end
function GetRealZoneText() return "Test zone" end
function UnitClass() return playerClass, playerClass end
function UnitName(unit) return unit == "player" and "Tester" or "Other" end
function GetSpellInfo() return spellName end
function IsSpellKnown() return true end
function UnitIsConnected() return true end
function UnitExists() return true end
function UnitLevel() return 20 end
function UnitPower() return 1000 end
function UnitChannelInfo() return spellName end
function UnitInParty() return group == "party" end
function UnitInRaid() return group == "raid" end
function GetNumGroupMembers() return group == "solo" and 0 or 2 end
function GetItemCount() return 5 end
function PlaySound() end
function time() return 100000 end
function strsplit(_, value) return value:match("^[^-]+") end
function SendChatMessage(message, channel, _, target)
    if failSend then error("test blocked send") end
    table.insert(sent, { message = message, channel = channel, target = target })
end
local function equal(actual, expected, reason)
    checks = checks + 1
    assert(actual == expected, reason .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(text, expected, reason)
    checks = checks + 1
    assert(text:find(expected, 1, true), reason .. ": missing " .. expected)
end
local function flush()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do now = now + timer.delay; timer.fn() end
end
local function click(button, mouseButton)
    mouseButton = mouseButton or "RightButton"
    local registered = false
    for _, event in ipairs(button.clicks or {}) do
        if event == "AnyUp" or event == mouseButton .. "Up" then registered = true end
    end
    assert(registered, "Button must register for the tested mouse release")
    button.scripts.PostClick(button, mouseButton)
end
local function log() return table.concat(TimbersRaidSummoner.ChatDebug.lines, "\n") end

dofile("TimbersRaidSummoner/Compat.lua")
dofile("TimbersRaidSummoner/TimbersRaidSummoner.lua")
local TRS = TimbersRaidSummoner
local addonEvents = frames[#frames]
dofile("TimbersRaidSummoner/ChatMessages.lua")
dofile("TimbersRaidSummoner/ChatDebug.lua")
local debugEvents = frames[#frames]

-- Newer engines only have C_Spell.GetSpellInfo, which returns a table.
do
    local legacy = GetSpellInfo
    GetSpellInfo = nil
    C_Spell = { GetSpellInfo = function(id) return { name = "Ritual " .. id, iconID = 7, spellID = id } end }
    local name, _, icon, _, _, _, id = TRS.GetSpellInfo(698)
    equal(name, "Ritual 698", "C_Spell name is returned positionally")
    equal(icon, 7, "C_Spell icon lands in the legacy icon slot")
    equal(id, 698, "C_Spell spell ID lands in the legacy slot")
    GetSpellInfo, C_Spell = legacy, nil
end
-- Initialize saved variables without constructing the unrelated main window.
TRS.CreateMainFrame = function() end
TRS.InitializeMinimapButton = function() end
addonEvents.scripts.OnEvent(addonEvents, "ADDON_LOADED", "TimbersRaidSummoner")
flush()
local saved = TimbersRaidSummonerDB.settings
saved.sendRaidMessage, saved.sendSayMessage, saved.autoWhisper = true, true, true
saved.raidMessage, saved.sayMessage, saved.whisperMessage = "Group %s", "Say %s", "Whisper %s"

-- Normal sends keep existing formatting and ordering, without test labels.
TRS:SendSummonMessages("Other", "queue")
equal(#sent, 2, "Queue say must not be duplicated in the callback")
equal(sent[1].channel, "PARTY", "Party route")
equal(sent[1].message, "Group Other", "Group substitution")
equal(sent[2].target, "Other", "Whisper recipient")
equal(sent[2].message, "Whisper %s", "Existing whisper text stays literal")
equal(TRS:BuildQueueSayMacro("Other"), "/s Say Other\n", "Normal say macro")
sent = {}
group = "raid"
TRS:SendSummonMessages("Other", "stone")
equal(#sent, 3, "Meeting-stone channel count")
equal(sent[1].channel, "SAY", "Meeting-stone say first")
equal(sent[2].channel, "RAID", "Raid route")
equal(sent[3].channel, "WHISPER", "Meeting-stone whisper last")

-- A solo mage can preview all controls without sending or altering persistent state.
local Debug = TRS.ChatDebug
equal(Debug.enabled, false, "Logging is opt-in")
equal(Debug:HandleSlash("debugger"), false, "Unrelated slash commands are not consumed")
group, sent = "solo", {}
SlashCmdList.TIMBERSRAIDSUMMONER("debug")
equal(#Debug.buttons, 8, "Both routes and all individual channels have controls")
Debug.targetBox:SetText("Other-Realm")
local queue = TimbersRaidSummonerDB.summonQueue
for _, button in ipairs(Debug.buttons) do
    equal(button:GetAttribute("macrotext2"), "", "Dry run cannot execute a chat macro")
    for _, mouseButton in ipairs({ "LeftButton", "RightButton" }) do
        local before = #timers
        click(button, mouseButton)
        equal(#timers, before + 1, button.source .. " " .. button.channel .. " must respond once to " .. mouseButton)
    end
end
flush()
equal(#sent, 0, "Dry run must never send chat")
equal(TimbersRaidSummonerDB.summonQueue, queue, "Tests do not replace queue")
equal(#queue, 0, "Tests do not enqueue players")
equal(saved.sayMessage, "Say %s", "Tests do not overwrite templates")
contains(log(), "WOULD SEND WHISPER -> Other-Realm", "Dry run reports recipient")
contains(log(), "WOULD RUN MACRO: /s [TRS TEST] Say Other-Realm", "Dry run reports queue macro")
contains(log(), "real event timing not tested", "Simulation limit is explicit")

-- Live queue say remains a secure macro; only group and whisper use the delay.
group = "party"
Debug.modeButton.scripts.OnClick()
local queueAll, stoneAll = Debug.buttons[1], Debug.buttons[5]
contains(queueAll:GetAttribute("macrotext2"), "/stopmacro [combat]\n/s [TRS TEST] Say Other-Realm",
    "Live queue macro preserves say route and stops in combat")
equal(queueAll:GetAttribute("type1"), "macro", "Left click uses the secure macro action")
equal(queueAll:GetAttribute("macrotext1"), queueAll:GetAttribute("macrotext2"), "Both mouse buttons use the same say macro")
equal(queueAll:GetAttribute("macrotext2"):find("/cast", 1, true), nil, "Test cannot cast a spell")
click(queueAll)
equal(#sent, 0, "No immediate SendChatMessage call for queue tests")
equal(timers[1].delay, 0.1, "Production callback delay is preserved")
flush()
equal(#sent, 2, "Queue callback sends only group and whisper")
equal(sent[1].message, "[TRS TEST] Group Other-Realm", "Live tests are visibly labeled")
equal(sent[2].target, "Other-Realm", "Realm-qualified whisper recipient is retained")

sent = {}
click(stoneAll)
flush()
equal(#sent, 3, "Live meeting-stone test sends all enabled channels without a warlock")
equal(sent[1].channel, "SAY", "Stone say uses SendChatMessage")
contains(log(), "delivery not confirmed", "An API return is not treated as delivery")

local expectedCallbacks = { 2, 1, 0, 1, 3, 1, 1, 1 }
for index, button in ipairs(Debug.buttons) do
    equal(button:GetAttribute("macrotext1"), button:GetAttribute("macrotext2"),
        "Left and right click must prepare the same live macro")
    for _, mouseButton in ipairs({ "LeftButton", "RightButton" }) do
        sent = {}
        click(button, mouseButton)
        flush()
        equal(#sent, expectedCallbacks[index], button.source .. " " .. button.channel
            .. " must dispatch the expected channels once on " .. mouseButton)
    end
end

-- Individual tests work even when the corresponding saved settings are disabled.
saved.sendRaidMessage, saved.sendSayMessage, saved.autoWhisper = false, false, false
Debug:RefreshButtons()
sent = {}
click(stoneAll)
flush()
equal(#sent, 0, "All respects disabled saved settings")
for index, expected in pairs({ [6] = "PARTY", [7] = "SAY", [8] = "WHISPER" }) do
    sent = {}
    click(Debug.buttons[index])
    flush()
    equal(#sent, 1, "Individual test isolates one channel")
    equal(sent[1].channel, expected, "Individual channel selection")
end
equal(saved.autoWhisper, false, "Individual tests do not enable saved options")
equal(Debug.buttons[3]:GetAttribute("macrotext2"), "/stopmacro [combat]\n/s [TRS TEST] Say Other-Realm\n",
    "Individual queue say uses macro despite disabled saved setting")

sent, group = {}, "raid"
click(Debug.buttons[6])
flush()
equal(sent[1].channel, "RAID", "Live tests follow current raid membership")
sent, group = {}, "solo"
click(Debug.buttons[6])
flush()
equal(#sent, 0, "Live group test skips nonexistent group")
contains(log(), "join a real party/raid", "Solo live skip is explained")

-- Combat and invalid input cannot leave a test using a new recipient with an old macro.
combat = true
Debug.targetBox:SetText("Changed")
click(queueAll)
equal(#timers, 0, "Combat click cannot schedule chat")
combat = false
debugEvents.scripts.OnEvent(debugEvents, "PLAYER_REGEN_ENABLED")
equal(queueAll.testTarget, "Changed", "Deferred recipient refresh after combat")
Debug.targetBox:SetText("bad\n/cast spell")
equal(queueAll:GetAttribute("macrotext2"), "", "Invalid recipient clears live macro")
click(queueAll)
equal(#timers, 0, "Invalid recipient cannot schedule chat")
Debug.targetBox:SetText("Other")
saved.sayMessage = "Hello\n/cast Something"
Debug:RefreshButtons()
equal(Debug.buttons[3]:GetAttribute("macrotext2"), "/stopmacro [combat]\n/s [TRS TEST] Hello /cast Something\n",
    "Saved newlines cannot inject test macro commands")
saved.sayMessage = "Say %s"

-- A failed send logs the error and preserves the existing stop-on-error order.
saved.sendRaidMessage, saved.sendSayMessage, saved.autoWhisper = true, true, true
Debug:RefreshButtons()
group, sent, failSend = "party", {}, true
click(stoneAll)
flush()
equal(#sent, 0, "Failed first send does not continue to other channels")
contains(log(), "test blocked send", "Lua send errors appear in log")
failSend = false
debugEvents.scripts.OnEvent(debugEvents, "ADDON_ACTION_BLOCKED", "TimbersRaidSummoner", "SendChatMessage")
contains(log(), "ADDON_ACTION_BLOCKED", "Protected-action diagnostics")
debugEvents.scripts.OnEvent(debugEvents, "UI_ERROR_MESSAGE", 1, "test game error")
contains(log(), "GAME ERROR: test game error", "Game error diagnostics")

-- Disabling or reopening cancels a delayed test and resets live mode.
click(stoneAll)
Debug.modeButton.scripts.OnClick()
flush()
equal(#sent, 0, "Switching to dry run cancels pending live callbacks")
Debug.modeButton.scripts.OnClick()
click(stoneAll)
Debug:Disable()
flush()
equal(#sent, 0, "Disabling cancels pending callback")
equal(Debug.live, false, "Live mode is reset on close")
equal(queueAll:GetAttribute("macrotext2"), "", "Closing disarms the live macro")
equal(queueAll:GetAttribute("macrotext1"), "", "Closing also disarms the left-click macro")
local lines = #Debug.lines
TRS:DebugChat("disabled message")
equal(#Debug.lines, lines, "Disabled logging remains quiet")
Debug:HandleSlash("debug")
Debug.modeButton.scripts.OnClick()
click(stoneAll)
Debug:HandleSlash("debug")
flush()
equal(#sent, 0, "Reopening invalidates old callbacks")

-- Exercise the real queue PostClick and real event handler, not just test dispatch.
TRS.mainFrame = frame()
TRS.summonQueueFrame = { content = frame(), buttons = {} }
playerClass = "WARLOCK"
TRS:AddToSummonQueue("Other")
contains(log(), "Dry run selected", "Diagnostics remain usable after reopen")
local realButton = TRS.summonQueueFrame.buttons[1]
equal(realButton:GetAttribute("macrotext2"), "/s Say Other\n/target Other\n/cast Ritual of Summoning",
    "Production queue macro is unchanged")
click(realButton)
addonEvents.scripts.OnEvent(addonEvents, "UNIT_SPELLCAST_START", "player", "cast", 698)
flush()
equal(#sent, 2, "Actual queue event still dispatches group and whisper")
equal(sent[1].message, "Group Other", "Normal messages never receive the test prefix")
contains(log(), "fromQueue=true", "Real summon state is logged")
sent = {}
TRS:ParseChatMessage("please 123", "Requester-Realm")
equal(#queue, 2, "Incoming request still adds a player")
contains(log(), "REQUEST Requester matched keyword *123", "Incoming keyword diagnosis")
addonEvents.scripts.OnEvent(addonEvents, "UNIT_SPELLCAST_INTERRUPTED", "player", "cast", 698)
spellName = "Localized ritual"
addonEvents.scripts.OnEvent(addonEvents, "UNIT_SPELLCAST_START", "player", "cast", 698)
flush()
contains(log(), "SKIP group/whisper: summon not from queue",
    "Summon is matched by spell ID, so a localized name still starts the manual summon flow")
equal(#sent, 0, "Manual casts still send no group or whisper messages")
contains(log(), "name=Localized ritual", "Localized spell names are visible for diagnosis")

-- Real meeting-stone events also use the shared sender, including on a non-warlock.
playerClass, spellName = "MAGE", "Meeting Stone Summon"
addonEvents.scripts.OnEvent(addonEvents, "UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 23598)
flush()
equal(#sent, 3, "Real meeting-stone event still sends all three channels")
equal(sent[1].channel, "SAY", "Real meeting-stone say is first")
equal(sent[2].message, "Group Other", "Real meeting-stone messages have no test label")

for i = 1, 250 do Debug:Log("bounded " .. i) end
equal(#Debug.lines, 200, "Log memory is bounded")
print("Chat diagnostics: " .. checks .. " assertions passed")
