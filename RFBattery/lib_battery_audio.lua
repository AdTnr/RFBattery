-- Audio and alert handling functions for RFBattery widget

local M = {}

-- Cache global functions for performance
local getValue = getValue
local getTime = getTime
local playHaptic = playHaptic
local playFile = playFile
local playNumber = playNumber
local math = math

-- Audio support - play audio file
function M.playAudio(audioPath, fileName)
    playFile(audioPath .. fileName .. ".wav")
end

-- Handle battery audio alerts based on widget state
function M.handleBatteryAlerts(wgt, config)
    -- Prevent double execution: EdgeTX may call background() and refresh() independently,
    -- and refresh() also calls background(), so handleBatteryAlerts could run twice per cycle
    -- Use cycle counter instead of time for more reliable detection
    if wgt.audioProcessedThisCycle then
        return  -- Already processed this cycle
    end
    wgt.audioProcessedThisCycle = true
    
    -- Check ARM telemetry - if ARM == 2 (disarmed), silence battery percentage warnings only
    -- Graceful fallback: if ARM sensor not detected (nil), assume armed and allow warnings
    local armValue = getValue(config.SENSOR_ARM)
    local isDisarmed = (armValue ~= nil and armValue == 2)  -- Only disarmed if ARM sensor exists and equals 2

    -- haptic feedback for battery connected low (always plays, regardless of ARM status)
    -- Set flag BEFORE playing to prevent double announcement
    if wgt.bat_connected_low == 1 and not wgt.bat_connected_low_played then
        wgt.bat_connected_low_played = true  -- Set flag FIRST to prevent double trigger
        playHaptic(100, 0, PLAY_NOW)
        M.playAudio(config.AUDIO_PATH, "BatInL")
    elseif wgt.bat_connected_low == 0 then
        wgt.bat_connected_low_played = false
    end

    -- voice alerts (only if armed - battery connected low is handled separately above)
    -- Fallback: if ARM sensor unavailable, warnings play normally (assumes armed)
    if not isDisarmed and wgt.isDataAvailable then
        local fvpcnt = wgt.vPercent

        -- what do we have to report?
        local battva = 0
        if fvpcnt > config.singleStepThreshold then
            battva = math.ceil(fvpcnt / 10) * 10
        else
            battva = fvpcnt
        end

        -- silence until cell_detected
        if not wgt.cell_detected then
            wgt.battPercentPlayed = battva
            wgt.battPercentSetDuringCellDetection = true  -- Track that we set this during cell detection
            return  -- Don't announce anything until cell detection is complete
        end

        local critical = wgt.vReserve == 0 and config.singleStepThreshold or 0

        -- Special handling: If battPercentPlayed was set during cell detection phase,
        -- skip announcement on the first cycle after cell detection completes (even if percentage changed slightly)
        local wasSetDuringDetection = wgt.battPercentSetDuringCellDetection
        if wasSetDuringDetection then
            -- Cell detection just completed - skip first announcement to prevent double announcement
            wgt.battPercentSetDuringCellDetection = false
            wgt.battPercentPlayed = battva  -- Update to current value
            wgt.battNextPlay = getTime() + 500  -- Add delay to prevent immediate second announcement
            return
        end

        -- silence routine bat% reports if not using sensorP
        if not wgt.useSensorP and battva > critical + config.battLowMargin then
            wgt.battPercentPlayed = battva
        end
        
        local shouldAnnounce = (wgt.battPercentPlayed ~= battva or battva <= 0) and getTime() > wgt.battNextPlay
        
        -- Skip announcement if battery is at 100% (don't announce full battery)
        if battva == 100 then
            wgt.battPercentPlayed = battva  -- Update flag silently without announcing
            return
        end
        
        if shouldAnnounce then
            -- Set flags BEFORE playing to prevent double announcement if function is called multiple times
            wgt.battPercentPlayed = battva
            wgt.battNextPlay = getTime() + 500

            -- urgent?
            if battva > critical + config.battLowMargin then
                M.playAudio(config.AUDIO_PATH, "battry")
            elseif battva > critical then
                M.playAudio(config.AUDIO_PATH, "batlow")
            else
                M.playAudio(config.AUDIO_PATH, "batcrt")
                playHaptic(100, 0, PLAY_NOW)
            end

            -- play % if >= 0 (but not 100% - handled above)
            if battva >= 0 then
                playNumber(battva, 13)
            end
        end
    end
end

return M

