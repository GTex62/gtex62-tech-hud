--[[
  ${CONKY_SUITE_DIR}/lua/widgets/calendar.lua
  Calendar ring (seasons) around the center clock.
]]

require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local draw_text_center = util.draw_text_center_mid
local read_file = util.read_file
local parse_vars_file = util.parse_vars_file

local function polar(cx, cy, radius, angle)
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

local function draw_ring(cr, cx, cy, r, lw, col, a)
  if r <= 0 then return end
  set_rgba(cr, col, a)
  cairo_set_line_width(cr, lw)
  ---@diagnostic disable-next-line: undefined-global
  cairo_new_sub_path(cr)
  cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
  cairo_stroke(cr)
end

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

local function days_in_year(year)
  local t0 = os.time({ year = year, month = 1, day = 1, hour = 0 })
  local t1 = os.time({ year = year + 1, month = 1, day = 1, hour = 0 })
  return math.floor((t1 - t0) / 86400)
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

local function ymd_string(t)
  if not t then return nil end
  return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function dst_dates_local(year)
  local dst_start = nil
  local dst_end = nil
  local prev = nil
  for day = 0, 366 do
    local ts = os.time({ year = year, month = 1, day = 1, hour = 12 }) + (day * 86400)
    local dt = os.date("*t", ts)
    if dt.year ~= year then break end
    local cur = (dt.isdst == true)
    if prev == nil then
      prev = cur
    else
      if (not prev) and cur and dst_start == nil then
        dst_start = { year = dt.year, month = dt.month, day = dt.day }
      end
      if prev and (not cur) and dst_end == nil then
        dst_end = { year = dt.year, month = dt.month, day = dt.day }
      end
      prev = cur
    end
  end
  return dst_start, dst_end
end

local function draw_text_arc(cr, cx, cy, r, angle_mid, txt, font_face, font_size, col, alpha)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)

  local parts = {}
  local total = 0
  for ch in txt:gmatch(".") do
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, ch, ext)
    local adv = ext.x_advance
    total = total + adv
    parts[#parts + 1] = { ch = ch, ext = ext, adv = adv }
  end

  if total <= 0 or r <= 0 then return end

  local arc = total / r
  local angle = angle_mid - (arc / 2)
  for _, p in ipairs(parts) do
    local a = angle + (p.adv / 2) / r
    local x, y = polar(cx, cy, r, a)
    local rot = a + math.pi / 2

    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_rotate(cr, rot)
    cairo_move_to(cr, -(p.ext.width / 2 + p.ext.x_bearing), p.ext.height / 2)
    cairo_show_text(cr, p.ch)
    cairo_restore(cr)

    angle = angle + (p.adv / r)
  end
end

local function draw_calendar_ring_impl()
  if conky_window == nil then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local t = get_theme()
  local v = (type(t.volvelle) == "table") and t.volvelle or {}
  local c = (type(t.calendar) == "table") and t.calendar or {}
  if c.enabled == false then
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    return
  end

  local cx, cy = w / 2, h / 2
  local r_clock = math.min(w, h) * (tonumber(t.clock_r_factor) or 0.17)

  local ring_r = (type(v.r) == "number") and scale(v.r) or (r_clock + scale(v.r_offset or 85))
  local ring_w = scale(v.stroke or 6.0)

  local s_stroke = scale(tonumber(c.stroke) or 40.0)
  local s_gap = scale(tonumber(c.gap_px) or 10)
  local s_r = ring_r + (ring_w / 2) + s_gap + (s_stroke / 2) - scale(5) + scale(tonumber(c.r_offset) or 0)
  local s_col = c.color or { 0.10, 0.10, 0.10 }
  local s_alpha = tonumber(c.alpha) or 0.50
  local s_text_col = c.text_color or { 0.20, 0.20, 0.20 }
  local s_text_alpha = tonumber(c.text_alpha) or 0.70
  local s_text_size = scale(tonumber(c.text_size) or 16)
  local s_text_r = s_r + scale(tonumber(c.text_r_offset) or 0)
  local s_font = c.font
  if s_font == nil or s_font == "" or s_font == "auto" then
    s_font = (t.fonts and t.fonts.title) or "Rajdhani Medium"
  end

  local now = os.time()
  local now_t = os.date("*t", now)
  local year = now_t.year
  local year_start = os.time({ year = year, month = 1, day = 1, hour = 0 })
  local year_days = days_in_year(year)
  local today_doy = math.floor((now - year_start) / 86400) + 1
  local rot_year = -((today_doy - 1) / year_days) * 2 * math.pi
  local month_start_doy = day_of_year_for_date(string.format("%04d-%02d-01", year, now_t.month), year)
  local ideal_month_start = (now_t.month - 1) / 12
  local month_offset = 0
  if month_start_doy then
    month_offset = (((month_start_doy - 1) / year_days) - ideal_month_start) * 2 * math.pi
  end
  local rot_months = rot_year + month_offset
  local days = (type(c.days) == "table") and c.days or {}
  local rot_days = rot_months
  if days.rotate == false then
    rot_days = -math.pi / 12 -- half-segment CCW offset
  end

  local today_tick = math.floor(((today_doy - 1) / year_days) * 360 + 0.5) % 360
  if days.rotate == false then
    today_tick = math.floor((-rot_days) * 360 / (2 * math.pi) + 0.5) % 360
  end

  local seasonal = read_seasonal_vars()
  local spring_doy = day_of_year_for_date(seasonal.SPRING_EQ_DATE, year)
  local summer_doy = day_of_year_for_date(seasonal.SUMMER_SOL_DATE, year)
  local autumn_doy = day_of_year_for_date(seasonal.AUTUMN_EQ_DATE, year)
  local winter_doy = day_of_year_for_date(seasonal.WINTER_SOL_DATE, year)

  if not spring_doy then spring_doy = day_of_year_for_date(string.format("%d-03-20", year), year) end
  if not summer_doy then summer_doy = day_of_year_for_date(string.format("%d-06-21", year), year) end
  if not autumn_doy then autumn_doy = day_of_year_for_date(string.format("%d-09-22", year), year) end
  if not winter_doy then winter_doy = day_of_year_for_date(string.format("%d-12-21", year), year) end

  local function day_angle(doy)
    return ((doy - 1) / year_days) * 2 * math.pi - math.pi / 2 + rot_months
  end

  local function draw_arc_segment(a_start, a_end, r)
    if a_end < a_start then a_end = a_end + (2 * math.pi) end
        ---@diagnostic disable-next-line: undefined-global
        cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, a_start, a_end)
    cairo_stroke(cr)
  end

  set_rgba(cr, s_col, s_alpha)
  cairo_set_line_width(cr, s_stroke)
  local gap_ang = (s_r > 0) and (s_gap / s_r) or 0

  local season_tint_enabled = (c.season_tint_enable ~= false)
  local season_tint_amt = tonumber(c.season_tint_amount) or 0.08
  local season_tints = {
    WINTER = { 0.20, 0.30, 0.45 }, -- blue
    SPRING = { 0.85, 0.80, 0.40 }, -- orange/yellow
    SUMMER = { 0.30, 0.55, 0.30 }, -- green
    AUTUMN = { 0.75, 0.35, 0.25 }, -- orange/red
  }
  local function blend_color(base, tint, amt)
    return {
      base[1] + (tint[1] - base[1]) * amt,
      base[2] + (tint[2] - base[2]) * amt,
      base[3] + (tint[3] - base[3]) * amt,
    }
  end

  local function draw_season_segment(start_doy, end_doy, label)
    if not start_doy or not end_doy then return end
    local a_start = day_angle(start_doy) + (gap_ang / 2)
    local a_end = day_angle(end_doy) - (gap_ang / 2)
    if a_end ~= a_start then
      local tint = season_tints[label]
      local seg_col = s_col
      if season_tint_enabled and tint then
        seg_col = blend_color(s_col, tint, season_tint_amt)
      end
      set_rgba(cr, seg_col, s_alpha)
      draw_arc_segment(a_start, a_end, s_r)
      local a_end_adj = a_end
      if a_end_adj < a_start then
        a_end_adj = a_end_adj + (2 * math.pi)
      end
      local a_mid = a_start + ((a_end_adj - a_start) / 2)
      draw_text_arc(cr, cx, cy, s_text_r, a_mid, label, s_font, s_text_size, s_text_col, s_text_alpha)
    end
  end

  draw_season_segment(winter_doy, spring_doy, "WINTER")
  draw_season_segment(spring_doy, summer_doy, "SPRING")
  draw_season_segment(summer_doy, autumn_doy, "SUMMER")
  draw_season_segment(autumn_doy, winter_doy, "AUTUMN")

  local months = (type(c.months) == "table") and c.months or {}
  local m_gap = scale(tonumber(months.gap_px) or 15)

  local dst = (type(c.dst) == "table") and c.dst or {}
  local dst_start = day_of_year_for_date(seasonal.DST_START_DATE, year)
  local dst_end = day_of_year_for_date(seasonal.DST_END_DATE, year)
  if (dst_start == nil) or (dst_end == nil) then
    local vars_path = SUITE_DIR .. "/config/owm.vars"
    local owm = parse_vars_file(vars_path)
    dst_start = dst_start or day_of_year_for_date(owm.DST_START_DATE, year)
    dst_end = dst_end or day_of_year_for_date(owm.DST_END_DATE, year)
  end
  if (dst_start == nil) or (dst_end == nil) then
    -- Fallback to local DST transitions if cache is missing/stale.
    local ds, de = dst_dates_local(year)
    dst_start = dst_start or day_of_year_for_date(ymd_string(ds), year)
    dst_end = dst_end or day_of_year_for_date(ymd_string(de), year)
  end
  if dst.enabled ~= false and dst_start and dst_end then
    local dst_stroke = scale(tonumber(dst.stroke) or 4.0)
    local dst_r = s_r + (s_stroke / 2) + (m_gap / 2) + scale(tonumber(dst.r_offset) or 0)
    local dst_col = dst.color or { 1.00, 1.00, 1.00 }
    local dst_alpha = tonumber(dst.alpha) or 0.80

    set_rgba(cr, dst_col, dst_alpha)
    cairo_set_line_width(cr, dst_stroke)
    draw_arc_segment(day_angle(dst_start), day_angle(dst_end), dst_r)
  end

  if months.enabled ~= false then
    local m_stroke = scale(tonumber(months.stroke) or 46.0)
    local m_r = s_r + (s_stroke / 2) + m_gap + (m_stroke / 2) + scale(tonumber(months.r_offset) or 0)
    local m_col = months.color
    if m_col == nil or m_col == "volvelle" then
      m_col = v.color or { 0.20, 0.20, 0.20 }
    end
    local m_alpha = months.alpha
    if m_alpha == nil or m_alpha == "volvelle" then
      m_alpha = v.alpha or 0.35
    end
    local m_text_col = months.text_color or { 0.70, 0.70, 0.70 }
    local m_text_alpha = tonumber(months.text_alpha) or 0.70
    local m_text_size = scale(tonumber(months.text_size) or 16)
    local m_text_r = m_r + scale(tonumber(months.text_r_offset) or 0)
    local m_font = months.font
    if m_font == nil or m_font == "" or m_font == "auto" then
      m_font = (t.fonts and t.fonts.title) or "Rajdhani Medium"
    end

    -- Outer days ring (12 segments) + day ticks (360)
    if days.enabled ~= false then
      local o_stroke = scale(tonumber(days.ring_stroke) or 25)
      local o_gap = scale(tonumber(days.ring_gap_px) or 6)
      local o_r = m_r + (m_stroke / 2) + o_gap + (o_stroke / 2) + scale(tonumber(days.ring_r_offset) or 0)
      local o_col = days.ring_color or ((t.palette and t.palette.white) or { 1.00, 1.00, 1.00 })
      local o_alpha = tonumber(days.ring_alpha) or 0.80

      -- subtle inner/outer shadow around the days ring
      do
        local shadow_col = (t.palette and t.palette.black) or { 0.00, 0.00, 0.00 }
        draw_ring(cr, cx, cy, o_r + scale(6.0), scale(10.0), shadow_col, 0.22)
        draw_ring(cr, cx, cy, o_r + scale(10.0), scale(14.0), shadow_col, 0.16)
        draw_ring(cr, cx, cy, o_r + scale(14.0), scale(18.0), shadow_col, 0.11)
        draw_ring(cr, cx, cy, o_r + scale(18.0), scale(24.0), shadow_col, 0.07)
        draw_ring(cr, cx, cy, o_r - scale(6.0), scale(10.0), shadow_col, 0.22)
        draw_ring(cr, cx, cy, o_r - scale(10.0), scale(14.0), shadow_col, 0.16)
        draw_ring(cr, cx, cy, o_r - scale(14.0), scale(18.0), shadow_col, 0.11)
        draw_ring(cr, cx, cy, o_r - scale(18.0), scale(24.0), shadow_col, 0.07)
      end

      set_rgba(cr, o_col, o_alpha)
      cairo_set_line_width(cr, o_stroke)
      local o_gap_ang = (o_r > 0) and (o_gap / o_r) or 0
      for i = 0, 11 do
        local a_start = (i / 12) * 2 * math.pi - math.pi / 2 + rot_days + (o_gap_ang / 2)
        local a_end = ((i + 1) / 12) * 2 * math.pi - math.pi / 2 + rot_days - (o_gap_ang / 2)
        if a_end ~= a_start then
          draw_arc_segment(a_start, a_end, o_r)
        end
      end

      -- Title label above the ring apex
      do
        local title_font = (t.fonts and t.fonts.title) or "Rajdhani Medium"
        local title_size = scale(tonumber(c.title_size) or 20)
        local title_col = (t.palette and t.palette.black) or { 0.00, 0.00, 0.00 }
        local title_alpha = tonumber(c.title_alpha) or 1.00
        local title_x = cx + scale(tonumber(c.title_x_offset) or 0)
        local title_y = cy - (o_r + (o_stroke / 2) + title_size) + scale(tonumber(c.title_y_offset) or 0)
        draw_text_center(cr, title_x, title_y, "CALENDAR", title_font, title_size, title_col, title_alpha)
      end

      local d_len = scale(tonumber(days.tick_len) or 6)
      local d_width = scale(tonumber(days.tick_width) or 1.5)
      local d_col = days.tick_color or days.color or { 0.50, 0.50, 0.50 }
      local d_alpha = tonumber(days.tick_alpha) or tonumber(days.alpha) or 0.50
      local d_outer = o_r - (o_stroke / 4) + scale(tonumber(days.tick_r_offset) or tonumber(days.r_offset) or 0)
      local d_today_col = (t.palette and t.palette.accent and t.palette.accent.maroon) or d_col

      cairo_set_line_width(cr, d_width)
      for i = 0, 359 do
        local a = (i / 360) * 2 * math.pi - math.pi / 2 + rot_days
        if i == today_tick then
          set_rgba(cr, d_today_col, 1.00)
        else
          set_rgba(cr, d_col, d_alpha)
        end
        local x1, y1 = polar(cx, cy, d_outer - d_len, a)
        local x2, y2 = polar(cx, cy, d_outer, a)
        cairo_move_to(cr, x1, y1)
        cairo_line_to(cr, x2, y2)
        cairo_stroke(cr)
      end

      -- Date strip (Month / Day / Year boxes above days ring)
      do
        local strip = (type(c.date_strip) == "table") and c.date_strip or {}
        if strip.enabled ~= false then
          local gap = scale(tonumber(strip.gap) or 8)
          local box_h = scale(tonumber(strip.box_h) or 26)
          local w_month = scale(tonumber(strip.month_w) or 46)
          local w_day = scale(tonumber(strip.day_w) or 32)
          local w_year = scale(tonumber(strip.year_w) or 54)
          local dow_gap = scale(tonumber(strip.dow_gap) or 6)
          local dow_box_h = scale(tonumber(strip.dow_box_h) or box_h)
          local dow_box_w = scale(tonumber(strip.dow_box_w) or 120)
          local r_offset = scale(tonumber(strip.r_offset) or 16)
          local strip_r = o_r + (o_stroke / 2) + r_offset + (box_h / 2)
          local strip_y = cy - strip_r
          local total_w = w_month + w_day + w_year + (gap * 2)
          local left = cx - (total_w / 2)

          local font = strip.font
          if font == nil or font == "" or font == "auto" then
            font = (t.fonts and (t.fonts.value_c or t.fonts.value)) or "Exo 2"
          end
          local text_size = scale(tonumber(strip.text_size) or 16)
          local dow_text_size = scale(tonumber(strip.dow_text_size) or text_size)
          local text_col = strip.text_color or { 0.90, 0.90, 0.90 }
          local text_alpha = tonumber(strip.text_alpha) or 0.95
          local box_alpha = tonumber(strip.box_alpha) or 0.90
          local dow_box_col = strip.dow_box_color or { 0.21, 0.21, 0.21 }
          local col_month = strip.box_color_month or { 0.20, 0.20, 0.20 }
          local col_day = strip.box_color_day or { 0.22, 0.22, 0.22 }
          local col_year = strip.box_color_year or { 0.18, 0.18, 0.18 }

          local month_txt = os.date("%b", now)
          local day_txt = os.date("%d", now)
          local year_txt = os.date("%Y", now)
          local dow_txt = os.date("%A", now)

          local function draw_box(cx_box, cy_box, w_box, h_box, col)
            set_rgba(cr, col, box_alpha)
            cairo_rectangle(cr, cx_box - (w_box / 2), cy_box - (h_box / 2), w_box, h_box)
            cairo_fill(cr)
          end

          local month_x = left + (w_month / 2)
          local day_x = month_x + (w_month / 2) + gap + (w_day / 2)
          local year_x = day_x + (w_day / 2) + gap + (w_year / 2)

          draw_box(month_x, strip_y, w_month, box_h, col_month)
          draw_box(day_x, strip_y, w_day, box_h, col_day)
          draw_box(year_x, strip_y, w_year, box_h, col_year)

          draw_text_center(cr, month_x, strip_y, month_txt, font, text_size, text_col, text_alpha)
          draw_text_center(cr, day_x, strip_y, day_txt, font, text_size, text_col, text_alpha)
          draw_text_center(cr, year_x, strip_y, year_txt, font, text_size, text_col, text_alpha)

          if strip.dow_enabled ~= false then
            local dow_y = strip_y - (box_h / 2) - dow_gap - (dow_box_h / 2)
            draw_box(cx, dow_y, dow_box_w, dow_box_h, dow_box_col)
            draw_text_center(cr, cx, dow_y, dow_txt, font, dow_text_size, text_col, text_alpha)
          end
        end
      end
    end

    set_rgba(cr, m_col, m_alpha)
    cairo_set_line_width(cr, m_stroke)
    local m_gap_ang = (m_r > 0) and (m_gap / m_r) or 0
    for i = 0, 11 do
      local a_start = (i / 12) * 2 * math.pi - math.pi / 2 + rot_months + (m_gap_ang / 2)
      local a_end = ((i + 1) / 12) * 2 * math.pi - math.pi / 2 + rot_months - (m_gap_ang / 2)
      if a_end ~= a_start then
        draw_arc_segment(a_start, a_end, m_r)
      end
    end

    local month_labels = {
      "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
      "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
    }
    for i = 0, 11 do
      local a_mid = ((i + 0.5) / 12) * 2 * math.pi - math.pi / 2 + rot_months
      local txt = month_labels[i + 1]
      local col = m_text_col
      local alpha = m_text_alpha
      if now_t and (i + 1) == now_t.month then
        col = months.current_text_color or (t.palette and t.palette.accent and t.palette.accent.orange) or m_text_col
        alpha = tonumber(months.current_text_alpha) or m_text_alpha
      end
      draw_text_arc(cr, cx, cy, m_text_r, a_mid, txt, m_font, m_text_size, col, alpha)
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

---@diagnostic disable-next-line: lowercase-global
function conky_draw_calendar_ring()
  if conky_window == nil then return end
  local ok, err = pcall(draw_calendar_ring_impl)
  if not ok then
    print("calendar error: " .. tostring(err))
  end
end
