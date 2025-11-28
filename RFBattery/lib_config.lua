-- Configuration constants and data tables for RFBattery widget

local M = {}

-- Widget name and paths
M.app_name = "RFBattery"
M.AUDIO_PATH = "/WIDGETS/RFBattery/audio/"

-- Battery warning thresholds (percentages)
M.singleStepThreshold = 10                              -- Below/at this %, use 1% steps; above it, round to 10%
M.battLowMargin = 5                                  -- Battery low margin (%) - used for voice alert suppression

-- Telemetry stabilization (consolidated delay for all telemetry/data stabilization)
-- This delay is used for: telemetry reconnection and cell detection
M.TELEMETRY_STABILIZATION_DELAY = 500                   -- Delay in 10ms units (500 = 5000ms / 5 seconds)

-- RSSI disconnection delay - wait before resetting widget when RSSI goes to zero
-- This prevents immediate reset during brief out-of-range scenarios
M.RSSI_DISCONNECT_DELAY = 200                          -- Delay in 10ms units (200 = 2000ms / 2 seconds)

-- Zero voltage detection delay - wait before resetting widget when voltage reads 0V
-- This prevents immediate reset during brief voltage drops
M.ZERO_VOLTAGE_DELAY = 200                             -- Delay in 10ms units (200 = 2000ms / 2 seconds)

-- Battery inserted low warning settings
M.batteryInsertedLowPercent = 98                       -- Percentage threshold for battery inserted low warning (high % + low voltage)
M.BATTERY_MIN_VOLTAGE = 3.0                            -- Minimum voltage threshold (volts) for battery connected low warning
M.LOW_BAT_INS_VOLTAGE = 4.08                           -- Low battery inserted voltage threshold (volts) - 4.0V = cell voltage below this triggers warning
M.BATTERY_CONNECTED_LOW_DELAY = 0                     -- Delay in 10ms units (10 = 100ms / 0.1 second) after conditions met before triggering warning
M.BAT_INSERTED_DETECT_WINDOW = 300                    -- Time window after stabilization to consider 'battery inserted low' (10ms units)

-- Cell detection and calculation
-- (cellFull removed; LOW_BAT_INS_VOLTAGE now governs inserted-low checks)

-- Voltage filter settings (for percentage calculation fallback when Bat% sensor unavailable)
M.VFLT_SAMPLES_DEFAULT = 150                           -- Default number of samples for voltage percentage filter
M.VFLT_INTERVAL_DEFAULT = 10                           -- Default interval (in 10ms units) between voltage filter samples

-- Global variable settings
M.GV_CEL = 3                                           -- Global variable index for cell count fallback

-- RotorFlight telemetry sensor names (hardcoded)
M.SENSOR_VOLT = "Vbat"                                 -- Voltage sensor name from RotorFlight telemetry
M.SENSOR_PCNT = "Bat%"                                 -- Battery percentage sensor name from RotorFlight telemetry
M.SENSOR_MAH = "Capa"                                  -- Capacity (mAh) sensor name from RotorFlight telemetry
M.SENSOR_CELLS = "Cel#"                                -- Cell count sensor name from RotorFlight telemetry
M.SENSOR_ARM = "ARM"                                   -- ARM telemetry sensor (2 = disarmed, silence warnings)

-- Widget option names (for UI settings)
M.OPT_RESERVE = "Reserve %"                            -- Option name for battery reserve percentage
M.OPT_COLOR_TOGGLE = "Text Color (0=White,1=Black)"     -- Toggle for text/border color

-- Widget display borders (pixels)
M.BORDER_LEFT = 5                                      -- Left border padding for battery display
M.BORDER_RIGHT = 10                                    -- Right border padding for battery display
M.BORDER_TOP = 0                                       -- Top border padding for battery display
M.BORDER_BOTTOM = 5                                   -- Bottom border padding for battery display

-- Widget options array
M.options = {
    { M.OPT_RESERVE             , VALUE, 30, 0, 50 },    -- reserve percentage (0..50)
    { M.OPT_COLOR_TOGGLE        , VALUE, 0, 0, 1 },      -- 0 = White, 1 = Black
}

-- Data gathered from commercial lipo sensors - voltage to percentage lookup table
M.lipoPercentListSplit = {
    { { 3.000,  0 }, { 3.093,  1 }, { 3.196,  2 }, { 3.301,  3 }, { 3.401,  4 }, { 3.477,  5 }, { 3.544,  6 }, { 3.601,  7 }, { 3.637,  8 }, { 3.664,  9 }, { 3.679, 10 }, { 3.683, 11 }, { 3.689, 12 }, { 3.692, 13 } },
    { { 3.705, 14 }, { 3.710, 15 }, { 3.713, 16 }, { 3.715, 17 }, { 3.720, 18 }, { 3.731, 19 }, { 3.735, 20 }, { 3.744, 21 }, { 3.753, 22 }, { 3.756, 23 }, { 3.758, 24 }, { 3.762, 25 }, { 3.767, 26 } },
    { { 3.774, 27 }, { 3.780, 28 }, { 3.783, 29 }, { 3.786, 30 }, { 3.789, 31 }, { 3.794, 32 }, { 3.797, 33 }, { 3.800, 34 }, { 3.802, 35 }, { 3.805, 36 }, { 3.808, 37 }, { 3.811, 38 }, { 3.815, 39 } },
    { { 3.818, 40 }, { 3.822, 41 }, { 3.825, 42 }, { 3.829, 43 }, { 3.833, 44 }, { 3.836, 45 }, { 3.840, 46 }, { 3.843, 47 }, { 3.847, 48 }, { 3.850, 49 }, { 3.854, 50 }, { 3.857, 51 }, { 3.860, 52 } },
    { { 3.863, 53 }, { 3.866, 54 }, { 3.870, 55 }, { 3.874, 56 }, { 3.879, 57 }, { 3.888, 58 }, { 3.893, 59 }, { 3.897, 60 }, { 3.902, 61 }, { 3.906, 62 }, { 3.911, 63 }, { 3.918, 64 } },
    { { 3.923, 65 }, { 3.928, 66 }, { 3.939, 67 }, { 3.943, 68 }, { 3.949, 69 }, { 3.955, 70 }, { 3.961, 71 }, { 3.968, 72 }, { 3.974, 73 }, { 3.981, 74 }, { 3.987, 75 }, { 3.994, 76 } },
    { { 4.001, 77 }, { 4.007, 78 }, { 4.014, 79 }, { 4.021, 80 }, { 4.029, 81 }, { 4.036, 82 }, { 4.044, 83 }, { 4.052, 84 }, { 4.062, 85 }, { 4.074, 86 }, { 4.085, 87 }, { 4.095, 88 } },
    { { 4.105, 89 }, { 4.111, 90 }, { 4.116, 91 }, { 4.120, 92 }, { 4.125, 93 }, { 4.129, 94 }, { 4.135, 95 }, { 4.145, 96 }, { 4.176, 97 }, { 4.179, 98 }, { 4.193, 99 }, { 4.200, 100 } },
}

return M

