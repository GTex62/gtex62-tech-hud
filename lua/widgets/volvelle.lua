--[[
  ${CONKY_SUITE_DIR}/lua/volvelle.lua
  Volvelle ring (celestial glyph ring) around the center clock.
]]

require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local read_file = util.read_file
local parse_vars_file = util.parse_vars_file

local function read_sky_vars(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then return out end
  for line in f:lines() do
    local k, v = line:match("^%s*([A-Za-z0-9_]+)%s*=%s*([%-0-9%.]+)%s*$")
    if k and v then
      out[k] = tonumber(v) -- last occurrence wins
    end
  end
  f:close()
  return out
end

local function owm_daily_cache_path()
  local vars_path = SUITE_DIR .. "/config/owm.vars"
  local v = parse_vars_file(vars_path)
  local cache_path = v.OWM_DAILY_CACHE
  if not cache_path or cache_path == "" then
    cache_path = CACHE_DIR .. "/owm_forecast.json"
  end
  return cache_path
end

local function read_json_num_first(json, key)
  if not json then return nil end
  local m = json:match([["]] .. key .. [["%s*:%s*(%d+)]])
  return m and tonumber(m) or nil
end

local function sun_theta_from_owm()
  local j = read_file(owm_daily_cache_path())
  local sr = read_json_num_first(j, "sunrise")
  local ss = read_json_num_first(j, "sunset")

  if not sr or not ss then
    j = read_file(CACHE_DIR .. "/owm_current.json")
    sr = read_json_num_first(j, "sunrise")
    ss = read_json_num_first(j, "sunset")
  end

  if not sr or not ss or ss <= sr then return nil end
  local now = os.time()
  local day_p = (now - sr) / (ss - sr)
  if day_p >= 0 and day_p <= 1 then
    return day_p * 180.0
  end

  -- Night: map sunset->next sunrise across the bottom half (180..360)
  local sr_next = sr + 86400
  local ss_prev = ss - 86400
  local night_p
  if now > ss then
    night_p = (now - ss) / (sr_next - ss)
  else
    night_p = (now - ss_prev) / (sr - ss_prev)
  end
  if night_p < 0 then night_p = 0 elseif night_p > 1 then night_p = 1 end
  return 180.0 + (night_p * 180.0)
end

local function theta_to_angle(theta_deg)
  if theta_deg == nil then return nil end
  local t = theta_deg % 360
  if t < 0 then t = t + 360 end
  return t
end

local function point_on_ring(cx, cy, r, theta_deg, gap_ang)
  local ang = theta_to_angle(theta_deg)
  if not ang then return nil end
  local a = ang * math.pi / 180
  -- allow glyphs to pass through gaps
  return cx + r * math.cos(a), cy - r * math.sin(a), a
end

local function draw_glyph(cr, x, y, glyph, font_face, font_size, col, alpha, rot)
  if not x or not y then return end
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)

  local ext = (cairo_text_extents_t and cairo_text_extents_t.create) and cairo_text_extents_t:create() or nil
  if ext then cairo_text_extents(cr, glyph, ext) end
  cairo_save(cr)
  cairo_translate(cr, x, y)
  if rot then cairo_rotate(cr, rot) end
  if ext then
    cairo_move_to(cr, -(ext.width / 2 + ext.x_bearing), ext.height / 2)
  else
    cairo_move_to(cr, 0, 0)
  end
  cairo_show_text(cr, glyph)
  cairo_restore(cr)
end

local function draw_circle(cr, x, y, radius, col, alpha)
  if not x or not y then return end
  set_rgba(cr, col, alpha)
  cairo_arc(cr, x, y, radius, 0, 2 * math.pi)
  cairo_fill(cr)
end

local function draw_volvelle_ring_impl()
  if conky_window == nil then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local t = get_theme()
  local v = (type(t.volvelle) == "table") and t.volvelle or {}

  local cx, cy = w / 2, h / 2
  local r_clock = math.min(w, h) * (tonumber(t.clock_r_factor) or 0.17)

  local ring_r = (type(v.r) == "number") and scale(v.r) or (r_clock + scale(v.r_offset or 85))
  local ring_w = scale(v.stroke or 6.0)
  local ring_col = v.color or { 0.20, 0.20, 0.20 }
  local ring_alpha = v.alpha or 0.35
  local ring_gap = scale(v.gap_px or 20)
  local pad_deg = tonumber(v.pad_deg) or 0

  local glyph_set = v.glyph_set or "astronomicon"
  local font_face = v.font
  if font_face == nil or font_face == "" or font_face == "auto" then
    if glyph_set == "unicode" then
      font_face = v.font_unicode or "Symbola"
    else
      font_face = v.font_astronomicon or "Astronomicon"
    end
  end
  local glyphs = (type(v.glyphs) == "table") and v.glyphs or {}
  local function glyph_opt(name, key, default)
    local gcfg = glyphs[name]
    if type(gcfg) == "table" and gcfg[key] ~= nil then return gcfg[key] end
    return default
  end

  local function rot_rad(name, default)
    local deg = glyph_opt(name, "rot_deg", default)
    if deg == nil then return 0 end
    return (tonumber(deg) or 0) * math.pi / 180
  end

  local glyph_size = scale(v.glyph_pt or 18)
  local glyph_col = v.glyph_color or { 0.20, 0.20, 0.20 }
  local glyph_alpha = v.glyph_alpha or 0.90
  local planet_render = v.planet_render or "glyphs"
  local planet_circles = (type(v.planet_circles) == "table") and v.planet_circles or {}
  local function gray(vv) return { vv, vv, vv } end
  local g = (t.palette and t.palette.gray) or {}
  local moon_col = g.g90 or gray(0.92)
  local planet_cols = {
    MERCURY = g.g70 or gray(0.70),
    VENUS   = g.g80 or gray(0.80),
    MARS    = g.g75 or gray(0.75),
    JUPITER = g.g85 or gray(0.85),
    SATURN  = g.g78 or gray(0.78),
  }

  local sun_size = scale(glyph_opt("SUN", "pt", v.sun_pt or (v.glyph_pt or 18)))
  local sun_col = glyph_opt("SUN", "color", v.sun_color or { 1.00, 0.62, 0.00 })
  local sun_alpha = glyph_opt("SUN", "alpha", v.sun_alpha or 0.95)
  local sun_dr = scale(glyph_opt("SUN", "dr", v.sun_dr or 0))

  local moon_size = scale(glyph_opt("MOON", "pt", v.moon_pt or (v.glyph_pt or 18)))
  local moon_col_override = glyph_opt("MOON", "color", nil)
  if moon_col_override ~= nil then moon_col = moon_col_override end
  local moon_alpha = glyph_opt("MOON", "alpha", v.moon_alpha or glyph_alpha)
  local moon_dr = scale(glyph_opt("MOON", "dr", v.moon_dr or 0))

  local function planet_cfg(name, def_col, def_dr)
    local col = glyph_opt(name, "color", def_col)
    local alpha = glyph_opt(name, "alpha", glyph_alpha)
    local pt = glyph_opt(name, "pt", v.planet_pt or (v.glyph_pt or 18))
    local dr = scale(glyph_opt(name, "dr", def_dr or 0))
    return col, alpha, pt, dr
  end

  local mercury_col, mercury_alpha, mercury_pt, mercury_dr = planet_cfg("MERCURY", planet_cols.MERCURY, -6)
  local venus_col, venus_alpha, venus_pt, venus_dr = planet_cfg("VENUS", planet_cols.VENUS, 0)
  local mars_col, mars_alpha, mars_pt, mars_dr = planet_cfg("MARS", planet_cols.MARS, 6)
  local jupiter_col, jupiter_alpha, jupiter_pt, jupiter_dr = planet_cfg("JUPITER", planet_cols.JUPITER, 0)
  local saturn_col, saturn_alpha, saturn_pt, saturn_dr = planet_cfg("SATURN", planet_cols.SATURN, 0)

  -- Ring (two segments, gaps at 3 and 9 o'clock)
  set_rgba(cr, ring_col, ring_alpha)
  cairo_set_line_width(cr, ring_w)
  local gap_ang = (ring_r > 0) and (ring_gap / ring_r) or 0
  local gap_deg = (gap_ang * 180 / math.pi) / 2
  local arc1_min = gap_deg
  local arc1_max = 180 - gap_deg
  local arc2_min = 180 + gap_deg
  local arc2_max = 360 - gap_deg
  local a1 = 0 + (gap_ang / 2)
  local a2 = math.pi - (gap_ang / 2)
  local a3 = math.pi + (gap_ang / 2)
  local a4 = (2 * math.pi) - (gap_ang / 2)
  cairo_arc(cr, cx, cy, ring_r, a1, a2)
  cairo_stroke(cr)
  cairo_arc(cr, cx, cy, ring_r, a3, a4)
  cairo_stroke(cr)

  -- Sky vars (planets/moon)
  local sky = read_sky_vars(CACHE_DIR .. "/sky.vars")

  local debug_mode = v.debug_mode == true
  local debug_theta = v.debug_theta
  local function pick_theta(key, fallback)
    if not debug_mode then return fallback end
    if type(debug_theta) == "number" then return debug_theta end
    if type(debug_theta) == "table" then
      local val = debug_theta[key]
      if val == nil then val = debug_theta.ALL end
      if val ~= nil then
        local num = tonumber(val)
        if num ~= nil then return num end
      end
    end
    return fallback
  end

  local function moon_theta_from_rise_set()
    local fallback = pick_theta("MOON", sky.MOON_THETA)
    if debug_mode then return fallback end
    local rise_ts = sky.MOON_RISE_TS
    local set_ts = sky.MOON_SET_TS
    if not (rise_ts and set_ts) then return fallback end

    local now = os.time()
    if set_ts < rise_ts then
      -- Handle wrap when next_set occurs before next_rise (crosses midnight)
      local rise_prev = rise_ts - 86400
      local set_next = set_ts + 86400
      if now >= rise_prev and now <= set_ts then
        local p = (now - rise_prev) / math.max(1, set_ts - rise_prev)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return p * 180.0
      elseif now >= set_ts and now <= rise_ts then
        local p = (now - set_ts) / math.max(1, rise_ts - set_ts)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return 180.0 + (p * 180.0)
      elseif now >= rise_ts and now <= set_next then
        local p = (now - rise_ts) / math.max(1, set_next - rise_ts)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return p * 180.0
      end
    else
      if now >= rise_ts and now <= set_ts then
        -- Moon above horizon: east (0°) → west (180°), CCW
        local p = (now - rise_ts) / math.max(1, set_ts - rise_ts)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return p * 180.0
      end

      -- Moon below horizon: west (180°) → east (360°), CCW
      if now < rise_ts then
        local prev_set = sky.MOON_SET_PREV_TS or (set_ts - 86400)
        if prev_set and rise_ts > prev_set then
          local p = (now - prev_set) / math.max(1, rise_ts - prev_set)
          if p < 0 then p = 0 elseif p > 1 then p = 1 end
          return 180.0 + (p * 180.0)
        end
      elseif now > set_ts then
        local next_rise = rise_ts + 86400
        local p = (now - set_ts) / math.max(1, next_rise - set_ts)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return 180.0 + (p * 180.0)
      end
    end

    return fallback
  end

  local glyph_map = {
    astronomicon = {
      SUN = "Q",
      MOON = "R",
      MERCURY = "S",
      VENUS = "T",
      MARS = "U",
      JUPITER = "V",
      SATURN = "W",
    },
    unicode = {
      SUN = "☉",
      MOON = "☽",
      MERCURY = "☿",
      VENUS = "♀",
      MARS = "♂",
      JUPITER = "♃",
      SATURN = "♄",
    },
  }
  local gmap = glyph_map[(glyph_set == "unicode") and "unicode" or "astronomicon"]

  local sun_theta = pick_theta("SUN", sky.SUN_THETA or sun_theta_from_owm())
  local bodies = {
    { key = "SUN", glyph = gmap.SUN, theta = sun_theta, dr = sun_dr, rot = rot_rad("SUN", 0), pt = sun_size, col = sun_col, alpha = sun_alpha },
    { key = "MOON", glyph = gmap.MOON, theta = moon_theta_from_rise_set(), dr = moon_dr, rot = rot_rad("MOON", 180), pt = moon_size, col = moon_col, alpha = moon_alpha },
    { key = "MERCURY", glyph = gmap.MERCURY, theta = pick_theta("MERCURY", sky.MERCURY_THETA), dr = mercury_dr, rot = rot_rad("MERCURY", 180), pt = mercury_pt, col = mercury_col, alpha = mercury_alpha },
    { key = "VENUS", glyph = gmap.VENUS, theta = pick_theta("VENUS", sky.VENUS_THETA), dr = venus_dr, rot = rot_rad("VENUS", 180), pt = venus_pt, col = venus_col, alpha = venus_alpha },
    { key = "MARS", glyph = gmap.MARS, theta = pick_theta("MARS", sky.MARS_THETA), dr = mars_dr, rot = rot_rad("MARS", 180), pt = mars_pt, col = mars_col, alpha = mars_alpha },
    { key = "JUPITER", glyph = gmap.JUPITER, theta = pick_theta("JUPITER", sky.JUPITER_THETA), dr = jupiter_dr, rot = rot_rad("JUPITER", 180), pt = jupiter_pt, col = jupiter_col, alpha = jupiter_alpha },
    { key = "SATURN", glyph = gmap.SATURN, theta = pick_theta("SATURN", sky.SATURN_THETA), dr = saturn_dr, rot = rot_rad("SATURN", 270), pt = saturn_pt, col = saturn_col, alpha = saturn_alpha },
  }

  if pad_deg > 0 then
    local function norm_theta(theta)
      local t = theta % 360
      if t < 0 then t = t + 360 end
      return t
    end
    local function clamp(vv, lo, hi)
      if vv < lo then return lo end
      if vv > hi then return hi end
      return vv
    end
    local list_top = {}
    local list_bot = {}
    for _, b in ipairs(bodies) do
      if b.theta ~= nil then
        local t = norm_theta(b.theta)
        if t >= arc1_min and t <= arc1_max then
          b.theta_adj = clamp(t, arc1_min, arc1_max)
          table.insert(list_top, b)
        elseif t >= arc2_min and t <= arc2_max then
          b.theta_adj = clamp(t, arc2_min, arc2_max)
          table.insert(list_bot, b)
        end
      end
    end
    local function apply_padding(list, min_deg, max_deg)
      table.sort(list, function(a, b) return a.theta_adj < b.theta_adj end)
      local prev = nil
      for _, b in ipairs(list) do
        if prev then
          if (b.theta_adj - prev.theta_adj) < pad_deg then
            b.theta_adj = clamp(prev.theta_adj + pad_deg, min_deg, max_deg)
          end
        end
        prev = b
      end
    end
    apply_padding(list_top, arc1_min, arc1_max)
    apply_padding(list_bot, arc2_min, arc2_max)
  end

  for _, b in ipairs(bodies) do
    local theta = b.theta_adj or b.theta
    local x, y, a = point_on_ring(cx, cy, ring_r + scale(b.dr or 0), theta, gap_ang)
    if x and y then
      local rot = (math.pi / 2) - a + (b.rot or 0)
      local is_planet = (b.key ~= "SUN" and b.key ~= "MOON")
      if planet_render == "circles" and is_planet then
        local pc = planet_circles[b.key] or {}
        local radius = scale(tonumber(pc.r) or ((b.pt or glyph_size) / 2))
        local col = pc.color or b.col or glyph_col
        local alpha = tonumber(pc.alpha) or (type(col) == "table" and col[4]) or b.alpha or glyph_alpha
        draw_circle(cr, x, y, radius, col, alpha)
      else
        draw_glyph(cr, x, y, b.glyph, font_face, b.pt or glyph_size, b.col or glyph_col, b.alpha or glyph_alpha, rot)
      end
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_draw_volvelle_ring()
  if conky_window == nil then return end
  local ok, err = pcall(draw_volvelle_ring_impl)
  if not ok then
    print("volvelle error: " .. tostring(err))
  end
end
