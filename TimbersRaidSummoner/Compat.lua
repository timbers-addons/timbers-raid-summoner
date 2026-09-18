-- Client API compatibility layer.
--
-- Classic Era / TBC Anniversary run the pre-Cataclysm API. WoW: Forever runs
-- the Midnight (retail) engine, which renamed or removed a number of globals.
-- This file is the only place allowed to touch a client-specific global; the
-- rest of the addon calls the TRS.* wrappers below so it reads the same on
-- every client. It loads first, so it owns the addon table.

local TRS = _G["TimbersRaidSummoner"] or {}
_G["TimbersRaidSummoner"] = TRS

-- Newer engines moved spell lookups under C_Spell and removed the global.
-- Keep the old positional return shape so call sites are unchanged.
function TRS.GetSpellInfo(spell)
    if GetSpellInfo then return GetSpellInfo(spell) end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
    if not info then return nil end
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
end

-- Same move for item counts: the global is gone on Forever, C_Item has it.
TRS.GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount) or function() return 0 end

-- SendChatMessage is deprecated on the retail engine (11.2.0) in favor of
-- C_ChatInfo.SendChatMessage, same arguments. Still present on Forever
-- 1.60.1, so the global is preferred while it lasts.
TRS.SendChatMessage = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)

-- Addon messages. Pre-Cata clients still expose the global SendAddonMessage;
-- newer ones only have C_ChatInfo, and both need the prefix registered.
TRS.ADDON_PREFIX = "TRS"
if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    C_ChatInfo.RegisterAddonMessagePrefix(TRS.ADDON_PREFIX)
end
if type(SendAddonMessage) == "function" then
    function TRS.SendAddonMessage(prefix, message, channel)
        return SendAddonMessage(prefix, message, channel)
    end
elseif C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function" then
    function TRS.SendAddonMessage(prefix, message, channel)
        return C_ChatInfo.SendAddonMessage(prefix, message, channel)
    end
else
    function TRS.SendAddonMessage()
        return false
    end
end

-- Per-client content decisions. Project ID checks live here, not in UI code.
-- Classic Era shamans keep the vanilla pink class color; later flavors use
-- blue. Forever's WOW_PROJECT_ID is not confirmed yet, so it lands on blue.
TRS.Client = {
    shamanDefaultColor = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) and "pink" or "blue",
}
