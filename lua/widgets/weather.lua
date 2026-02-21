--[[
  ${CONKY_SUITE_DIR}/lua/widgets/weather.lua
  Weather widget (mirrored brackets + OWM drawing)
]]

require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local hex_to_rgba = util.hex_to_rgba
local draw_text_center = util.draw_text_center
local draw_text_left = util.draw_text_left
local draw_text_block_left = util.draw_text_block_left
local count_text_lines = util.count_text_lines
local file_exists = util.file_exists
local draw_png_centered = util.draw_png_centered

local function draw_weather_brackets(cr, w, h, t)
  local ww = t.weather_widget or {}
  local cal = t.calendar_marquee or {}
  local palette = t.palette or {}

  local cx = (w / 2) + scale(tonumber(ww.center_x_offset) or 0)
  local cy = (h / 2) + scale(tonumber(ww.center_y_offset) or 0)

  local title_text = tostring(ww.title_text or "WEATHER")
  local title_font = ww.title_font
  if title_font == nil or title_font == "" or title_font == "auto" then
    title_font = (t.fonts and t.fonts.title) or "Rajdhani"
  end
  local title_size = scale(tonumber(ww.title_size) or 16)
  local title_alpha = tonumber(ww.title_alpha) or 0.80
  local title_y = cy + scale(tonumber(ww.title_y_offset) or 0)
  local draw_title = ww.draw_title ~= false

  local bracket_y = title_y + scale(tonumber(ww.bracket_y_offset) or 0)
  local bracket_short = scale(tonumber(ww.bracket_short) or 0)
  local bracket_diag_dx = scale(tonumber(ww.bracket_diag_dx) or 10)
  local bracket_diag_dy = scale(tonumber(ww.bracket_diag_dy) or 40)
  local bracket_diag_scale = tonumber(ww.bracket_diag_scale) or 1.0
  local bracket_long_pad = scale(tonumber(ww.bracket_long_pad) or 55)
  local bracket_long_len = scale(tonumber(ww.bracket_long_len) or 0)
  local bracket_vert = scale(tonumber(ww.bracket_vert) or 75)
  local bracket_width = scale(tonumber(ww.bracket_width) or 3.0)
  local bracket_alpha = tonumber(ww.bracket_alpha) or 0.30
  local bracket_side_gap = scale(tonumber(ww.bracket_side_gap) or 34)

  local col_bracket = ww.color_bracket
      or (t.calendar_marquee and t.calendar_marquee.color_bracket)
      or (palette.white) or { 1.00, 1.00, 1.00 }
  local col_title = ww.color_title
      or (t.calendar_marquee and t.calendar_marquee.color_title)
      or (palette.black) or { 0.00, 0.00, 0.00 }

  if draw_title then
    draw_text_center(cr, cx, title_y, title_text, title_font, title_size, col_title, title_alpha)
  end

  local ext = cairo_text_extents_t:create()
  cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, title_size)
  cairo_text_extents(cr, title_text, ext)
  local title_left = cx - (ext.width / 2 + ext.x_bearing)
  local title_right = title_left + ext.width

  local arc_cx = (w / 2) + scale(tonumber(cal.center_x_offset) or 0)
  local arc_r = scale(tonumber(cal.r_offset) or 660)
  local arc_center_deg = tonumber(cal.arc_center_deg) or 90
  local arc_span_deg = tonumber(cal.arc_span_deg) or 70
  local arc_left_deg = arc_center_deg + (arc_span_deg / 2)
  local arc_right_deg = arc_center_deg - (arc_span_deg / 2)

  local arc_left_x = arc_cx + arc_r * math.cos((math.pi / 180) * arc_left_deg)
  local arc_right_x = arc_cx + arc_r * math.cos((math.pi / 180) * arc_right_deg)

  local short = bracket_short
  local diag_dx = bracket_diag_dx * bracket_diag_scale
  local diag_dy = bracket_diag_dy * bracket_diag_scale
  local long_y = bracket_y + diag_dy

  set_rgba(cr, col_bracket, bracket_alpha)
  cairo_set_line_width(cr, bracket_width)

  local left_start = title_left - bracket_side_gap
  local left_short_end = left_start - short
  local left_diag_end_x = left_short_end - diag_dx
  local left_diag_end_y = long_y
  local left_long_end_x
  if bracket_long_len > 0 then
    left_long_end_x = left_diag_end_x - bracket_long_len
  else
    left_long_end_x = math.min(left_diag_end_x - scale(10), arc_left_x - bracket_long_pad)
  end

  cairo_move_to(cr, left_start, bracket_y)
  cairo_line_to(cr, left_short_end, bracket_y)
  cairo_line_to(cr, left_diag_end_x, left_diag_end_y)
  cairo_line_to(cr, left_long_end_x, left_diag_end_y)
  cairo_line_to(cr, left_long_end_x, left_diag_end_y - bracket_vert)
  cairo_stroke(cr)

  local right_start = title_right + bracket_side_gap
  local right_short_end = right_start + short
  local right_diag_end_x = right_short_end + diag_dx
  local right_diag_end_y = long_y
  local right_long_end_x
  if bracket_long_len > 0 then
    right_long_end_x = right_diag_end_x + bracket_long_len
  else
    right_long_end_x = math.max(right_diag_end_x + scale(10), arc_right_x + bracket_long_pad)
  end

  cairo_move_to(cr, right_start, bracket_y)
  cairo_line_to(cr, right_short_end, bracket_y)
  cairo_line_to(cr, right_diag_end_x, right_diag_end_y)
  cairo_line_to(cr, right_long_end_x, right_diag_end_y)
  cairo_line_to(cr, right_long_end_x, right_diag_end_y - bracket_vert)
  cairo_stroke(cr)
end

function conky_draw_weather_widget()
  if conky_window == nil then return end

  local t = get_theme()
  local w, h = conky_window.width, conky_window.height

  if type(conky_draw_center_pre) == "function" then
    conky_draw_center_pre()
  end

  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  draw_weather_brackets(cr, w, h, t)

  if type(conky_owm_draw_forecast_placeholder) == "function" then
    conky_owm_draw_forecast_placeholder()
  end

  do
    local ww = t.weather_widget or {}
    local weather = t.weather or {}
    local wx = scale(tonumber(ww.center_x_offset) or 0)
    local wy = scale(tonumber(ww.center_y_offset) or 0)
    local base_cx = (w / 2) + wx
    local base_cy = (h / 2) + wy
    local icon_off_x = scale(tonumber(ww.icon_offset_x) or 0)
    local icon_off_y = scale(tonumber(ww.icon_offset_y) or 0)
    local icon_cx = base_cx + icon_off_x
    local icon_cy = base_cy + icon_off_y

    local icon_size = scale(tonumber(ww.icon_size) or 42)
    local temp_size = scale(tonumber(ww.temp_size) or 32)
    local label_size = scale(tonumber(ww.humidity_size) or 16)

    local col_text = (t.palette and t.palette.gray and t.palette.gray.g70) or { 0.70, 0.70, 0.70 }
    local col_dim = (t.palette and t.palette.gray and t.palette.gray.g50) or { 0.50, 0.50, 0.50 }

    local city = (type(conky_owm) == "function") and conky_owm("city") or ""
    local temp = (type(conky_owm) == "function") and conky_owm("temp") or ""
    local humidity = (type(conky_owm) == "function") and conky_owm("humidity") or ""

    local font_value = (t.fonts and t.fonts.value) or "Exo 2"
    local font_label = (t.fonts and t.fonts.label) or "Rajdhani"
    local temp_font = ww.temp_font
    if temp_font == nil or temp_font == "" or temp_font == "auto" then
      temp_font = font_value
    end
    local temp_size = scale(tonumber(ww.temp_size) or temp_size)
    local temp_col = ww.temp_color or col_text
    local temp_alpha = tonumber(ww.temp_alpha) or 0.95
    local humidity_font = ww.humidity_font
    if humidity_font == nil or humidity_font == "" or humidity_font == "auto" then
      humidity_font = font_label
    end
    local humidity_size = scale(tonumber(ww.humidity_size) or label_size)
    local humidity_col = ww.humidity_color or col_dim
    local humidity_alpha = tonumber(ww.humidity_alpha) or 0.85
    local city_font = ww.city_font
    if city_font == nil or city_font == "" or city_font == "auto" then
      city_font = font_label
    end
    local city_size = scale(tonumber(ww.city_size) or label_size)
    local city_col = ww.city_color or col_dim
    local city_alpha = tonumber(ww.city_alpha) or 0.85

    do
      local vline = weather.vline or {}
      local len = scale(tonumber(vline.length) or 60)
      local lw = scale(tonumber(vline.width) or 2)
      local dx = scale(tonumber(vline.dx) or 0)
      local dy = scale(tonumber(vline.dy) or 0)
      local col = vline.color or "A0A0A0"
      local alpha = tonumber(vline.alpha) or 1.0
      local base_cx = (w / 2) + wx
      local base_cy = (h / 2) + wy
      local cx_line = base_cx + dx
      local y1 = base_cy + dy
      local y2 = y1 + len
      local r_, g_, b_, a_ = hex_to_rgba(col, alpha)

      cairo_set_source_rgba(cr, r_, g_, b_, a_)
      cairo_set_line_width(cr, lw)
      cairo_move_to(cr, cx_line, y1)
      cairo_line_to(cr, cx_line, y2)
      cairo_stroke(cr)
    end

    local temp_x = base_cx + scale(tonumber(ww.temp_offset_x) or 0)
    local temp_y = base_cy + scale(tonumber(ww.temp_offset_y) or 0)
    local hum_x = base_cx + scale(tonumber(ww.humidity_offset_x) or 0)
    local hum_y = base_cy + scale(tonumber(ww.humidity_offset_y) or 0)
    local city_x = base_cx + scale(tonumber(ww.city_offset_x) or 0)
    local city_y = base_cy + scale(tonumber(ww.city_offset_y) or 0)

    draw_text_center(cr, temp_x, temp_y, temp .. "°", temp_font, temp_size, temp_col, temp_alpha)
    draw_text_center(cr, hum_x, hum_y, humidity .. "%", humidity_font, humidity_size, humidity_col, humidity_alpha)
    draw_text_center(cr, city_x, city_y, city, city_font, city_size, city_col, city_alpha)

    local icon_cache_dir = CACHE_DIR .. "/icons"
    do
      local cache_dir = weather.icon_cache_dir
      if cache_dir ~= nil and cache_dir ~= "" then
        cache_dir = tostring(cache_dir)
        if cache_dir:sub(1, 1) == "/" then
          icon_cache_dir = cache_dir
        else
          icon_cache_dir = CACHE_DIR .. "/" .. cache_dir
        end
      end
    end
    local icon_path = icon_cache_dir .. "/current.png"
    draw_png_centered(cr, icon_path, icon_cx, icon_cy, icon_size)
  end

  do
    local weather = t.weather or {}
    local style = weather.aviation_style or {}
    local clock_cx = w / 2
    local clock_cy = h / 2
    local font_default = (t.fonts and (t.fonts.value_c or t.fonts.value)) or "Exo 2"
    local col_default = (t.palette and t.palette.gray and t.palette.gray.g70) or { 0.70, 0.70, 0.70 }

    local font = style.font
    if font == nil or font == "" or font == "auto" then
      font = font_default
    end
    local size = scale(tonumber(style.size) or 12)
    local col = style.color or col_default
    local alpha = tonumber(style.alpha) or 0.85
    local line_gap = scale(tonumber(style.line_gap) or 4)
    local step = size + line_gap
    local gap_lines = tonumber(style.gap_lines) or 1
    local auto_stack = (style.auto_stack == true)

    local function draw_block(cfg, text, x, y)
      if cfg == nil then return 0 end
      if cfg.enabled == false then return 0 end
      if text == nil or text == "" then return 0 end
      draw_text_block_left(cr, x, y, text, font, size, col, alpha, line_gap)
      return count_text_lines(text)
    end

    local function next_y(y, lines)
      if lines <= 0 then return y end
      return y + (lines + gap_lines) * step
    end

    local metar_cfg = weather.metar or {}
    local taf_cfg = weather.taf or {}
    local adv_cfg = weather.advisories or {}

    local metar_txt = (type(conky_metar) == "function") and conky_metar() or ""
    local taf_txt = (type(conky_taf) == "function") and conky_taf() or ""
    local adv_txt = (type(conky_advisories) == "function") and conky_advisories() or ""

    local metar_x = clock_cx + scale(tonumber(metar_cfg.x_offset) or 0)
    local taf_x = clock_cx + scale(tonumber(taf_cfg.x_offset) or 0)
    local adv_x = clock_cx + scale(tonumber(adv_cfg.x_offset) or 0)

    local metar_y = clock_cy + scale(tonumber(metar_cfg.y_offset) or 0)
    local taf_y = clock_cy + scale(tonumber(taf_cfg.y_offset) or 0)
    local adv_y = clock_cy + scale(tonumber(adv_cfg.y_offset) or 0)

    local metar_lines = draw_block(metar_cfg, metar_txt, metar_x, metar_y)
    if auto_stack then
      taf_y = next_y(metar_y, metar_lines)
    end
    local taf_lines = draw_block(taf_cfg, taf_txt, taf_x, taf_y)
    if auto_stack then
      adv_y = next_y(taf_y, taf_lines)
    end
    draw_block(adv_cfg, adv_txt, adv_x, adv_y)
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)

  if type(conky_draw_center_post) == "function" then
    conky_draw_center_post()
  end
end
