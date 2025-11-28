--[[
#########################################################################
#                                                                       #
# Telemetry Widget script for FrSky Horus/RadioMaster TX16s             #
# Copyright "Offer Shmuely"                                             #
#                                                                       #
# License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
#                                                                       #
# This program is free software; you can redistribute it and/or modify  #
# under the terms of the GNU General Public License version 2 as     #
# published by the Free Software Foundation.                            #
#                                                                       #
# This program is distributed in the hope that it will be useful        #
# but WITHOUT ANY WARRANTY; without even the implied warranty of        #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
# GNU General Public License for more details.                          #
#########################################################################

FEATURES
- Percent source selection:
  - Prefers Bat% telemetry. If unavailable, uses voltage-based calculation per cell lookup.
  - Battery Inserted Low (high % with low Vcell shortly after connect) forces corrected telemetry:
    • Captures a one-time offset = Bat% − calcPercent, then displays (Bat% − offset) for the flight.
    • If Bat% is absent while active, falls back to voltage calculation.
- Reserve percentage:
  - Option: "Reserve %". Values 0..50.
  - Applied to the final percentage via: if p<r then (p−r) else ((p−r)/(100−r))*100.
  - Also sets the single-step threshold (see below) when reserve>0.
- Single-step threshold (config.singleStepThreshold):
  - Default 15. Above the threshold, voice rounding speaks in tens (e.g., 27→30). At/under threshold, speaks every 1%.
  - When Reserve>0, the threshold is set to Reserve.
- Audio alerts:
  - Battery connected low (BatInL) haptic+voice, not silenced by ARM.
  - Percentage voice alerts obey single-step threshold and battLowMargin.
  - 100% announcement is suppressed.
  - ARM==2 (disarmed) suppresses percentage callouts, but not BatInL.
- Telemetry stability and resets:
  - After telemetry reconnect, waits TELEMETRY_STABILIZATION_DELAY before using values.
  - Battery Inserted Low detection window (BAT_INSERTED_DETECT_WINDOW) opens after stabilization; detection only occurs within this window.
  - RSSI==0 triggers a delayed reset (RSSI_DISCONNECT_DELAY) to prepare for next battery and avoid flapping.
  - 0V voltage triggers delayed reset (ZERO_VOLTAGE_DELAY).
- Display:
  - Color toggle option (0=white, 1=black) controls all text and battery outline.
  - Five battery fill colors at 20% steps (R→O→Y→Lime→G). Inserted-low forces red fill.
  - Small and Medium zones show a tiny "Reserve X%" label bottom-right.
- Performance:
  - Caches globals, preallocates filter buffer, avoids duplicate cell-count checks in background.

HOW IT WORKS (FLOW)
1) Option handling
   - Options are accessed by name (e.g., options[config.OPT_RESERVE], options[config.OPT_COLOR_TOGGLE]).
   - update() reads options and applies:
     • Reserve: clamps 0..50, cached to wgt.vReserve; sets config.singleStepThreshold.
     • Color toggle: sets wgt.text_color / wgt.cell_color (white or black).
   - update() does not reset runtime state (no filter/timer resets) to avoid mid-flight disruptions.

2) Data acquisition & guards (calculateBatteryData)
   - RSSI guard handles disconnect/reset.
   - Telemetry re-connect starts stabilization timer; only after it passes do we accept values.
   - Reads Vbat; 0V triggers delayed reset. Validates table vs single value.
   - Cell count: prefers Vcel sensor; else auto-detect once via thresholds.

3) Percent computation
   - Base percent:
     • If bat_connected_low==1 and Bat% present → use adjusted telemetry: (Bat% − offset).
     • Else if Bat% present → Bat%.
     • Else → voltage-derived percent (filtered).
   - Apply Reserve transform to base percent.

4) Battery Inserted Low detection
   - Only during detection window after stabilization.
   - Conditions: cell_detected, vPercent>batteryInsertedLowPercent, Vcell<LOW_BAT_INS_VOLTAGE, Vcell≥BATTERY_MIN_VOLTAGE.
   - On confirmation (BATTERY_CONNECTED_LOW_DELAY), sets bat_connected_low=1 and, if Bat% present, captures offset.

5) Audio
   - In background(), handleBatteryAlerts enforces one-call-per-cycle (audioProcessedThisCycle flag).
   - Rounds voice values above threshold; haptic+voice on critical; suppress 100%.
   - ARM==2 silences percentage callouts only; BatInL still plays.

6) Display
   - Uses wgt.text_color / wgt.cell_color for text/outline; reserve label shown in small/medium.
   - Fill color reflects percent thresholds and Inserted-Low state.
]]

-- Load modules
local config = loadScript("/WIDGETS/RFBattery/lib_config.lua", "tcd")()
local filters = loadScript("/WIDGETS/RFBattery/lib_battery_filters.lua", "tcd")()
local calc = loadScript("/WIDGETS/RFBattery/lib_battery_calc.lua", "tcd")()
local display = loadScript("/WIDGETS/RFBattery/lib_battery_display.lua", "tcd")()
local audio = loadScript("/WIDGETS/RFBattery/lib_battery_audio.lua", "tcd")()

-- Cache global functions for performance
local getValue = getValue
local model = model
local math = math

-- Simple logger
local function log(s)
    -- print("RFBattery: " .. s)
end

local function update(wgt, options)
    if (wgt == nil) then
        return
    end

    wgt.options = options

    -- Check telemetry sensor for cell count first, then auto detection
    local sensorCells = getValue(config.SENSOR_CELLS)
        if sensorCells ~= nil and sensorCells > 0 then
            -- use telemetry sensor cell count
            wgt.cellCount = math.floor(sensorCells)
            wgt.cell_detected = true
        else
        -- sensor not available or reading 0, fall back to GV or auto
        local gvCel = model.getGlobalVariable(config.GV_CEL, 0)
        if gvCel == 0 then
            -- auto cell detection
            wgt.cellCount = 1
            wgt.cell_detected = false
        else
            -- use GV cell count
            wgt.cellCount = gvCel
            wgt.cell_detected = true
        end
    end

    -- Set source name from hardcoded sensor
    wgt.options.source_name = config.SENSOR_VOLT

    -- Set text and border color from option (default to WHITE if not set or is 0)
    local colorToggle = wgt.options[config.OPT_COLOR_TOGGLE]
    do
        local cv
        if colorToggle ~= nil and colorToggle == 1 then
            cv = lcd.RGB(0, 0, 0)    -- black
        else
            cv = lcd.RGB(255, 255, 255)  -- white
        end
        wgt.text_color = cv
        wgt.cell_color = cv
    end

    -- Check if sensors are available
    local pcntValue = getValue(config.SENSOR_PCNT)
    wgt.useSensorP = (pcntValue ~= nil and pcntValue >= 0)
    
    local mahValue = getValue(config.SENSOR_MAH)
    wgt.useSensorM = (mahValue ~= nil and mahValue >= 0)
    
    wgt.useSensorC = (sensorCells ~= nil and sensorCells > 0)

    -- Set reserve percentage (applies to both sensor-based and voltage-based calculations)
    local reserveValue = wgt.options[config.OPT_RESERVE]
    if reserveValue ~= nil then
        -- Clamp to 0..50 to match option bounds
        reserveValue = math.max(0, math.min(50, reserveValue))
        wgt.vReserve = reserveValue
        config.singleStepThreshold = wgt.vReserve > 0 and wgt.vReserve or 20
    else
        wgt.vReserve = 0
        config.singleStepThreshold = 20
    end

    if wgt.useSensorP then
        -- using telemetry for battery %
        -- vReserve already set above
    else
        -- estimating battery % (fallback when Bat% sensor not available)
        wgt.vfltInterval = config.VFLT_INTERVAL_DEFAULT
        -- keep existing sample buffer; size will self-initialize in filter code if needed
    end
end

local function create(zone, options)
    -- Ensure option defaults are set once at creation (using numeric indices for reliability)
    if options[config.OPT_COLOR_TOGGLE] == nil then
        options[config.OPT_COLOR_TOGGLE] = 0
    end

    -- Determine initial color from toggle (0=white,1=black)
    local initialColor
    do
        local colorToggle = options[config.OPT_COLOR_TOGGLE]
        if colorToggle ~= nil and colorToggle == 1 then
            initialColor = lcd.RGB(0, 0, 0)
        else
            initialColor = lcd.RGB(255, 255, 255)
        end
    end

    local wgt = {
        zone = zone,
        options = options,
        counter = 0,

        text_color = initialColor,
        cell_color = initialColor,
        border_l = config.BORDER_LEFT,
        border_r = config.BORDER_RIGHT,
        border_t = config.BORDER_TOP,
        border_b = config.BORDER_BOTTOM,

        telemResetCount = 0,
        telemResetLowestMinRSSI = 101,
        isDataAvailable = 0,
        vMax = 0,
        vMin = 0,
        vTotalLive = 0,
        vPercent = 0,
        vMah = 0,
        cellCount = 1,
        cell_detected = false,
        bat_connected_low = 0,
        bat_connected_low_played = false,
        bat_connected_low_timer = 0,
        vCellLive = 0,
        mainValue = 0,
        secondaryValue = 0,

        battNextPlay = 0,
        battPercentPlayed = -1,                       -- Set to -1 initially to allow first announcement
        battPercentSetDuringCellDetection = false,   -- Track if percentage was set during cell detection phase
        audioProcessedThisCycle = false,             -- Track if audio has been processed this cycle (prevent double execution)

        vflt = {},
        vflti = 0,
        vfltSamples = 0,
        vfltInterval = 0, 
        vfltNextUpdate = 0,

        useSensorP = false,
        useSensorM = false,

        telemReconnectTime = 0,                        -- Time when telemetry reconnected (for stabilization delay)
        wasTelemetryLost = false,                      -- Track previous telemetry state
        rssiDisconnectTime = 0,                        -- Time when RSSI went to zero (for disconnect delay)
        zeroVoltageTime = 0,                           -- Time when voltage went to 0V (for zero voltage delay)
        
        batInsDetectDeadline = 0,                      -- End time for 'battery inserted low' detection window
        batLowOffset = 0,                              -- Offset to subtract from telemetry Bat% when inserted-low is active
    }

    -- imports
    wgt.ToolsClass = loadScript("/WIDGETS/" .. config.app_name .. "/lib_widget_tools.lua", "tcd")
    wgt.tools = wgt.ToolsClass(config.app_name)

    update(wgt, options)
    return wgt
end

-- This function allows recording of lowest cells when widget is in background
local function background(wgt)
    if (wgt == nil) then return end

    wgt.tools.detectResetEvent(wgt, function(wgt) calc.onTelemetryResetEvent(wgt, config) end)

    calc.calculateBatteryData(wgt, config, filters, calc, audio)

    -- Handle battery audio alerts (flag prevents double execution if called multiple times)
    audio.handleBatteryAlerts(wgt, config)

    -- Removed duplicate cell-count refresh here; calculateBatteryData handles it
end

local function refresh(wgt, event, touchState)
    if (wgt == nil)         then return end
    if type(wgt) ~= "table" then return end
    if (wgt.options == nil) then return end
    if (wgt.zone == nil)    then return end

    -- Reset audio processing flag at start of each refresh cycle
    wgt.audioProcessedThisCycle = false
    
    background(wgt)

    -- Color is already set in update() - no need to read again here (optimization #3)
    -- wgt.text_color and wgt.cell_color are already current from update()

    if (event ~= nil) then
        display.refreshAppMode(wgt, event, touchState, config)
        return
    end

    if wgt.zone.w > 180 and wgt.zone.h > 145 then
        display.refreshZoneLarge(wgt, config)
    elseif wgt.zone.w > 170 and wgt.zone.h >  80 then
        display.refreshZoneMedium(wgt, config)
    elseif wgt.zone.w > 150 and wgt.zone.h >  28 then
        display.refreshZoneSmall(wgt, config)
    elseif wgt.zone.w >  65 and wgt.zone.h >  35 then
        display.refreshZoneTiny(wgt, config)
    end
end

return { name = config.app_name, options = config.options, create = create, update = update, background = background, refresh = refresh }
