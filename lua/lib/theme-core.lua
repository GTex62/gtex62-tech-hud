--[[
  ${CONKY_SUITE_DIR}/lua/lib/theme-core.lua
  Shared palette + fonts + font detection helpers
]]

----------------------------------------------------------------
-- Helpers for Font Detection
----------------------------------------------------------------
local HOME = os.getenv("HOME") or ""
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local FONT_CACHE = CACHE_DIR .. "/font_cache.txt"
local font_cache = nil

local function load_font_cache()
  if font_cache then return font_cache end
  font_cache = {}
  local f = io.open(FONT_CACHE, "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^(.-)=(%d)$")
      if k then
        font_cache[k] = (v == "1")
      end
    end
    f:close()
  end
  return font_cache
end

local function save_font_cache()
  if not font_cache then return end
  os.execute("mkdir -p " .. CACHE_DIR)
  local f = io.open(FONT_CACHE, "w")
  if not f then return end
  for k, v in pairs(font_cache) do
    f:write(k, "=", v and "1" or "0", "\n")
  end
  f:close()
end

-- Font detection helpers. Checks installed families, falls back to full list when needed.
local function font_installed(family)
  -- fc-list prints one family per line when using : family
  -- grep case-insensitive for the family name.
  local name = family:match("^([^:]+)") or family
  local cache = load_font_cache()
  if cache[name] ~= nil then
    return cache[name]
  end
  local safe = name:gsub("'", "'\\''") -- minimal shell-escape for single quotes
  local cmd_family = "sh -lc \"fc-list : family | grep -qi '" .. safe .. "'\""
  local ok = os.execute(cmd_family)
  if ok == true or ok == 0 then
    cache[name] = true
    save_font_cache()
    return true
  end
  local cmd_any = "sh -lc \"fc-list | grep -qi '" .. safe .. "'\""
  ok = os.execute(cmd_any)
  local found = (ok == true or ok == 0)
  cache[name] = found
  save_font_cache()
  return found
end

local function pick_font(preferred_families, fallback_family)
  for _, fam in ipairs(preferred_families) do
    if font_installed(fam) then
      return fam
    end
  end
  return fallback_family
end

local PRO_SQUARE_EXT = { "Eurostile LT Std Ext Two" }
local PRO_SQUARE_STD = { "Eurostile LT Std" }
local PRO_CONDENSED = { "Berthold City Light", "Berthold City" }

----------------------------------------------------------------
-- Colors
----------------------------------------------------------------
local palette = {
  black = { 0.00, 0.00, 0.00 },
  white = { 1.00, 1.00, 1.00 },

  gray = {
    g10 = { 0.10, 0.10, 0.10 },
    g18 = { 0.18, 0.18, 0.18 },
    g20 = { 0.20, 0.20, 0.20 },
    g21 = { 0.21, 0.21, 0.21 },
    g22 = { 0.22, 0.22, 0.22 },
    g30 = { 0.30, 0.30, 0.30 },
    g40 = { 0.40, 0.40, 0.40 },
    g50 = { 0.50, 0.50, 0.50 },
    g60 = { 0.60, 0.60, 0.60 },
    g65 = { 0.65, 0.65, 0.65 },
    g70 = { 0.70, 0.70, 0.70 },
    g75 = { 0.75, 0.75, 0.75 },
    g78 = { 0.78, 0.78, 0.78 },
    g80 = { 0.80, 0.80, 0.80 },
    g85 = { 0.85, 0.85, 0.85 },
    g90 = { 0.90, 0.90, 0.90 },
  },

  accent = {
    orange = { 1.00, 0.62, 0.00 },
    maroon = { 0.40, 0.08, 0.12 },
  },

  planet = {
    venus   = { 1.00, 0.95, 0.70, 0.60 },
    mars    = { 1.00, 0.62, 0.00, 0.40 },
    jupiter = { 0.90, 0.82, 0.65, 0.50 },
    saturn  = { 0.85, 0.75, 0.50, 0.40 },
    mercury = { 0.78, 0.80, 0.86, 0.80 },
  },

  forecast = {
    date    = { 0.85, 0.85, 0.85, 1.0 },
    temp_hi = { 1.00, 1.00, 1.00, 1.0 },
    temp_lo = { 0.70, 0.70, 0.70, 1.0 },
  },

  pfsense = {
    bg      = { 0.06, 0.06, 0.08, 1.0 },
    text    = { 0.90, 0.92, 0.96, 1.0 },
    accent  = { 1.00, 0.00, 0.00, 1.0 },
    good    = { 0.20, 0.80, 0.40, 1.0 },
    warn    = { 1.00, 0.70, 0.20, 1.0 },
    bad     = { 0.95, 0.30, 0.25, 1.0 },
    arc_in  = { 0.35, 0.75, 1.00, 1.0 },
    arc_out = { 1.00, 0.55, 0.25, 1.0 },
  },
}

----------------------------------------------------------------
-- Fonts
----------------------------------------------------------------
local fonts = {
  title            = pick_font(PRO_SQUARE_EXT, "Orbitron Black"),
  title_b          = pick_font(PRO_SQUARE_EXT, "Roboto Condensed Black"),
  label            = pick_font(PRO_CONDENSED, "Rajdhani"),
  value            = pick_font(PRO_SQUARE_EXT, "Exo 2"),
  value_b          = pick_font(PRO_CONDENSED, "Exo 2"),
  value_c          = pick_font(PRO_SQUARE_STD, "Exo 2"),
  value_mono       = pick_font({ "Nimbus Mono PS" }, "Nimbus Mono PS"),
  subtle           = pick_font(PRO_CONDENSED, "Exo 2 Light"),
  accent           = pick_font(PRO_SQUARE_EXT, "Orbitron SemiBold"),
  accent_bold      = pick_font(PRO_SQUARE_EXT, "Orbitron Bold"),
  accent_black     = pick_font(PRO_SQUARE_EXT, "Orbitron Black"),
  accent_extrabold = pick_font(PRO_SQUARE_EXT, "Orbitron ExtraBold"),
  mono             = pick_font({ "Nimbus Mono PS" }, "Nimbus Mono PS"),
  regular          = pick_font(PRO_SQUARE_STD, "Exo 2"),
}

----------------------------------------------------------------
-- Font Metric Shims (fallback alignment)
----------------------------------------------------------------
-- Use these profiles to nudge/scale text when fallback fonts are used.
-- y_offset is in pixels at scale=1.0. size_scale is a multiplier.
-- Start with 0/1.0 and adjust per font.
local font_profiles = {
  ["Rajdhani Medium"]        = { y_offset = 0, size_scale = 1.10 },
  ["Roboto Condensed Black"] = { y_offset = 0, size_scale = 1.10 },
  ["Rajdhani"]               = { y_offset = 0, size_scale = 1.10 },
  ["Exo 2"]                  = { y_offset = 0, size_scale = 1.10 },
  ["Exo 2 Light"]            = { y_offset = 0, size_scale = 1.10 },
  ["Orbitron SemiBold"]      = { y_offset = 0, size_scale = 1.10 },
  ["Orbitron Bold"]          = { y_offset = 0, size_scale = 1.10 },
  ["Orbitron Black"]         = { y_offset = 0, size_scale = 1.10 },
  ["Orbitron ExtraBold"]     = { y_offset = 0, size_scale = 1.10 },
}

return {
  palette = palette,
  fonts = fonts,
  font_profiles = font_profiles,
  pick_font = pick_font,
}
