-- Display and rendering functions for RFBattery widget

local M = {}

-- Cache global functions for performance
local lcd = lcd
local string = string
local math = math

-- Helper function to format cell voltage display string
function M.formatCellVoltageString(cellVoltage, cellCount, cellDetected)
    if cellDetected then
        return string.format("%.2f V (%.0fS)", cellVoltage, cellCount)
    else
        return string.format("%.2f V (?S)", cellVoltage)
    end
end

-- Helper function to format total voltage
function M.formatTotalVoltage(voltage)
    return string.format("%.2f V", voltage)
end

-- Helper function to format percentage
function M.formatPercentage(percent)
    return string.format("%.0f%%", percent)
end

-- Helper function to format mAh
function M.formatMah(mah)
    return string.format("%.0f mah", mah)
end

-- Helper function to get secondary info text (battery connected low warning or mAh)
function M.getSecondaryInfoText(wgt)
    if wgt.bat_connected_low == 1 then
        return "Bat Connected Low"
    elseif wgt.useSensorM then
        return M.formatMah(wgt.vMah)
    else
        return nil
    end
end

-- Color for battery - uses 5 predefined color thresholds at equal 20% increments (red -> orange -> yellow -> lime -> green)
function M.getPercentColor(wgt, config)
    -- 5 thresholds with predefined colors at equal 20% intervals
    if wgt.vPercent <= 20 then
        -- Threshold 1: 0-20% - Red
        return RED
    elseif wgt.vPercent <= 40 then
        -- Threshold 2: 20-40% - Orange
        return ORANGE
    elseif wgt.vPercent <= 60 then
        -- Threshold 3: 40-60% - Yellow
        return YELLOW
    elseif wgt.vPercent <= 80 then
        -- Threshold 4: 60-80% - Lime/Light Green (explicit RGB to avoid firmware constant issues)
        return lcd.RGB(160, 255, 0)
    else
        -- Threshold 5: 80-100% - Green
        return GREEN
    end
end

-- Get battery fill color for battery inserted low warning
function M.getBatteryFillColor(wgt, config)
    -- If battery inserted low warning is active, always show red
    if wgt.bat_connected_low == 1 then
        return RED
    else
        return M.getPercentColor(wgt, config)
    end
end

function M.drawBattery(wgt, myBatt, config)
    -- fill batt
    local fill_color = M.getBatteryFillColor(wgt, config)
    local pcntY = math.floor(wgt.vPercent / 100 * (myBatt.h - myBatt.cath_h))
    local rectY = wgt.zone.y + myBatt.y + myBatt.h - pcntY
    
    lcd.drawFilledRectangle(wgt.zone.x + myBatt.x, rectY, myBatt.w, pcntY, fill_color)
    lcd.drawLine(wgt.zone.x + myBatt.x, rectY, wgt.zone.x + myBatt.x + myBatt.w - 1, rectY, SOLID, wgt.cell_color)

    -- draw battery segments
    lcd.drawRectangle(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y + myBatt.cath_h, myBatt.w, myBatt.h - myBatt.cath_h, wgt.cell_color, 2)
end

--- Zone size: 70x39 top bar
function M.refreshZoneTiny(wgt, config)
    -- write text
    lcd.drawText(wgt.zone.x + wgt.zone.w - 25, wgt.zone.y + 5, M.formatPercentage(wgt.vPercent), RIGHT + SMLSIZE + wgt.text_color)
    lcd.drawText(wgt.zone.x + wgt.zone.w - 25, wgt.zone.y + 20, string.format("%.2fV", wgt.mainValue), RIGHT + SMLSIZE + wgt.text_color)

    -- draw battery
    local batt_color = wgt.text_color
    lcd.drawRectangle(wgt.zone.x + 50, wgt.zone.y + 9, 16, 25, batt_color, 2)
    lcd.drawFilledRectangle(wgt.zone.x + 50 + 4, wgt.zone.y + 7, 6, 3, batt_color)
    local rect_h = math.floor(25 * wgt.vPercent / 100)
    local fill_color = M.getBatteryFillColor(wgt, config)
    lcd.drawFilledRectangle(wgt.zone.x + 50, wgt.zone.y + 9 + 25 - rect_h, 16, rect_h, fill_color)
end

--- Zone size: 160x32 1/8th
function M.refreshZoneSmall(wgt, config)
    local myBatt = { ["x"] = 4, ["y"] = 4, ["w"] = wgt.zone.w - 8, ["h"] = wgt.zone.h - 8, ["segments_w"] = 25, ["cath_w"] = 6, ["cath_h"] = 20 }

    -- fill battery
    local fill_color = M.getBatteryFillColor(wgt, config)
    lcd.drawGauge(myBatt.x, myBatt.y, myBatt.w, myBatt.h, wgt.vPercent, 100, fill_color)

    -- draw battery
    lcd.drawRectangle(myBatt.x, myBatt.y, myBatt.w + 1, myBatt.h, wgt.text_color, 2)

    -- write text
    local volts = string.format("%s / %s", M.formatTotalVoltage(wgt.vTotalLive), M.formatCellVoltageString(wgt.vCellLive, wgt.cellCount, wgt.cell_detected))
    lcd.drawText(myBatt.x + 8, myBatt.y + 4, volts, BOLD + LEFT + wgt.text_color)

    local secondaryInfo = M.getSecondaryInfoText(wgt)
    if secondaryInfo then
        lcd.drawText(myBatt.x + 8, myBatt.y + myBatt.h / 2, secondaryInfo, BOLD + LEFT + wgt.text_color)
    end

    lcd.drawText(myBatt.x + myBatt.w - 4, myBatt.y + myBatt.h / 2, M.formatPercentage(wgt.vPercent), BOLD + VCENTER + RIGHT + MIDSIZE + wgt.text_color)

    -- Reserve label (bottom-right, small but legible) - move text up to avoid overlap
    local reserveVal
    if wgt.options then
        local rv = wgt.options[config.OPT_RESERVE]
        if rv ~= nil then reserveVal = math.max(0, math.min(50, rv)) end
    end
    if reserveVal == nil then reserveVal = (wgt.vReserve or 0) end
    local reserveTxt = string.format("Reserve %d%%", reserveVal)
    lcd.drawText(myBatt.x + myBatt.w - 2, myBatt.y + myBatt.h - 17, reserveTxt, RIGHT + SMLSIZE + wgt.text_color)
end

--- Zone size: 180x70 1/4th  (with sliders/trim)
--- Zone size: 225x98 1/4th  (no sliders/trim)
function M.refreshZoneMedium(wgt, config)
    local myBatt = { ["x"] = 0 +  wgt.border_l, ["y"] = 0, ["w"] = 50, ["h"] = wgt.zone.h - wgt.border_b, ["segments_w"] = 15, ["cath_w"] = 26, ["cath_h"] = 10, ["segments_h"] = 16 }

    -- draw values
    lcd.drawText(wgt.zone.x + myBatt.w + 10 +  wgt.border_l, wgt.zone.y, M.formatTotalVoltage(wgt.vTotalLive), DBLSIZE + wgt.text_color)
    lcd.drawText(wgt.zone.x + myBatt.w + 12 +  wgt.border_l, wgt.zone.y + 30, M.formatPercentage(wgt.vPercent), MIDSIZE + wgt.text_color)
    
    lcd.drawText(wgt.zone.x + wgt.zone.w - 5 - wgt.border_r, wgt.zone.y + wgt.zone.h - 38, M.formatCellVoltageString(wgt.vCellLive, wgt.cellCount, wgt.cell_detected), RIGHT + wgt.text_color)

    local secondaryInfo = M.getSecondaryInfoText(wgt)
    if secondaryInfo then
        lcd.drawText(wgt.zone.x + wgt.zone.w - 5 - wgt.border_r, wgt.zone.y + wgt.zone.h - 20, secondaryInfo, RIGHT + wgt.text_color)
    end

    -- Reserve label (bottom-right corner, small)
    local reserveVal
    if wgt.options then
        local rv = wgt.options[config.OPT_RESERVE]
        if rv ~= nil then reserveVal = math.max(0, math.min(50, rv)) end
    end
    if reserveVal == nil then reserveVal = (wgt.vReserve or 0) end
    local reserveTxt = string.format("Reserve %d%%", reserveVal)
    lcd.drawText(wgt.zone.x + wgt.zone.w - 5 - wgt.border_r, wgt.zone.y + wgt.zone.h - 17, reserveTxt, RIGHT + SMLSIZE + wgt.text_color)

    M.drawBattery(wgt, myBatt, config)
end

--- Zone size: 192x152 1/2
function M.refreshZoneLarge(wgt, config)
    local myBatt = { ["x"] = 0, ["y"] = 0, ["w"] = 76, ["h"] = wgt.zone.h, ["segments_h"] = 30, ["cath_w"] = 30, ["cath_h"] = 10 }

    lcd.drawText(wgt.zone.x + wgt.zone.w, wgt.zone.y + 10, M.formatTotalVoltage(wgt.vTotalLive), RIGHT + DBLSIZE + wgt.text_color)
    lcd.drawText(wgt.zone.x + wgt.zone.w, wgt.zone.y + 40, M.formatPercentage(wgt.vPercent), RIGHT + DBLSIZE + wgt.text_color)
    
    lcd.drawText(wgt.zone.x + wgt.zone.w, wgt.zone.y + wgt.zone.h - 38, M.formatCellVoltageString(wgt.vCellLive, wgt.cellCount, wgt.cell_detected), RIGHT + BOLD + wgt.text_color)

    local secondaryInfo = M.getSecondaryInfoText(wgt)
    if secondaryInfo then
        lcd.drawText(wgt.zone.x + wgt.zone.w, wgt.zone.y + wgt.zone.h - 20, secondaryInfo, RIGHT + BOLD + wgt.text_color)
    end

    M.drawBattery(wgt, myBatt, config)
end

--- Zone size: 390x172 1/1
--- Zone size: 460x252 1/1 (no sliders/trim/topbar)
function M.refreshZoneXLarge(wgt, config)
    local x = wgt.zone.x
    local w = wgt.zone.w
    local y = wgt.zone.y
    local h = wgt.zone.h

    local myBatt = { ["x"] = 10, ["y"] = 0, ["w"] = 80, ["h"] = h, ["segments_h"] = 30, ["cath_w"] = 30, ["cath_h"] = 10 }

    -- draw right text section
    lcd.drawText(x + 150, y + myBatt.y + 0, string.format("%.2f V", wgt.mainValue), XXLSIZE + wgt.text_color)
    lcd.drawText(x + 150, y + myBatt.y + 70, wgt.options.source_name, DBLSIZE + wgt.text_color)
    lcd.drawText(x + w, y + myBatt.y + 80, M.formatPercentage(wgt.vPercent), RIGHT + DBLSIZE + wgt.text_color)
    lcd.drawText(x + w, y + h - 60, string.format("%2.2fV    %dS", wgt.secondaryValue, wgt.cellCount), RIGHT + DBLSIZE + wgt.text_color)
    lcd.drawText(x + w, y + h - 30, string.format("min %2.2fV", wgt.vMin), RIGHT + DBLSIZE + wgt.text_color)
    M.drawBattery(wgt, myBatt, config)
end

--- Zone size: 460x252 - app mode (full screen)
function M.refreshAppMode(wgt, event, touchState, config)
    if (touchState and touchState.tapCount == 2) or (event and event == EVT_VIRTUAL_EXIT) then
        lcd.exitFullScreen()
    end

    local x = 0
    local y = 0
    local w = LCD_W
    local h = LCD_H - 20

    local myBatt = { ["x"] = 10, ["y"] = 10, ["w"] = 90, ["h"] = h, ["segments_h"] = 30, ["cath_w"] = 30, ["cath_h"] = 10 }

    -- draw right text section
    lcd.drawText(x + 180, y + 0, wgt.options.source_name, DBLSIZE + wgt.text_color)
    lcd.drawText(x + 180, y + 30, string.format("%.2f V", wgt.mainValue), XXLSIZE + wgt.text_color)
    lcd.drawText(x + 180, y + 90, M.formatPercentage(wgt.vPercent), XXLSIZE + wgt.text_color)

    lcd.drawText(x + w - 20, y + h - 90, string.format("%2.2fV", wgt.secondaryValue), RIGHT + DBLSIZE + wgt.text_color)
    lcd.drawText(x + w - 20, y + h - 60, string.format("%dS", wgt.cellCount), RIGHT + DBLSIZE + wgt.text_color)
    lcd.drawText(x + w - 20, y + h - 30, string.format("min %2.2fV", wgt.vMin), RIGHT + DBLSIZE + wgt.text_color)

    M.drawBattery(wgt, myBatt, config)
end

return M

