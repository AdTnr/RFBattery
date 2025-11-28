-- Voltage filtering functions for battery percentage calculation

local M = {}

-- Cache global functions for performance
local getTime = getTime
local math = math

-- Smoothen vPercent, sample every 1/10s, collect last N seconds
function M.getFilteredvPercent(wgt)
    local count = #wgt.vflt
    if count == 0 then
        return 0
    end

    -- Only average non-zero values (ignore preallocated zeros)
    local sum = 0
    local validCount = 0
    for i=1, count do
        if wgt.vflt[i] > 0 then
            sum = sum + wgt.vflt[i]
            validCount = validCount + 1
        end
    end
    
    -- If no valid samples yet, return 0
    if validCount == 0 then
        return 0
    end
    
    return math.ceil(sum / validCount)
end

-- Preallocate filter array to prevent dynamic growth and improve performance
function M.preallocateFilterArray(wgt, config)
    if wgt.vfltSamples > 0 and #wgt.vflt == 0 then
        -- Preallocate array to prevent resizing during operation
        -- Use nil instead of 0 to distinguish uninitialized from actual zero values
        for i = 1, wgt.vfltSamples do
            wgt.vflt[i] = nil
        end
    end
end

function M.updateFilteredvPercent(wgt, vPercent, config)
    -- Ensure vfltSamples is set to a valid value (prevent division by zero)
    if wgt.vfltSamples == 0 or wgt.vfltSamples == nil then
        wgt.vfltSamples = config.VFLT_SAMPLES_DEFAULT
        -- Preallocate after determining sample count
        M.preallocateFilterArray(wgt, config)
    end
    
    -- If filter is empty or has no valid samples yet, return current value immediately
    -- This prevents the "counting up from 0" issue when a new battery is inserted
    local hasValidSamples = false
    for i=1, #wgt.vflt do
        if wgt.vflt[i] ~= nil and wgt.vflt[i] > 0 then
            hasValidSamples = true
            break
        end
    end
    
    if vPercent > 0 and getTime() > wgt.vfltNextUpdate and wgt.vfltSamples > 0 then
        wgt.vflt[wgt.vflti + 1] = vPercent
        wgt.vflti = (wgt.vflti + 1) % wgt.vfltSamples
        wgt.vfltNextUpdate = getTime() + wgt.vfltInterval
    end

    -- If no valid samples yet, return current value immediately
    if not hasValidSamples and vPercent > 0 then
        return vPercent
    end

    return M.getFilteredvPercent(wgt)
end

return M

