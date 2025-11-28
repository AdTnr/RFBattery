-- Battery calculation functions for RFBattery widget

local M = {}

-- Cache global functions for performance
local getValue = getValue
local getFieldInfo = getFieldInfo
local getTime = getTime
local getRSSI = getRSSI
local model = model
local playNumber = playNumber
local math = math

-- Helper function to apply reserve percentage to a battery percentage value
function M.applyReservePercentage(percent, reserve)
    if percent < reserve then
        return percent - reserve
    else
        local usable = 100 - reserve
        return (percent - reserve) / usable * 100
    end
end

-- This function returns the percentage remaining in a single Lipo cell
function M.getCellPercent(cellValue, lipoPercentListSplit)
    if cellValue == nil then
        return 0
    end

    -- in case somehow voltage is higher, don't return nil
    if (cellValue > 4.2) then
        return 100
    end

    -- Binary search through voltage lookup table to find matching percentage
    for i1, v1 in ipairs(lipoPercentListSplit) do
        -- Check if cellValue is within this sub-list's range (first to last value)
        if (cellValue <= v1[#v1][1]) then
            -- cellValue is in this sub-list, find the exact value
            for i2, v2 in ipairs(v1) do
                if v2[1] >= cellValue then
                    return v2[2]
                end
            end
        end
    end

    -- If we get here, cellValue is outside expected range but > 0
    -- Return 0 as fallback (shouldn't happen with valid voltage input)
    return 0
end

-- Only invoke this function once.
function M.calcCellCount(singleVoltage)
    if singleVoltage     < 4.3  then return 1
    elseif singleVoltage < 8.6  then return 2
    elseif singleVoltage < 12.9 then return 3
    elseif singleVoltage < 17.2 then return 4
    elseif singleVoltage < 21.5 then return 5
    elseif singleVoltage < 25.8 then return 6
    elseif singleVoltage < 30.1 then return 7
    elseif singleVoltage < 34.4 then return 8
    elseif singleVoltage < 38.7 then return 9
    elseif singleVoltage < 43.0 then return 10
    --elseif singleVoltage < 47.3 then return 11 -- 11s very rare and sometimes interfears with detection, so disabled for now
    elseif singleVoltage < 51.6 then return 12
    elseif singleVoltage < 60.2 then return 14
    end

    return 1
end

-- Reset widget to initial state (called by disconnect/zero voltage/telemetry reset)
function M.resetWidget(wgt, config)
    wgt.isDataAvailable = false
    wgt.vTotalLive = 0
    wgt.vCellLive = 0
    wgt.vPercent = 0
    wgt.mainValue = 0
    wgt.secondaryValue = 0
    wgt.vMah = 0
    wgt.useSensorP = false
    wgt.useSensorM = false
    wgt.useSensorC = false
    -- Reset filters for next battery
    wgt.vflt = {}
    wgt.vflti = 0
    wgt.vfltNextUpdate = 0
    -- Reset cell detection
    wgt.cellCount = 1
    wgt.cell_detected = false
    wgt.periodic1 = wgt.tools.periodicInit()
    -- Reset battery connected low warning
    wgt.bat_connected_low = 0
    wgt.bat_connected_low_played = false
    wgt.bat_connected_low_timer = 0
    -- Reset timers
    wgt.rssiDisconnectTime = 0
    wgt.zeroVoltageTime = 0
    wgt.audioProcessedThisCycle = false  -- Reset audio processing flag
    -- Track that telemetry was lost
    wgt.wasTelemetryLost = true
    wgt.telemReconnectTime = 0
    wgt.batInsDetectDeadline = 0
    wgt.batLowOffset = 0
end

-- Clear old telemetry data upon reset event
function M.onTelemetryResetEvent(wgt, config)
    wgt.telemResetCount = wgt.telemResetCount + 1

    -- Set to a value that will definitely trigger announcement when battery is detected
    -- Use -1 instead of 100 to ensure 100% will always be announced if battery is at 100%
    wgt.battPercentPlayed = -1
    wgt.battNextPlay = 0
    wgt.battPercentSetDuringCellDetection = false  -- Reset flag

    wgt.vMin = 99
    wgt.vMax = 0
    
    -- Reset widget state (but preserve telemResetCount which tracks number of resets)
    M.resetWidget(wgt, config)
    
    -- Additional reset for telemetry reset event (preserve reset count)
    -- Note: resetWidget already sets all values, this is mainly for clarity
end

-- This function calculates battery data and updates widget state
function M.calculateBatteryData(wgt, config, filters, calc, audio)
    -- Check if telemetry is disconnected (RSSI = 0 means no telemetry)
    local rssi = getRSSI()
    local currentTime = getTime()
    
    if rssi == 0 or rssi == nil then
        -- Telemetry appears disconnected - start timer if not already started
        if wgt.rssiDisconnectTime == 0 then
            wgt.rssiDisconnectTime = currentTime
        end
        
        -- Check if we've waited long enough before resetting
        local elapsed = currentTime - wgt.rssiDisconnectTime
        if elapsed >= config.RSSI_DISCONNECT_DELAY then
            -- RSSI has been zero for long enough - reset widget to prepare for next battery pack
            M.resetWidget(wgt, config)
            return
        else
            -- Still waiting - don't reset yet, but mark data as unavailable
            wgt.isDataAvailable = false
            return
        end
    else
        -- RSSI is active - cancel any disconnect timer
        if wgt.rssiDisconnectTime > 0 then
            wgt.rssiDisconnectTime = 0  -- Telemetry came back, cancel reset
        end
    end
    
    -- Telemetry is connected - check if it just reconnected
    if wgt.wasTelemetryLost then
        -- Telemetry just reconnected - start stabilization timer
        wgt.telemReconnectTime = currentTime
        wgt.wasTelemetryLost = false
    end
    
    -- Check if we're still in the stabilization period after reconnection
    if wgt.telemReconnectTime > 0 then
        local elapsed = currentTime - wgt.telemReconnectTime
        if elapsed < config.TELEMETRY_STABILIZATION_DELAY then
            -- Still stabilizing - don't accept telemetry values yet (they might be stale)
            wgt.isDataAvailable = false
            return
        else
            -- Stabilization period complete - clear timer and accept values
            wgt.telemReconnectTime = 0
            -- Start a short window where 'battery inserted low' can be detected
            wgt.batInsDetectDeadline = currentTime + config.BAT_INSERTED_DETECT_WINDOW
        end
    end
    
    local v = getValue(config.SENSOR_VOLT)
    -- Removed unused getFieldInfo call

    -- Check for zero voltage reading (battery disconnected)
    if v ~= nil and v == 0 then
        -- Voltage sensor is reading 0V - start timer if not already started
        if wgt.zeroVoltageTime == 0 then
            wgt.zeroVoltageTime = currentTime
        end
        
        -- Check if we've waited long enough before resetting
        local elapsed = currentTime - wgt.zeroVoltageTime
        if elapsed >= config.ZERO_VOLTAGE_DELAY then
            -- Voltage has been 0V for long enough - reset widget
            M.resetWidget(wgt, config)
            return
        else
            -- Still waiting - mark data as unavailable but don't reset yet
            wgt.isDataAvailable = false
            return
        end
    else
        -- Voltage is valid (> 0) - cancel any zero voltage timer
        if wgt.zeroVoltageTime > 0 then
            wgt.zeroVoltageTime = 0  -- Voltage came back, cancel reset
        end
    end

    if type(v) == "table" then
        -- multi cell values using FLVSS liPo Voltage Sensor
        if (#v > 1) then
            wgt.isDataAvailable = false
            return
        end
    elseif v ~= nil and v >= 1 then
        -- single cell or VFAS lipo sensor
        -- valid voltage reading
    else
        -- no telemetry available (telemetry connected but voltage sensor not available or invalid)
        wgt.isDataAvailable = false
        return
    end

    -- Check telemetry sensor for cell count (HIGHEST PRIORITY - always check first)
    -- Sensor takes precedence over auto-detection, even if auto-detection already set cell_detected
    local sensorCells = getValue(config.SENSOR_CELLS)
    wgt.useSensorC = (sensorCells ~= nil and sensorCells > 0)  -- Update flag dynamically
    if wgt.useSensorC then
        local newCellCount = math.floor(sensorCells)
        -- Always trust sensor if available - override auto-detection if different
        if newCellCount ~= wgt.cellCount then
            wgt.cellCount = newCellCount
            wgt.cell_detected = true  -- Sensor always sets cell_detected to true
            wgt.vMin = 99  -- reset min/max when cell count changes
            wgt.vMax = 0
        else
            -- Sensor matches current count - ensure cell_detected is true (trust sensor over auto-detection)
            wgt.cell_detected = true
        end
    elseif not wgt.cell_detected then
        -- Sensor not available and cell_detected is false - use auto-detection
        local newCellCount = M.calcCellCount(v)
        if (wgt.tools.periodicHasPassed(wgt.periodic1)) then
            wgt.cell_detected = true
            wgt.periodic1 = wgt.tools.periodicInit()
            wgt.cellCount = newCellCount
            -- Only play warning if not disarmed (ARM != 2)
            -- Removed early BatLow alert to avoid conflict with battery-inserted-low flow
            -- local armValue = getValue(config.SENSOR_ARM)
            -- if (v / newCellCount) < config.cellFull and (armValue == nil or armValue ~= 2) then
            --     audio.playAudio(config.AUDIO_PATH, "BatLow")
            --     playNumber(v * 10, 1, PREC1)
            -- end
        else
            -- this is necessary for simu where cell-count can change
            if newCellCount ~= wgt.cellCount then
                wgt.vMin = 99
                wgt.vMax = 0
            end
            wgt.cellCount = newCellCount
        end
    end

    -- calc highest of all cells
    if v > wgt.vMax then
        wgt.vMax = v
    end

    wgt.vTotalLive = v
    wgt.vCellLive = wgt.vTotalLive / wgt.cellCount

    -- Calculate battery percentage: prioritize Bat% sensor unless battery connected low warning is active
    local pcnt = getValue(config.SENSOR_PCNT)
    wgt.useSensorP = (pcnt ~= nil and pcnt >= 0)  -- Update flag dynamically
    
    local basePercent
    if wgt.bat_connected_low == 1 then
        -- Battery inserted low confirmed: prefer telemetry percentage minus offset if available
        if wgt.useSensorP then
            local adjusted = pcnt - (wgt.batLowOffset or 0)
            if adjusted < 0 then adjusted = 0 end
            if adjusted > 100 then adjusted = 100 end
            basePercent = adjusted
        else
            -- Fallback to voltage-based if telemetry percentage is unavailable
            basePercent = filters.updateFilteredvPercent(wgt, M.getCellPercent(wgt.vCellLive, config.lipoPercentListSplit), config)
        end
    elseif wgt.useSensorP then
        -- Bat% sensor is available and battery connected low not active
        basePercent = pcnt
    else
        -- Bat% sensor not available, fall back to voltage-based calculation
        basePercent = filters.updateFilteredvPercent(wgt, M.getCellPercent(wgt.vCellLive, config.lipoPercentListSplit), config)
    end
    
    -- Apply reserve percentage to calculated percentage
    do
        local reserveVal = wgt.vReserve
        if wgt.options then
            local rv = wgt.options[config.OPT_RESERVE]
            if rv ~= nil then
                reserveVal = math.max(0, math.min(50, rv))
            end
        end
        if reserveVal == nil then reserveVal = 0 end
        wgt.vReserve = reserveVal
        wgt.vPercent = M.applyReservePercentage(basePercent, reserveVal)
    end

    -- Check for battery inserted low: high percentage but low cell voltage
    -- Only check if not already in battery connected low mode
    if wgt.bat_connected_low == 0 then
        local currentTime = getTime()
        
        -- Only check after telemetry has stabilized and cell count is established
        -- Also ensure voltage is above minimum threshold (not disconnected/faulty battery)
        if wgt.cell_detected 
            and currentTime <= wgt.batInsDetectDeadline 
            and wgt.vPercent > config.batteryInsertedLowPercent 
            and wgt.vCellLive < config.LOW_BAT_INS_VOLTAGE 
            and wgt.vCellLive >= config.BATTERY_MIN_VOLTAGE then
            -- Start timer if not already started
            if wgt.bat_connected_low_timer == 0 then
                wgt.bat_connected_low_timer = currentTime
            end
            
            -- Check if enough time has passed for confirmation (shorter delay since telemetry already stabilized)
            local elapsed = currentTime - wgt.bat_connected_low_timer
            if elapsed >= config.BATTERY_CONNECTED_LOW_DELAY then
                wgt.bat_connected_low = 1
                -- Capture offset once at trigger time if telemetry percent is available
                if wgt.useSensorP then
                    local calcPercentRaw = M.getCellPercent(wgt.vCellLive, config.lipoPercentListSplit)
                    local offset = pcnt - calcPercentRaw
                    if offset < 0 then offset = 0 end
                    if offset > 100 then offset = 100 end
                    wgt.batLowOffset = offset
                else
                    wgt.batLowOffset = 0
                end
            else
                wgt.bat_connected_low = 0  -- Still confirming
            end
        else
            -- Reset timer (but don't reset bat_connected_low if already set - it persists)
            wgt.bat_connected_low_timer = 0
        end
    end

    -- Update mAh sensor availability dynamically
    local mahValue = getValue(config.SENSOR_MAH)
    wgt.useSensorM = (mahValue ~= nil and mahValue >= 0)
    if wgt.useSensorM then
        wgt.vMah = mahValue
    end

    -- mainValue
    wgt.mainValue = wgt.vCellLive
    wgt.secondaryValue = wgt.vTotalLive

    --- calc lowest main voltage
    if wgt.mainValue < wgt.vMin and wgt.mainValue > 1 then
        -- min 1v to consider a valid reading
        wgt.vMin = wgt.mainValue
    end

    wgt.isDataAvailable = true
    -- if need detection and not detecting, start detection
    -- Use telemetry stabilization delay (convert from 10ms units to milliseconds)
    if not wgt.cell_detected and wgt.tools.getDurationMili(wgt.periodic1) == -1 then
        wgt.tools.periodicStart(wgt.periodic1, config.TELEMETRY_STABILIZATION_DELAY * 10)
    end
end

return M

