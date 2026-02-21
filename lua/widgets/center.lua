--[[
  ${CONKY_SUITE_DIR}/lua/widgets/center.lua
  Center widget loader: core → volvelle → calendar → marquee → owm → weather
]]

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")

local function safe_dofile(path, label)
  local ok, err = pcall(dofile, path)
  if not ok then
    print((label or "loader") .. " load error: " .. tostring(err))
  end
end

safe_dofile(SUITE_DIR .. "/lua/widgets/core.lua", "core")
safe_dofile(SUITE_DIR .. "/lua/widgets/volvelle.lua", "volvelle")
safe_dofile(SUITE_DIR .. "/lua/widgets/calendar.lua", "calendar")
safe_dofile(SUITE_DIR .. "/lua/widgets/marquee_calendar.lua", "marquee")
safe_dofile(SUITE_DIR .. "/lua/widgets/owm.lua", "owm")
safe_dofile(SUITE_DIR .. "/lua/widgets/weather.lua", "weather")
safe_dofile(SUITE_DIR .. "/lua/widgets/sitrep.lua", "sitrep")
safe_dofile(SUITE_DIR .. "/lua/widgets/station_model.lua", "station_model")
safe_dofile(SUITE_DIR .. "/lua/widgets/baro_gauge.lua", "baro_gauge")
