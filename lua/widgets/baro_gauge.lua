--[[
  ${CONKY_SUITE_DIR}/lua/widgets/baro_gauge.lua
  Barometer gauge widget (circles only).
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

local SEASON_CACHE = { ts = 0, label = nil }

local function seasonal_cache_path()
  local vars_path = SUITE_DIR .. "/config/owm.vars"
  local v = parse_vars_file(vars_path)
  local cache = v.SEASONAL_CACHE
  if not cache or cache == "" then
    cache = CACHE_DIR .. "/seasonal.vars"
  end
  return cache
end

local function read_seasonal_vars()
  local out = {}
  local s = read_file(seasonal_cache_path())
  if not s then return out end
  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local k, v = line:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$")
      if k and v then out[k] = v end
    end
  end
  return out
end

local function day_of_year_for_date(ymd, year)
  if not ymd then return nil end
  local y, m, d = ymd:match("^(%d+)%-(%d+)%-(%d+)$")
  if not y then return nil end
  local y_num = tonumber(y)
  local m_num = tonumber(m)
  local d_num = tonumber(d)
  if not y_num or not m_num or not d_num then return nil end
  y_num = math.floor(y_num)
  m_num = math.floor(m_num)
  d_num = math.floor(d_num)
  if year and y_num ~= year then return nil end
  local t0 = os.time({ year = y_num, month = 1, day = 1, hour = 0 })
  local t = os.time({ year = y_num, month = m_num, day = d_num, hour = 0 })
  return math.floor((t - t0) / 86400) + 1
end

local function current_season_label()
  local now = os.time()
  if SEASON_CACHE.label and (now - SEASON_CACHE.ts) < 900 then
    return SEASON_CACHE.label
  end

  local now_t = os.date("*t", now)
  local year = now_t.year
  local year_start = os.time({ year = year, month = 1, day = 1, hour = 0 })
  local today_doy = math.floor((now - year_start) / 86400) + 1
  local seasonal = read_seasonal_vars()
  local spring_doy = day_of_year_for_date(seasonal.SPRING_EQ_DATE, year)
  local summer_doy = day_of_year_for_date(seasonal.SUMMER_SOL_DATE, year)
  local autumn_doy = day_of_year_for_date(seasonal.AUTUMN_EQ_DATE, year)
  local winter_doy = day_of_year_for_date(seasonal.WINTER_SOL_DATE, year)

  if not spring_doy then spring_doy = day_of_year_for_date(string.format("%d-03-20", year), year) end
  if not summer_doy then summer_doy = day_of_year_for_date(string.format("%d-06-21", year), year) end
  if not autumn_doy then autumn_doy = day_of_year_for_date(string.format("%d-09-22", year), year) end
  if not winter_doy then winter_doy = day_of_year_for_date(string.format("%d-12-21", year), year) end

  local label = "WINTER"
  if winter_doy and spring_doy and summer_doy and autumn_doy then
    if today_doy >= winter_doy or today_doy < spring_doy then
      label = "WINTER"
    elseif today_doy >= spring_doy and today_doy < summer_doy then
      label = "SPRING"
    elseif today_doy >= summer_doy and today_doy < autumn_doy then
      label = "SUMMER"
    else
      label = "AUTUMN"
    end
  end

  SEASON_CACHE.label = label
  SEASON_CACHE.ts = now
  return label
end

local function blend_color(base, tint, amt)
  if type(base) ~= "table" or type(tint) ~= "table" then return base end
  return {
    base[1] + (tint[1] - base[1]) * amt,
    base[2] + (tint[2] - base[2]) * amt,
    base[3] + (tint[3] - base[3]) * amt,
  }
end

local function clamp(v, lo, hi)
  if v == nil then return nil end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function normalize_metar(s)
  if not s then return "" end
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function extract_ob_line(raw)
  if not raw or raw == "" then return "" end
  for line in raw:gmatch("[^\r\n]+") do
    local ob = line:match("^ob:%s*(.+)$")
    if ob and ob ~= "" then
      return normalize_metar(ob)
    end
  end
  return ""
end

local function metar_cache_path(t)
  local sm = t.station_model or {}
  local station = sm.station or "KMEM"
  local cache_path = sm.cache_path
  if cache_path == nil or cache_path == "" then
    cache_path = CACHE_DIR .. "/metar_" .. station .. "_raw.txt"
  elseif cache_path:find("%%s") then
    cache_path = string.format(cache_path, station)
  end
  return cache_path
end

local function read_cached_metar(t)
  local raw = read_file(metar_cache_path(t))
  if not raw then return "" end
  local ob = extract_ob_line(raw)
  if ob ~= "" then return ob end
  return normalize_metar(raw)
end

local function parse_altimeter(metar)
  if not metar or metar == "" then return nil, nil end
  local inhg
  local hpa
  local slp_code
  for tok in metar:gmatch("%S+") do
    local a = tok:match("^A(%d%d%d%d)$")
    if a then inhg = tonumber(a) / 100.0 end
    local q = tok:match("^Q(%d%d%d%d)$")
    if q then hpa = tonumber(q) end
    local slp = tok:match("^SLP(%d%d%d)$")
    if slp then slp_code = slp end
  end
  local slp_hpa
  if slp_code then
    local code = tonumber(slp_code)
    if code then
      if code < 500 then
        slp_hpa = 1000 + (code / 10.0)
      else
        slp_hpa = 900 + (code / 10.0)
      end
    end
  end
  if inhg and not hpa then
    hpa = inhg * 33.8639
  elseif hpa and not inhg then
    inhg = hpa / 33.8639
  end
  return inhg, hpa, slp_hpa
end

local function draw_text_center_centered(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  local cx = x - (ext.width / 2 + ext.x_bearing)
  local cy = y - (ext.height / 2 + ext.y_bearing)
  cairo_move_to(cr, cx, cy)
  cairo_show_text(cr, txt)
end

local function draw_baro_gauge_impl()
  if conky_window == nil then return end

  local t = get_theme()
  local bg = t.baro_gauge or {}
  if bg.enabled == false then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local base_cx = (w / 2) + scale(tonumber(bg.center_x_offset) or 0)
  local base_cy = (h / 2) + scale(tonumber(bg.center_y_offset) or 0)
  local circle = bg.circle or {}
  local circle_outer = bg.circle_outer or {}
  local center_x = base_cx
  local center_y = base_cy + scale(tonumber(circle.offset_y) or 0)
  local circle_radius = scale(tonumber(circle.radius) or 120)
  local circle_stroke = scale(tonumber(circle.stroke_width) or 3.0)
  local sm = t.station_model or {}
  local txt = bg.text or {}
  local metar = read_cached_metar(t)
  local inhg, hpa, slp_hpa = parse_altimeter(metar)
  local hpa_val = slp_hpa or hpa
  local inhg_source = tostring(txt.inhg_source or "slp"):lower()
  local inhg_val
  if inhg_source == "altimeter" or inhg_source == "a" then
    inhg_val = inhg or (hpa and (hpa / 33.8639)) or nil
  else
    inhg_val = (hpa_val and (hpa_val / 33.8639)) or inhg
  end
  local outer_offset = scale(tonumber(circle_outer.radius_offset) or 4)
  local outer_radius = scale(tonumber(circle_outer.radius) or (circle_radius + outer_offset))

  if circle.enabled ~= false then
    local fill_col = circle.fill_color or { 0.30, 0.30, 0.30 }
    if circle.season_tint_enable == true then
      local season_tints = {
        WINTER = { 0.20, 0.30, 0.45 }, -- blue
        SPRING = { 0.85, 0.80, 0.40 }, -- orange/yellow
        SUMMER = { 0.30, 0.55, 0.30 }, -- green
        AUTUMN = { 0.75, 0.35, 0.25 }, -- orange/red
      }
      local season = current_season_label()
      local tint = season_tints[season]
      local amt = tonumber(circle.season_tint_amount) or 0.06
      if tint and type(fill_col) == "table" then
        fill_col = blend_color(fill_col, tint, amt)
      end
    end
    local fill_alpha = tonumber(circle.fill_alpha) or 0.65
    local stroke_col = circle.stroke_color or { 0.40, 0.08, 0.12 }
    local stroke_alpha = tonumber(circle.stroke_alpha) or 0.70

    if fill_alpha > 0 then
      set_rgba(cr, fill_col, fill_alpha)
      cairo_arc(cr, center_x, center_y, circle_radius, 0, 2 * math.pi)
      cairo_fill(cr)
    end
    if circle_stroke > 0 and stroke_alpha > 0 then
      set_rgba(cr, stroke_col, stroke_alpha)
      cairo_set_line_width(cr, circle_stroke)
      cairo_arc(cr, center_x, center_y, circle_radius, 0, 2 * math.pi)
      cairo_stroke(cr)
    end

    if circle_outer.enabled ~= false then
      local outer_stroke = scale(tonumber(circle_outer.stroke_width) or 4.0)
      local outer_col = circle_outer.stroke_color or { 1.00, 1.00, 1.00 }
      local outer_alpha = tonumber(circle_outer.stroke_alpha) or 0.95
      if outer_stroke > 0 and outer_alpha > 0 then
        set_rgba(cr, outer_col, outer_alpha)
        cairo_set_line_width(cr, outer_stroke)
        cairo_arc(cr, center_x, center_y, outer_radius, 0, 2 * math.pi)
        cairo_stroke(cr)
      end
    end
  end

  do
    local arc = bg.arc or {}
    local ticks = bg.ticks or {}
    local range = bg.range or {}
    local use_inhg_range = range.use_inhg_range == true
    local hpa_min = tonumber(range.hpa_min)
    local hpa_max = tonumber(range.hpa_max)
    local hpa_std = tonumber(range.hpa_std)
    local inhg_min = tonumber(range.inhg_min)
    local inhg_max = tonumber(range.inhg_max)
    local inhg_std = tonumber(range.inhg_std)

    if use_inhg_range and inhg_min and inhg_max then
      hpa_min = inhg_min * 33.8639
      hpa_max = inhg_max * 33.8639
    end

    hpa_min = hpa_min or 870.0
    hpa_max = hpa_max or 1084.8
    hpa_std = hpa_std or 1013.2
    inhg_min = inhg_min or (hpa_min / 33.8639)
    inhg_max = inhg_max or (hpa_max / 33.8639)
    inhg_std = inhg_std or (hpa_std / 33.8639)

    local arc_inset = scale(tonumber(arc.radius_inset) or 6)
    local arc_radius = outer_radius - arc_inset
    local arc_width = scale(tonumber(arc.stroke_width) or 6.0)
    local left_col = arc.color_left or { 1.00, 1.00, 1.00 }
    local right_col = arc.color_right or { 1.00, 1.00, 1.00 }
    local left_alpha = tonumber(arc.alpha_left) or 0.90
    local right_alpha = tonumber(arc.alpha_right) or 0.90

    local start_ang = math.pi / 2
    if arc.enabled ~= false then
      if inhg_val and inhg_max > inhg_min then
        local left_frac = clamp((inhg_val - inhg_min) / (inhg_max - inhg_min), 0, 1)
        set_rgba(cr, left_col, left_alpha)
        cairo_set_line_width(cr, arc_width)
        cairo_arc(cr, center_x, center_y, arc_radius, start_ang, start_ang + (left_frac * math.pi))
        cairo_stroke(cr)
      end
      if hpa_val and hpa_max > hpa_min then
        local right_frac = clamp((hpa_val - hpa_min) / (hpa_max - hpa_min), 0, 1)
        set_rgba(cr, right_col, right_alpha)
        cairo_set_line_width(cr, arc_width)
        cairo_arc_negative(cr, center_x, center_y, arc_radius, start_ang, start_ang - (right_frac * math.pi))
        cairo_stroke(cr)
      end
    end

    if ticks.enabled ~= false then
      local tick_len = scale(tonumber(ticks.length) or 10)
      local tick_width = scale(tonumber(ticks.width) or 3.0)
      local tick_alpha = tonumber(ticks.alpha) or 0.95
      local col_low = ticks.color_low or { 1.00, 1.00, 1.00 }
      local col_std = ticks.color_std or { 0.40, 0.08, 0.12 }
      local col_high = ticks.color_high or { 1.00, 1.00, 1.00 }

      local function draw_tick(angle, col)
        local x0 = center_x + arc_radius * math.cos(angle)
        local y0 = center_y + arc_radius * math.sin(angle)
        local x1 = center_x + (arc_radius - tick_len) * math.cos(angle)
        local y1 = center_y + (arc_radius - tick_len) * math.sin(angle)
        set_rgba(cr, col, tick_alpha)
        cairo_set_line_width(cr, tick_width)
        cairo_move_to(cr, x0, y0)
        cairo_line_to(cr, x1, y1)
        cairo_stroke(cr)
      end

      if inhg_max > inhg_min then
        local left_std = clamp((inhg_std - inhg_min) / (inhg_max - inhg_min), 0, 1)
        draw_tick(start_ang, col_low)
        draw_tick(start_ang + (left_std * math.pi), col_std)
        draw_tick(start_ang + math.pi, col_high)
      end
      if hpa_max > hpa_min then
        local right_std = clamp((hpa_std - hpa_min) / (hpa_max - hpa_min), 0, 1)
        draw_tick(start_ang, col_low)
        draw_tick(start_ang - (right_std * math.pi), col_std)
        draw_tick(start_ang - math.pi, col_high)
      end
    end

    do
      local record_labels = bg.record_labels or {}
      local label_font = sm.font_numbers
      if label_font == nil or label_font == "" or label_font == "auto" then
        label_font = sm.font_value or (t.fonts and t.fonts.value) or "Exo 2"
      end
      local label_size = scale(15)
      local label_col = txt.color or sm.color_text or { 0.90, 0.90, 0.90 }
      local label_alpha = tonumber(txt.alpha) or tonumber(sm.alpha_text) or 0.85
      local tick_len = scale(tonumber(ticks.length) or 10)
      local label_pad = scale(4)
      local label_radius = arc_radius - tick_len - label_pad
      local top_angle = start_ang + math.pi
      local bottom_angle = start_ang
      local hi_y_offset = scale(tonumber(record_labels.hi_y_offset) or 0)
      local lo_y_offset = scale(tonumber(record_labels.lo_y_offset) or 0)

      local function format_extreme(v)
        if v == nil then return "/" end
        local rounded = math.floor(v + 0.5)
        if math.abs(v - rounded) < 0.01 then
          return string.format("%d", rounded)
        end
        return string.format("%.1f", v)
      end

      local hi_txt = format_extreme(hpa_max)
      local lo_txt = format_extreme(hpa_min)
      local hi_x = center_x + label_radius * math.cos(top_angle)
      local hi_y = center_y + label_radius * math.sin(top_angle) + hi_y_offset
      local lo_x = center_x + label_radius * math.cos(bottom_angle)
      local lo_y = center_y + label_radius * math.sin(bottom_angle) + lo_y_offset

      draw_text_center_centered(cr, hi_x, hi_y, hi_txt, label_font, label_size, label_col, label_alpha)
      draw_text_center_centered(cr, lo_x, lo_y, lo_txt, label_font, label_size, label_col, label_alpha)
    end
  end

  do
    if txt.enabled ~= false then
      local label = (inhg_source == "altimeter" or inhg_source == "a") and "ALT" or "SLP"
      local inhg_txt = inhg_val and string.format("%d", math.floor(inhg_val * 100 + 0.5)) or "/"
      local hpa_txt = hpa_val and string.format("%.1f", hpa_val) or "/"
      local sep = txt.separator or "  |  "
      local line = inhg_txt .. sep .. hpa_txt

      local font = txt.font
      if font == nil or font == "" or font == "auto" then
        font = sm.font_numbers or sm.font_value or "Exo 2"
      end
      local size = tonumber(txt.size) or 0
      if size <= 0 then
        size = tonumber(sm.value_size) or 22
      end
      local col = txt.color or sm.color_text or { 0.90, 0.90, 0.90 }
      local alpha = tonumber(txt.alpha) or tonumber(sm.alpha_text) or 0.85
      local y = center_y + scale(tonumber(txt.y_offset) or 0)

      local center_text_y = sm.center_text_y == true
      local draw_text = center_text_y and draw_text_center_centered or util.draw_text_center
      draw_text(cr, center_x, y, line, font, scale(size), col, alpha)

      if txt.show_source == true then
        local label_font = txt.source_font
        if label_font == nil or label_font == "" or label_font == "auto" then
          label_font = (t.fonts and t.fonts.title) or font
        end
        local label_size = tonumber(txt.source_size) or (size * 0.6)
        local label_col = txt.source_color or col
        local label_alpha = tonumber(txt.source_alpha) or alpha
        local label_offset = scale(tonumber(txt.source_y_offset) or 0)
        local label_size_px = scale(label_size)
        local label_y = center_y - circle_radius + (circle_stroke / 2) + (label_size_px / 2) + label_offset
        draw_text(cr, center_x, label_y, label, label_font, label_size_px, label_col, label_alpha)
      end
    end
  end
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

---@diagnostic disable-next-line: lowercase-global
function conky_baro_gauge(key)
  if key ~= "draw" then return "" end
  local ok, err = pcall(draw_baro_gauge_impl)
  if not ok then
    print("baro gauge error: " .. tostring(err))
  end
  return ""
end
