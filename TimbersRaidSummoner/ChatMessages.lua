local TRS = _G["TimbersRaidSummoner"]

function TRS:DebugChat(message)
    if self.ChatDebug and self.ChatDebug.enabled then
        self.ChatDebug:Log(message)
    end
end

function TRS:BuildQueueSayMacro(playerName, settings)
    settings = settings or TimbersRaidSummonerDB.settings
    if not settings.sendSayMessage then return "" end
    local message = string.gsub(settings.sayMessage or "Summoning %s", "%%s", playerName)
    return "/s " .. message .. "\n"
end

function TRS:SendSummonChat(message, channel, target)
    self:DebugChat("SEND " .. channel .. (target and " -> " .. target or "") .. ": " .. message)
    if not (self.ChatDebug and self.ChatDebug.enabled) then
        return SendChatMessage(message, channel, nil, target)
    end

    local ok, result = pcall(SendChatMessage, message, channel, nil, target)
    if not ok then
        self:DebugChat("ERROR " .. tostring(result))
        error(result, 0)
    end
    self:DebugChat("SendChatMessage returned " .. tostring(result) .. "; delivery not confirmed")
    return result
end

-- Queue say runs in the secure macro. Meeting-stone say runs in the timer.
-- Tests supply settings and a sender without changing saved settings or queue state.
function TRS:SendSummonMessages(playerName, source, settings, send)
    settings = settings or TimbersRaidSummonerDB.settings
    send = send or function(message, channel, target)
        return self:SendSummonChat(message, channel, target)
    end

    if source == "stone" then
        if settings.sendSayMessage then
            local message = string.gsub(settings.sayMessage or "Summoning %s", "%%s", playerName)
            send(message, "SAY")
        else
            self:DebugChat("SKIP SAY: disabled")
        end
    end

    if settings.sendRaidMessage then
        local message = string.gsub(settings.raidMessage or "Summoning %s", "%%s", playerName)
        send(message, IsInRaid() and "RAID" or "PARTY")
    else
        self:DebugChat("SKIP group message: disabled")
    end

    if settings.autoWhisper then
        send(settings.whisperMessage or "Summoning you now", "WHISPER", playerName)
    else
        self:DebugChat("SKIP WHISPER: disabled")
    end
end
