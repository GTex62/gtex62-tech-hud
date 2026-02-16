require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local draw_text_center = util.draw_text_center
local draw_text_center_fixed = util.draw_text_center_fixed
local read_file = util.read_file
local parse_vars_file = util.parse_vars_file

local OWM = { last_read = 0, cache_path = nil, ttl = 300, tz_offset_hours = nil }

local function get_owm_tz_offset_hours()
  local now = os.time()
  if OWM.tz_offset_hours ~= nil and (now - (OWM.last_read or 0)) < (OWM.ttl or 300) then
    return OWM.tz_offset_hours
  end

  local vars_path = SUITE_DIR .. "/config/owm.vars"
  local v = parse_vars_file(vars_path)

  local ttl = tonumber(v.CACHE_TTL) or 300
  local cache_path = v.OWM_DAILY_CACHE
  if not cache_path or cache_path == "" then
    cache_path = CACHE_DIR .. "/owm_forecast.json"
  end

  OWM.ttl = ttl
  OWM.cache_path = cache_path
  OWM.last_read = now

  local j = read_file(cache_path)
  if not j then
    OWM.tz_offset_hours = nil
    return nil
  end

  -- Extract numeric timezone_offset from JSON (seconds east of UTC)
  local off = j:match([["timezone_offset"%s*:%s*(-?%d+)]])
  off = tonumber(off)
  if not off then
    OWM.tz_offset_hours = nil
    return nil
  end

  OWM.tz_offset_hours = off / 3600
  return OWM.tz_offset_hours
end



local function polar(cx, cy, radius, angle)
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

local function draw_ring(cr, cx, cy, r, lw, col, a)
  set_rgba(cr, col, a)
  cairo_set_line_width(cr, lw)
  cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
  cairo_stroke(cr)
end

local function draw_ticks(cr, cx, cy, r_outer, len_minor, len_major, lw_minor, lw_major, col, alpha)
  set_rgba(cr, col, alpha)

  for i = 0, 59 do
    local a = (i / 60) * 2 * math.pi - (math.pi / 2)
    local is_major = (i % 5 == 0)

    local len = is_major and len_major or len_minor
    local lw = is_major and lw_major or lw_minor

    cairo_set_line_width(cr, lw)

    local x1, y1 = polar(cx, cy, r_outer - len, a)
    local x2, y2 = polar(cx, cy, r_outer, a)

    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
  end
end



local function draw_clock_numbers(cr, cx, cy, r_numbers, font_face, font_size, col, alpha, rotate, weight)
  set_rgba(cr, col, alpha)
  local font_weight = weight or CAIRO_FONT_WEIGHT_BOLD
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, font_weight)
  cairo_set_font_size(cr, font_size)

  for n = 1, 12 do
    local angle = (n / 12) * 2 * math.pi - (math.pi / 2)

    local x, y = polar(cx, cy, r_numbers, angle)
    local txt = tostring(n)

    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, txt, ext)

    cairo_save(cr)

    if rotate then
      cairo_translate(cr, x, y)
      cairo_rotate(cr, angle + math.pi / 2)
      cairo_move_to(cr, -(ext.width / 2 + ext.x_bearing), (ext.height / 2))
    else
      cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
    end

    cairo_show_text(cr, txt)
    cairo_restore(cr)
  end
end

local function draw_hand_arrow(cr, cx, cy, length, width, angle, col, alpha, arrow_len, arrow_w, inner_offset)
  set_rgba(cr, col, alpha)
  cairo_set_line_width(cr, width)
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

  local inner = tonumber(inner_offset) or 0
  if inner < 0 then
    inner = 0
  end
  local max_inner = length - arrow_len
  if max_inner < 0 then
    max_inner = 0
  end
  if inner > max_inner then
    inner = max_inner
  end

  -- tip and base of arrow
  local x_tip, y_tip   = polar(cx, cy, length, angle)
  local x_base, y_base = polar(cx, cy, length - arrow_len, angle)
  local x_inner, y_inner = polar(cx, cy, inner, angle)

  -- draw shaft ONLY to base of arrow
  cairo_move_to(cr, x_inner, y_inner)
  cairo_line_to(cr, x_base, y_base)
  cairo_stroke(cr)

  -- build arrow triangle
  local x_left, y_left   = polar(x_base, y_base, arrow_w / 2, angle - math.pi / 2)
  local x_right, y_right = polar(x_base, y_base, arrow_w / 2, angle + math.pi / 2)

  cairo_move_to(cr, x_tip, y_tip)
  cairo_line_to(cr, x_left, y_left)
  cairo_line_to(cr, x_right, y_right)
  cairo_close_path(cr)
  cairo_fill(cr)
end


local function second_whole()
  return tonumber(os.date("%S")) or 0
end

function conky_core_time()
  if conky_window == nil then return end

  local w, h       = conky_window.width, conky_window.height
  local cs         = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr         = cairo_create(cs)

  local t          = get_theme()

  local cx, cy     = w / 2, h / 2
  local r          = math.min(w, h) * (tonumber(t.clock_r_factor) or 0.17)

  local col_struct = (t.palette and t.palette.gray and t.palette.gray.g10) or { 0.20, 0.20, 0.20 }
  local col_ticks  = (t.palette and t.palette.gray and t.palette.gray.g20) or { 0.20, 0.20, 0.20 }
  local col_hours  = (t.palette and t.palette.accent and t.palette.accent.maroon) or { 0.40, 0.08, 0.12 }
  local col_black  = (t.palette and t.palette.black) or { 0.00, 0.00, 0.00 }
  local col_white  = (t.palette and t.palette.white) or { 1.00, 1.00, 1.00 }
  local col_orange = (t.palette and t.palette.accent and t.palette.accent.orange) or { 1.00, 0.62, 0.00 }

  -- clock face fill (gray @ 65% alpha)
  do
    local col_face = (t.palette and t.palette.gray and t.palette.gray.g30) or { 0.30, 0.30, 0.30 }
    set_rgba(cr, col_face, 0.65)
    cairo_arc(cr, cx, cy, r - scale(1.0), 0, 2 * math.pi)
    cairo_fill(cr)
  end

  -- subtle outer shadow / halo (outside-only)
  do
    local shadow_col = (t.palette and t.palette.black) or { 0.00, 0.00, 0.00 }

    -- all radii are OUTSIDE the ring
    draw_ring(cr, cx, cy, r + scale(6.0), scale(12.0), shadow_col, 0.10)
    draw_ring(cr, cx, cy, r + scale(10.0), scale(18.0), shadow_col, 0.06)
    draw_ring(cr, cx, cy, r + scale(16.0), scale(26.0), shadow_col, 0.03)
  end

  local struct_color = t.clock_struct_color or col_struct
  local struct_alpha = tonumber(t.clock_struct_alpha) or 0.60
  draw_ring(cr, cx, cy, r, scale(6.0), struct_color, struct_alpha)

  local bezel_rot = 0

  -- ===============================
  -- 24h bezel (with rotation logic)
  -- ===============================
  do
    local bezel_r = r + scale(tonumber(t.clock_bezel_r_offset) or 54)  -- distance from clock center (≈50px gap + ring)
    local seg_len = scale(60)                                          -- angular segment length (visual width)
    local seg_gap = scale(tonumber(t.clock_bezel_seg_gap) or 20)       -- gap between segments
    local seg_thick = scale(tonumber(t.clock_bezel_seg_thick) or 21.0) -- thickness of bezel stroke
    local seg_arc = math.max(seg_len - seg_gap, 0)

    local col_bezel = (t.palette and t.palette.gray and t.palette.gray.g50) or { 0.6, 0.6, 0.6 }
    local col_black = (t.palette and t.palette.black) or { 0, 0, 0 }
    local col_orange = (t.palette and t.palette.accent and t.palette.accent.orange) or { 1, 0.62, 0 }

    -- rotation: manual utc offset (hours). Negative = west of UTC.
    -- We rotate the bezel so the 0/24 marker shifts around the dial.
    local utc_off = nil
    if t.clock_bezel_auto == true then
      utc_off = get_owm_tz_offset_hours()
    end
    if utc_off == nil then
      utc_off = tonumber(t.clock_bezel_utc_offset) or 0
    end
    local rot = (utc_off / 24) * 2 * math.pi
    bezel_rot = rot

    -- draw 24 segmented arcs
    for i = 0, 23 do
      local a_center = (i / 24) * 2 * math.pi - math.pi / 2 + rot
      local a1 = a_center - (seg_arc / (bezel_r * 2))
      local a2 = a_center + (seg_arc / (bezel_r * 2))

      set_rgba(cr, col_bezel, 0.85)
      cairo_set_line_width(cr, seg_thick)
      cairo_arc(cr, cx, cy, bezel_r, a1, a2)
      cairo_stroke(cr)
    end

    -- thin maroon circle, 10px outside the segment outer edge
    do
      local col_maroon = t.clock_bezel_outer_ring_color
        or (t.palette and t.palette.accent and t.palette.accent.maroon)
        or { 0.40, 0.08, 0.12 }
      local outer_offset = scale(tonumber(t.clock_bezel_outer_ring_offset) or 8)
      local outer_width = scale(tonumber(t.clock_bezel_outer_ring_width) or 4.0)
      local outer_alpha = tonumber(t.clock_bezel_outer_ring_alpha) or 1.00
      local outer_r = bezel_r + (seg_thick / 2) + outer_offset
      draw_ring(cr, cx, cy, outer_r, outer_width, col_maroon, outer_alpha)
    end

    -- draw numbers: 2..22 only (rotated)
    local bezel_font = t.clock_bezel_font
    if bezel_font == nil or bezel_font == "" or bezel_font == "auto" then
      bezel_font = (t.fonts and t.fonts.accent_black) or "Orbitron Black"
    end
    local bezel_font_size = scale(tonumber(t.clock_bezel_font_size) or 14)
    local bezel_font_color = t.clock_bezel_font_color or col_black
    local bezel_font_alpha = tonumber(t.clock_bezel_font_alpha) or 0.95
    cairo_select_font_face(cr, bezel_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, bezel_font_size)
    set_rgba(cr, bezel_font_color, bezel_font_alpha)

    for h = 2, 22, 2 do
      local i = h
      local angle = (i / 24) * 2 * math.pi - math.pi / 2 + rot
      local tx, ty = polar(cx, cy, bezel_r, angle)

      local txt = tostring(h)
      local ext = cairo_text_extents_t:create()
      cairo_text_extents(cr, txt, ext)

      cairo_save(cr)
      cairo_translate(cr, tx, ty)
      cairo_rotate(cr, angle + math.pi / 2)
      cairo_move_to(cr, -(ext.width / 2 + ext.x_bearing), ext.height / 2)
      cairo_show_text(cr, txt)
      cairo_restore(cr)
    end

    -- draw 0/24 triangle marker at "top" for now
    do
      local angle = -math.pi / 2 + rot
      local tip_r = bezel_r - scale(6)
      local base_r = bezel_r + scale(8)

      local x_tip, y_tip = polar(cx, cy, tip_r, angle)
      local x_base, y_base = polar(cx, cy, base_r, angle)

      local w = scale(10)
      local lx, ly = polar(x_base, y_base, w, angle - math.pi / 2)
      local rx, ry = polar(x_base, y_base, w, angle + math.pi / 2)

      local marker_color = t.clock_bezel_marker_color or col_orange
      local marker_alpha = tonumber(t.clock_bezel_marker_alpha) or 0.95
      set_rgba(cr, marker_color, marker_alpha)
      cairo_move_to(cr, x_tip, y_tip)
      cairo_line_to(cr, lx, ly)
      cairo_line_to(cr, rx, ry)
      cairo_close_path(cr)
      cairo_fill(cr)
    end
  end

  local minute_tick_len = scale(tonumber(t.clock_minute_tick_len) or 8)
  local minute_tick_width = scale(tonumber(t.clock_minute_tick_width) or 4.0)
  local minute_tick_color = t.clock_minute_tick_color or col_ticks
  local minute_tick_alpha = tonumber(t.clock_minute_tick_alpha) or 0.95

  draw_ticks(
    cr,
    cx, cy,
    r - scale(6),
    minute_tick_len,
    minute_tick_len,
    minute_tick_width,
    minute_tick_width,
    minute_tick_color,
    minute_tick_alpha
  )

  do
    set_rgba(cr, col_hours, 0.95)
    local hour_tick_len = scale(tonumber(t.clock_hour_tick_len) or 20)
    local hour_tick_width = scale(tonumber(t.clock_hour_tick_width) or 6.0)
    local hour_tick_r_offset = scale(tonumber(t.clock_hour_tick_r_offset) or 0)
    cairo_set_line_width(cr, hour_tick_width)

    local r_mid = r + hour_tick_r_offset
    local r_outer = r_mid + (hour_tick_len / 2)
    local r_inner = r_mid - (hour_tick_len / 2)

    for i = 0, 11 do
      local a = (i / 12) * 2 * math.pi - (math.pi / 2)
      local x1, y1 = polar(cx, cy, r_inner, a)
      local x2, y2 = polar(cx, cy, r_outer, a)
      cairo_move_to(cr, x1, y1)
      cairo_line_to(cr, x2, y2)
      cairo_stroke(cr)
    end
  end

  if t.clock_show_numbers == true then
    local numbers_font = t.clock_numbers_font
    if numbers_font == nil or numbers_font == "" or numbers_font == "auto" then
      numbers_font = (t.fonts and t.fonts.value_b) or "Exo 2"
    end
    local numbers_size = scale(tonumber(t.clock_numbers_size) or 24)
    local numbers_color = t.clock_numbers_color or col_hours
    local numbers_alpha = tonumber(t.clock_numbers_alpha) or 0.95
    local numbers_r = r * (tonumber(t.clock_numbers_r_factor) or 0.86)
    local numbers_weight = t.clock_numbers_weight
    local font_weight = CAIRO_FONT_WEIGHT_BOLD
    if numbers_weight == "normal" then
      font_weight = CAIRO_FONT_WEIGHT_NORMAL
    elseif numbers_weight == "bold" then
      font_weight = CAIRO_FONT_WEIGHT_BOLD
    end
    draw_clock_numbers(
      cr,
      cx, cy,
      numbers_r,
      numbers_font,
      numbers_size,
      numbers_color,
      numbers_alpha,
      t.clock_rotate_numbers == true,
      font_weight
    )
  end

  -- date window at 3 o'clock
  if t.clock_date_window_enabled ~= false then
    local base_r = r * (tonumber(t.clock_numbers_r_factor) or 0.86)
    local date_r = base_r + scale(tonumber(t.clock_date_window_r_offset) or -18)
    local x, y = polar(cx, cy, date_r, 0)
    local box = scale(tonumber(t.clock_date_window_box_size) or 22)
    local half = box / 2
    local col_bg = t.clock_date_window_bg_color
      or (t.palette and t.palette.gray and t.palette.gray.g70)
      or { 0.70, 0.70, 0.70 }
    local col_txt = t.clock_date_window_text_color
      or (t.palette and t.palette.black)
      or { 0.00, 0.00, 0.00 }
    local bg_alpha = tonumber(t.clock_date_window_bg_alpha) or 1.0
    local txt_alpha = tonumber(t.clock_date_window_text_alpha) or 1.0

    set_rgba(cr, col_bg, bg_alpha)
    cairo_rectangle(cr, x - half, y - half, box, box)
    cairo_fill(cr)

    local date_txt = os.date("%d") --[[@as string]]
    local font_face = t.clock_date_window_font
    if font_face == nil or font_face == "" or font_face == "auto" then
      font_face = (t.fonts and t.fonts.value) or "Exo 2"
    end
    local font_size = scale(tonumber(t.clock_date_window_font_size) or 14)

    cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)

    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, date_txt, ext)
    set_rgba(cr, col_txt, txt_alpha)
    cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
    cairo_show_text(cr, date_txt)
  end

  -- =======================================
  -- Digital readouts (UTC + Local + Offset)
  -- =======================================
  do
    local face_top_y = cy + r * (tonumber(t.clock_local_time_y_factor) or -0.45)
    local face_bottom_y = cy + r * (tonumber(t.clock_utc_time_y_factor) or 0.55)

    local font_face = (t.fonts and t.fonts.accent_black) or "Orbitron Black"
    local font_face_small = (t.fonts and t.fonts.accent_black) or "Orbitron Black"

    local col_g20 = (t.palette and t.palette.gray and t.palette.gray.g20) or { 0.20, 0.20, 0.20 }
    local col_g70 = (t.palette and t.palette.gray and t.palette.gray.g70) or { 0.70, 0.70, 0.70 }
    local col_orange = (t.palette and t.palette.accent and t.palette.accent.orange) or { 1.00, 0.62, 0.00 }
    local local_col = t.clock_local_time_color or col_g20
    local local_alpha = tonumber(t.clock_local_time_alpha) or 0.90
    local local_size = scale(tonumber(t.clock_local_time_size) or 28)
    local utc_col = t.clock_utc_time_color or col_g70
    local utc_alpha = tonumber(t.clock_utc_time_alpha) or 0.50
    local utc_size = scale(tonumber(t.clock_utc_time_size) or 24)
    local tz_col = t.clock_tz_label_color or col_orange
    local tz_alpha = tonumber(t.clock_tz_label_alpha) or 0.50
    local tz_size = scale(tonumber(t.clock_tz_label_size) or 18)
    local tz_y = face_bottom_y + scale(tonumber(t.clock_tz_label_y_offset) or 24)

    -- Top: Local time (darker gray)
    local local_time = os.date("%H:%M")
    draw_text_center_fixed(cr, cx, face_top_y, local_time, font_face, local_size, local_col, local_alpha)

    -- Bottom: UTC time (lighter gray)
    local utc_time = os.date("!%H:%M")
    draw_text_center_fixed(cr, cx, face_bottom_y, utc_time, font_face, utc_size, utc_col, utc_alpha)

    -- Offset line under local time (orange)
    local off = nil
    if t.clock_bezel_auto == true then
      off = get_owm_tz_offset_hours()
    end
    if off == nil then
      off = tonumber(t.clock_bezel_utc_offset) or 0
    end

    local tz_label = nil
    if t.clock_bezel_auto == true then
      -- Offset-based labels; extend as needed.
      local tz_map = {
        [-10] = "HST",
        [-9] = "AKST",
        [-8] = "PST",
        [-7] = "PDT",
        [-6] = "CST",
        [-5] = "CDT",
        [-4] = "EDT",
        [-3] = "ADT",
        [0] = "UTC",
        [1] = "CET",
        [2] = "EET",
        [3] = "MSK",
        [5.5] = "IST",
        [8] = "CST",
        [9] = "JST",
        [10] = "AEST",
      }
      tz_label = tz_map[off]
    end
    if tz_label == nil then
      tz_label = (t.clock_tz_label ~= nil and tostring(t.clock_tz_label)) or "CST"
    end
    local off_txt = string.format("%s %+g", tz_label, off)

    draw_text_center(cr, cx, tz_y, off_txt, font_face_small, tz_size, tz_col, tz_alpha)
  end

  local hours              = tonumber(os.date("%I")) or 0
  local minutes            = tonumber(os.date("%M")) or 0
  local seconds            = second_whole()

  local hour_fraction      = (hours % 12) + (minutes / 60)
  local ang_hour           = (hour_fraction / 12) * 2 * math.pi - (math.pi / 2)
  local ang_min            = ((minutes + (seconds / 60)) / 60) * 2 * math.pi - (math.pi / 2)
  local ang_sec            = (seconds / 60) * 2 * math.pi - (math.pi / 2)

  local gmt_h              = tonumber(os.date("!%H")) or 0
  local gmt_m              = tonumber(os.date("!%M")) or 0
  local gmt_fraction       = gmt_h + (gmt_m / 60) - 0.5
  local ang_gmt            = (gmt_fraction / 24) * 2 * math.pi - (math.pi / 2) + bezel_rot

  local hour_len           = r * (tonumber(t.clock_hand_hour_len_factor) or 0.78)
  local hour_width         = scale(tonumber(t.clock_hand_hour_width) or 10.0)
  local hour_col           = t.clock_hand_hour_color or col_struct
  local hour_alpha         = tonumber(t.clock_hand_hour_alpha) or 0.70
  local hour_arrow_len     = scale(tonumber(t.clock_hand_hour_arrow_len) or 22)
  local hour_arrow_width   = scale(tonumber(t.clock_hand_hour_arrow_width) or 24)

  local minute_len         = r * (tonumber(t.clock_hand_minute_len_factor) or 0.92)
  local minute_width       = scale(tonumber(t.clock_hand_minute_width) or 7.5)
  local minute_col         = t.clock_hand_minute_color or col_struct
  local minute_alpha       = tonumber(t.clock_hand_minute_alpha) or 0.75
  local minute_arrow_len   = scale(tonumber(t.clock_hand_minute_arrow_len) or 22)
  local minute_arrow_width = scale(tonumber(t.clock_hand_minute_arrow_width) or 14)

  local second_len         = r * (tonumber(t.clock_hand_second_len_factor) or 0.93)
  local second_width       = scale(tonumber(t.clock_hand_second_width) or 2.5)
  local second_col         = t.clock_hand_second_color or col_white
  local second_alpha       = tonumber(t.clock_hand_second_alpha) or 0.50
  local second_arrow_len   = scale(tonumber(t.clock_hand_second_arrow_len) or 14)
  local second_arrow_width = scale(tonumber(t.clock_hand_second_arrow_width) or 12)

  local gmt_len            = r * (tonumber(t.clock_hand_gmt_len_factor) or 1.16)
  local gmt_width          = scale(tonumber(t.clock_hand_gmt_width) or 4.0)
  local gmt_col            = t.clock_hand_gmt_color or col_orange
  local gmt_alpha          = tonumber(t.clock_hand_gmt_alpha) or 0.65
  local gmt_arrow_len      = scale(tonumber(t.clock_hand_gmt_arrow_len) or 15)
  local gmt_arrow_width    = scale(tonumber(t.clock_hand_gmt_arrow_width) or 16)
  local gmt_inner_offset   = scale(tonumber(t.clock_hand_gmt_inner_offset) or 0)

  -- hour hand (thicker)
  draw_hand_arrow(cr, cx, cy, hour_len, hour_width, ang_hour, hour_col, hour_alpha, hour_arrow_len, hour_arrow_width)

  -- minute hand
  draw_hand_arrow(cr, cx, cy, minute_len, minute_width, ang_min, minute_col, minute_alpha, minute_arrow_len,
    minute_arrow_width)

  -- second hand (shorter)
  draw_hand_arrow(cr, cx, cy, second_len, second_width, ang_sec, second_col, second_alpha, second_arrow_len,
    second_arrow_width)

  -- GMT hand (longer, clearly beyond ring)
  draw_hand_arrow(cr, cx, cy, gmt_len, gmt_width, ang_gmt, gmt_col, gmt_alpha, gmt_arrow_len, gmt_arrow_width,
    gmt_inner_offset)


  -- center: bigger solid black cap + subtle outer ring
  do
    -- subtle ring just outside the cap
    draw_ring(cr, cx, cy, scale(18), scale(4.7), col_struct, 0.30)

    -- full black center dot
    set_rgba(cr, col_black, 1.00)
    cairo_arc(cr, cx, cy, scale(9.0), 0, 2 * math.pi)
    cairo_fill(cr)
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_draw_center_pre()
  if type(conky_draw_calendar_marquee) == "function" then
    conky_draw_calendar_marquee()
  end
  conky_core_time()
end

function conky_draw_center_post()
  if type(conky_draw_volvelle_ring) == "function" then
    conky_draw_volvelle_ring()
  end
  if type(conky_draw_calendar_ring) == "function" then
    conky_draw_calendar_ring()
  end
end
