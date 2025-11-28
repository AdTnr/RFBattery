local app_name, p2 = ...

local M = {}
M.app_name = app_name


--------------------------------------------------------------
local function log(s)
    -- print(M.app_name .. ": " .. s)
end
---------------------------------------------------------------------------------------------------

function M.periodicInit()
    local t = {}
    t.startTime = -1;
    t.durationMili = -1;
    return t
end

function M.periodicStart(t, durationMili)
    t.startTime = getTime();
    t.durationMili = durationMili;
end

function M.periodicHasPassed(t)
    -- not started yet
    if (t.durationMili <= 0) then
        return false;
    end

    local elapsed = getTime() - t.startTime;
    -- log(string.format('elapsed: %d (t.durationMili: %d)', elapsed, t.durationMili))
    local elapsedMili = elapsed * 10;
    if (elapsedMili < t.durationMili) then
        return false;
    end
    return true;
end

function M.getDurationMili(t)
    return t.durationMili
end
--
function M.detectResetEvent(wgt, callback_onTelemetryResetEvent)

    local currMinRSSI = getValue('RSSI-')
    if (currMinRSSI == nil) then
        --log("telemetry reset event: can not be calculated")
        return
    end
    if (currMinRSSI == wgt.telemResetLowestMinRSSI) then
        --log("telemetry reset event: not found")
        return
    end

    if (currMinRSSI < wgt.telemResetLowestMinRSSI) then
        -- rssi just got lower, record it
        wgt.telemResetLowestMinRSSI = currMinRSSI
        --log("telemetry reset event: not found")
        return
    end

    -- reset telemetry detected
    wgt.telemResetLowestMinRSSI = 101
    --log("telemetry reset event detected")

    -- notify event
    callback_onTelemetryResetEvent(wgt)
end

return M
