--[[
  ${CONKY_SUITE_DIR}/lua/widgets/marquee_calendar.lua
  Calendar marquee arc (static placeholder).
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
local draw_text_center_rotated = util.draw_text_center_rotated
local draw_text_left = util.draw_text_left
local read_file = util.read_file
local parse_vars_file = util.parse_vars_file

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

local function read_sun_times()
  local j = read_file(owm_daily_cache_path())
  local sr = read_json_num_first(j, "sunrise")
  local ss = read_json_num_first(j, "sunset")
  if not sr or not ss then
    j = read_file(CACHE_DIR .. "/owm_current.json")
    sr = read_json_num_first(j, "sunrise")
    ss = read_json_num_first(j, "sunset")
  end
  return sr, ss
end

local function event_cache_path(m)
  local cache
  local en = (type(m) == "table") and m.event_notes or nil
  if type(en) == "table" then
    cache = en.cache_file
    if cache == "auto" then cache = nil end
  end
  if not cache or cache == "" then
    local vars_path = SUITE_DIR .. "/config/owm.vars"
    local v = parse_vars_file(vars_path)
    cache = v.EVENT_CACHE or v.EVENTS_CACHE
  end
  if not cache or cache == "" then
    cache = CACHE_DIR .. "/events_cache.txt"
  end
  return cache
end

local function read_event_cache(m)
  local path = event_cache_path(m)
  local s = read_file(path)
  if not s then return {} end
  local out = {}
  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local date, name, etype = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if not date then
        date, name = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s*|%s*(.-)%s*$")
      end
      if date and name and name ~= "" then
        local y, mth, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        local y_num = tonumber(y)
        local m_num = tonumber(mth)
        local d_num = tonumber(d)
        if y_num and m_num and d_num then
          out[#out + 1] = {
            date = date,
            name = name,
            etype = etype,
            y = y_num,
            m = m_num,
            d = d_num,
          }
        end
      end
    end
  end
  return out
end

local function deg2rad(d)
  return d * math.pi / 180
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function draw_calendar_marquee_impl()
  if conky_window == nil then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local t = get_theme()
  local palette = (type(t.palette) == "table") and t.palette or {}
  local gray = (type(palette.gray) == "table") and palette.gray or {}

  local cx, cy = w / 2, h / 2
  local r_clock = math.min(w, h) * (tonumber(t.clock_r_factor) or 0.17)

  local m = (type(t.calendar_marquee) == "table") and t.calendar_marquee or {}
  local function mval(k, default)
    local v = m[k]
    if v ~= nil then return v end
    return default
  end

  local arc_left_fallback = tonumber(m.arc_left_deg) or 130
  local arc_right_fallback = tonumber(m.arc_right_deg) or 50
  local arc_center = tonumber(m.arc_center_deg)
  if arc_center == nil then
    arc_center = (arc_left_fallback + arc_right_fallback) / 2
  end
  local arc_span = tonumber(m.arc_span_deg)
  if arc_span == nil then
    arc_span = arc_left_fallback - arc_right_fallback
  end
  if arc_span < 0 then arc_span = -arc_span end
  local arc_left_deg = arc_center + (arc_span / 2)
  local arc_right_deg = arc_center - (arc_span / 2)

  local arc_cx = cx + scale(mval("center_x_offset", 0))
  local arc_cy = cy + scale(mval("center_y_offset", 0))

  local marquee = {
    r = r_clock + scale(mval("r_offset", 190)),
    arc_left_deg = arc_left_deg,
    arc_right_deg = arc_right_deg,
    arc_width = scale(mval("arc_width", 1.0)),
    arc_alpha = mval("arc_alpha", 0.20),
    tick_len = scale(mval("tick_len", 10)),
    tick_len_apex = scale(mval("tick_len_apex", 16)),
    tick_width = scale(mval("tick_width", 1.5)),
    tick_width_apex = scale(mval("tick_width_apex", 2.0)),
    tick_alpha = mval("tick_alpha", 0.70),
    dow_offset = scale(mval("dow_offset", 12)),
    dom_offset = scale(mval("dom_offset", 20)),
    font_dow = scale(mval("font_dow", 10)),
    font_dom = scale(mval("font_dom", 10)),
    font_dow_apex = scale(mval("font_dow_apex", 12)),
    font_dom_apex = scale(mval("font_dom_apex", 12)),
    chevron_w = scale(mval("chevron_w", 12)),
    chevron_h = scale(mval("chevron_h", 9)),
    chevron_offset = scale(mval("chevron_offset", 30)),
    year_offset = scale(mval("year_offset", 20)),
    font_year = scale(mval("font_year", 14)),
    title_y_offset = scale(mval("title_y_offset", 46)),
    title_size = scale(mval("title_size", 16)),
    title_text = mval("title_text", "CALENDAR"),
    title_alpha = mval("title_alpha", 0.80),
    draw_title = mval("draw_title", false),
    bracket_short = scale(mval("bracket_short", 30)),
    bracket_diag_dx = scale(mval("bracket_diag_dx", 18)),
    bracket_diag_dy = scale(mval("bracket_diag_dy", 18)),
    bracket_long_pad = scale(mval("bracket_long_pad", 30)),
    bracket_vert = scale(mval("bracket_vert", 200)),
    bracket_width = scale(mval("bracket_width", 1.5)),
    bracket_alpha = mval("bracket_alpha", 0.80),
    year = mval("year", 2026),
    apex_index = tonumber(mval("apex_index", 16)) or 16,
  }

  local font_title = mval("font_title", "auto")
  if font_title == "auto" then
    font_title = (t.fonts and t.fonts.title) or "Rajdhani"
  end

  local font_text = mval("font_text", "auto")
  if font_text == "auto" then
    font_text = (t.fonts and t.fonts.label) or font_title
  end

  local col_tick = m.color_tick or gray.g70 or { 0.70, 0.70, 0.70 }
  local col_text = m.color_text or gray.g60 or { 0.60, 0.60, 0.60 }
  local col_weekend = m.color_weekend or palette.black or { 0.00, 0.00, 0.00 }
  local col_year = m.color_year or gray.g40 or { 0.40, 0.40, 0.40 }
  local col_apex_tick = m.color_apex_tick or (palette.accent and palette.accent.maroon) or { 0.40, 0.08, 0.12 }
  local col_apex_day = m.color_apex_day or palette.black or { 0.00, 0.00, 0.00 }
  local col_apex_date = m.color_apex_date or palette.white or { 1.00, 1.00, 1.00 }
  local col_bracket = m.color_bracket or palette.white or { 1.00, 1.00, 1.00 }
  local col_title = m.color_title or col_bracket
  local col_chevron = m.color_chevron or palette.white or { 1.00, 1.00, 1.00 }
  local col_sun_text = m.color_sun_text or gray.g70 or { 0.70, 0.70, 0.70 }
  local col_event_date = m.color_event_date or col_apex_tick

  local en = (type(m.event_notes) == "table") and m.event_notes or {}
  local event_left_lines = {}
  local event_right_lines = {}
  local event_dates = {}
  do
    if en.enabled ~= false then
      local window_days = tonumber(en.window_days) or 7
      if window_days < 0 then window_days = -window_days end
      local switch_hour = tonumber(en.switch_hour) or 12
      local max_left = tonumber(en.max_lines_left) or 0
      local max_right = tonumber(en.max_lines_right) or 0
      local now = os.time()
      local window_sec = window_days * 86400
      local left = {}
      local right = {}
      local events = read_event_cache(m)
      for _, e in ipairs(events) do
        if e.y and e.m and e.d then
          local ts = os.time({ year = e.y, month = e.m, day = e.d, hour = switch_hour })
          if ts then
            if now >= (ts - window_sec) and now <= (ts + window_sec) then
              event_dates[e.date] = true
              if now < ts then
                right[#right + 1] = { ts = ts, name = e.name }
              else
                left[#left + 1] = { ts = ts, name = e.name }
              end
            end
          end
        end
      end
      table.sort(right, function(a, b) return a.ts < b.ts end)
      table.sort(left, function(a, b) return a.ts > b.ts end)
      for _, e in ipairs(left) do
        event_left_lines[#event_left_lines + 1] = e.name
      end
      for _, e in ipairs(right) do
        event_right_lines[#event_right_lines + 1] = e.name
      end
      if max_left > 0 and #event_left_lines > max_left then
        while #event_left_lines > max_left do
          table.remove(event_left_lines)
        end
      end
      if max_right > 0 and #event_right_lines > max_right then
        while #event_right_lines > max_right do
          table.remove(event_right_lines)
        end
      end
    end
  end

  local apex_angle = deg2rad((marquee.arc_left_deg + marquee.arc_right_deg) / 2)
  local title_x = arc_cx
  local arc_top_y = arc_cy - marquee.r
  local title_y = arc_top_y + marquee.title_y_offset
  local bracket_y = arc_top_y + scale(mval("bracket_y_offset", 0))
  local title_txt = tostring(marquee.title_text or "CALENDAR")

  if marquee.draw_title then
    draw_text_center(cr, title_x, title_y, title_txt, font_title, marquee.title_size, col_title, marquee.title_alpha)
  end

  do
    local ext = cairo_text_extents_t:create()
    cairo_select_font_face(cr, font_title, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, marquee.title_size)
    cairo_text_extents(cr, title_txt, ext)

    local title_left = title_x - (ext.width / 2 + ext.x_bearing)
    local title_right = title_left + ext.width

    local arc_left_x = arc_cx + marquee.r * math.cos(deg2rad(marquee.arc_left_deg))
    local arc_right_x = arc_cx + marquee.r * math.cos(deg2rad(marquee.arc_right_deg))

    local short = marquee.bracket_short
    local diag_scale = tonumber(mval("bracket_diag_scale", 1.0)) or 1.0
    local diag_dx = marquee.bracket_diag_dx * diag_scale
    local diag_dy = marquee.bracket_diag_dy * diag_scale
    local long_y = bracket_y - diag_dy
    local long_len = scale(mval("bracket_long_len", 0))

    set_rgba(cr, col_bracket, marquee.bracket_alpha)
    cairo_set_line_width(cr, marquee.bracket_width)

    local bracket_side_gap = scale(mval("bracket_side_gap", 10))
    local left_start = title_left - bracket_side_gap
    local left_short_end = left_start - short
    local left_diag_end_x = left_short_end - diag_dx
    local left_diag_end_y = long_y
    local left_long_end_x
    if long_len > 0 then
      left_long_end_x = left_diag_end_x - long_len
    else
      left_long_end_x = math.min(left_diag_end_x - scale(10), arc_left_x - marquee.bracket_long_pad)
    end

    cairo_move_to(cr, left_start, bracket_y)
    cairo_line_to(cr, left_short_end, bracket_y)
    cairo_line_to(cr, left_diag_end_x, left_diag_end_y)
    cairo_line_to(cr, left_long_end_x, left_diag_end_y)
    cairo_line_to(cr, left_long_end_x, left_diag_end_y - marquee.bracket_vert)
    cairo_stroke(cr)

    local right_start = title_right + bracket_side_gap
    local right_short_end = right_start + short
    local right_diag_end_x = right_short_end + diag_dx
    local right_diag_end_y = long_y
    local right_long_end_x
    if long_len > 0 then
      right_long_end_x = right_diag_end_x + long_len
    else
      right_long_end_x = math.max(right_diag_end_x + scale(10), arc_right_x + marquee.bracket_long_pad)
    end

    cairo_move_to(cr, right_start, bracket_y)
    cairo_line_to(cr, right_short_end, bracket_y)
    cairo_line_to(cr, right_diag_end_x, right_diag_end_y)
    cairo_line_to(cr, right_long_end_x, right_diag_end_y)
    cairo_line_to(cr, right_long_end_x, right_diag_end_y - marquee.bracket_vert)
    cairo_stroke(cr)

    if en.enabled ~= false then
      local en_font = en.font or font_text
      if en_font == "auto" then en_font = font_text end
      local en_size = scale(tonumber(en.text_size) or 12)
      local en_col = en.color or col_text
      local en_alpha = tonumber(en.alpha) or 0.85
      local en_gap = scale(tonumber(en.line_gap) or 0)
      local en_y = long_y - scale(tonumber(en.y_offset) or 0)
      local en_pad = scale(tonumber(en.x_pad) or 0)
      local bullet_r = scale(tonumber(en.bullet_radius) or 0)
      local bullet_gap = scale(tonumber(en.bullet_gap) or 0)
      local bullet_col = en.bullet_color or (palette.accent and palette.accent.maroon) or col_apex_tick
      local bullet_alpha = tonumber(en.bullet_alpha) or en_alpha
      local en_y_offset = 0
      do
        if type(en_font) == "string" then
          local family = en_font
          local colon = family:find(":")
          if colon then family = family:sub(1, colon - 1) end
          family = family:gsub("^%s+", ""):gsub("%s+$", "")
          local profile = t.font_profiles and t.font_profiles[family]
          local offset = profile and tonumber(profile.y_offset)
          if offset and offset ~= 0 then
            en_y_offset = scale(offset)
          end
        end
      end

      local function to_lines(v)
        if v == nil then return {} end
        if type(v) == "table" then return v end
        local out = {}
        for line in tostring(v):gmatch("[^\r\n]+") do
          if line ~= "" then
            out[#out + 1] = line
          end
        end
        return out
      end

      local function draw_bullet(x, y)
        if bullet_r <= 0 then return end
        set_rgba(cr, bullet_col, bullet_alpha)
        cairo_arc(cr, x, y, bullet_r, 0, math.pi * 2)
        cairo_fill(cr)
      end

      local en_step = en_size + en_gap

      local function stack_top(y, lines)
        local count = #lines
        if count <= 1 then return y end
        return y - ((count - 1) * en_step)
      end

      local function draw_lines_left(x, y, lines)
        cairo_select_font_face(cr, en_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, en_size)
        for i, line in ipairs(lines) do
          if line ~= "" then
            local y_line = y + ((i - 1) * en_step)
            local ext = cairo_text_extents_t:create()
            cairo_text_extents(cr, line, ext)
            if bullet_r > 0 then
              local bullet_y = y_line + en_y_offset + ext.y_bearing + (ext.height / 2)
              local bullet_x = x - bullet_gap - bullet_r
              draw_bullet(bullet_x, bullet_y)
            end
            draw_text_left(cr, x, y_line, line, en_font, en_size, en_col, en_alpha)
          end
        end
      end

      local function draw_lines_right(x_right, y, lines)
        cairo_select_font_face(cr, en_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, en_size)
        for i, line in ipairs(lines) do
          if line ~= "" then
            local ext = cairo_text_extents_t:create()
            cairo_text_extents(cr, line, ext)
            local x = x_right - (ext.width + ext.x_bearing)
            local y_line = y + ((i - 1) * en_step)
            if bullet_r > 0 then
              local bullet_y = y_line + en_y_offset + ext.y_bearing + (ext.height / 2)
              local bullet_x = x_right + bullet_gap + bullet_r
              draw_bullet(bullet_x, bullet_y)
            end
            draw_text_left(cr, x, y_line, line, en_font, en_size, en_col, en_alpha)
          end
        end
      end

      local left_lines = event_left_lines
      local right_lines = event_right_lines
      if #left_lines == 0 and #right_lines == 0 then
        left_lines = to_lines(en.left_lines)
        right_lines = to_lines(en.right_lines)
      end
      if #left_lines > 0 then
        draw_lines_right(left_diag_end_x - en_pad, stack_top(en_y, left_lines), left_lines)
      end
      if #right_lines > 0 then
        draw_lines_left(right_diag_end_x + en_pad, stack_top(en_y, right_lines), right_lines)
      end
    end

    local sr, ss = read_sun_times()
    local sun_y = bracket_y + scale(mval("sun_text_y_offset", 16))
    local sun_x_offset = scale(mval("sun_text_x_offset", 0))
    local sun_size = scale(mval("sun_text_size", 16))
    local sun_alpha = mval("sun_text_alpha", 0.85)
    if ss then
      local ss_txt = "SS " .. os.date("%H:%M", ss)
      draw_text_center(cr, left_short_end - sun_x_offset, sun_y, ss_txt, font_text, sun_size, col_sun_text, sun_alpha)
    end
    if sr then
      local sr_txt = "SR " .. os.date("%H:%M", sr)
      draw_text_center(cr, right_short_end + sun_x_offset, sun_y, sr_txt, font_text, sun_size, col_sun_text, sun_alpha)
    end
  end

  if marquee.arc_alpha > 0 then
    set_rgba(cr, col_tick, marquee.arc_alpha)
    cairo_set_line_width(cr, marquee.arc_width)
    cairo_arc_negative(cr, arc_cx, arc_cy, marquee.r, deg2rad(marquee.arc_left_deg), deg2rad(marquee.arc_right_deg))
    cairo_stroke(cr)
  end

  local count = 31
  local now_t = os.date("*t")
  local base_time = os.time({
    year = now_t.year,
    month = now_t.month,
    day = now_t.day,
    hour = 12,
  })
  local dow_letters = { "S", "M", "T", "W", "T", "F", "S" }
  for i = 1, count do
    local offset_days = i - marquee.apex_index
    local dt = os.date("*t", base_time + (offset_days * 86400))
    local tpos = (i - 1) / (count - 1)
    local ang_deg = lerp(marquee.arc_left_deg, marquee.arc_right_deg, tpos)
    local ang = deg2rad(ang_deg)
    local is_apex = (i == marquee.apex_index)
    local dow = dow_letters[dt.wday or 1] or "?"
    local is_weekend = (dt.wday == 1 or dt.wday == 7)

    local tick_len = is_apex and marquee.tick_len_apex or marquee.tick_len
    local tick_w = is_apex and marquee.tick_width_apex or marquee.tick_width
    local tick_col = is_apex and col_apex_tick or (is_weekend and col_weekend or col_tick)
    local tick_alpha = is_apex and 1.00 or marquee.tick_alpha

    set_rgba(cr, tick_col, tick_alpha)
    cairo_set_line_width(cr, tick_w)
    local x1 = arc_cx + marquee.r * math.cos(ang)
    local y1 = arc_cy - marquee.r * math.sin(ang)
    local x2 = arc_cx + (marquee.r - tick_len) * math.cos(ang)
    local y2 = arc_cy - (marquee.r - tick_len) * math.sin(ang)
    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)

    local dow_r = marquee.r + marquee.dow_offset
    local dom_r = marquee.r - marquee.dom_offset
    local dow_size = is_apex and marquee.font_dow_apex or marquee.font_dow
    local dom_size = is_apex and marquee.font_dom_apex or marquee.font_dom
    local date_key = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
    local is_event = event_dates[date_key] == true
    local dow_col = is_apex and col_apex_day or (is_weekend and col_weekend or col_text)
    local dom_col = is_event and col_event_date or (is_apex and col_apex_date or (is_weekend and col_weekend or col_text))

    local dow_x = arc_cx + dow_r * math.cos(ang)
    local dow_y = arc_cy - dow_r * math.sin(ang)
    draw_text_center_rotated(cr, dow_x, dow_y, dow, font_text, dow_size, dow_col, 0.95, -ang + math.pi / 2)

    local dom_x = arc_cx + dom_r * math.cos(ang)
    local dom_y = arc_cy - dom_r * math.sin(ang)
    local dom_txt = string.format("%02d", dt.day or i)
    draw_text_center_rotated(cr, dom_x, dom_y, dom_txt, font_text, dom_size, dom_col, 0.95, -ang + math.pi / 2)
  end

  do
    local cx_chev = arc_cx + (marquee.r - marquee.chevron_offset) * math.cos(apex_angle)
    local cy_chev = arc_cy - (marquee.r - marquee.chevron_offset) * math.sin(apex_angle)
    local half_w = marquee.chevron_w / 2
    local half_h = marquee.chevron_h / 2

    set_rgba(cr, col_chevron, 1.00)
    cairo_move_to(cr, cx_chev, cy_chev - half_h)
    cairo_line_to(cr, cx_chev - half_w, cy_chev + half_h)
    cairo_line_to(cr, cx_chev + half_w, cy_chev + half_h)
    cairo_close_path(cr)
    cairo_fill(cr)

    local year_r = marquee.r - marquee.chevron_offset - marquee.year_offset
    local year_x = arc_cx + year_r * math.cos(apex_angle)
    local year_y = arc_cy - year_r * math.sin(apex_angle)
    draw_text_center(cr, year_x, year_y, tostring(marquee.year), font_title, marquee.font_year, col_year, 0.90)
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_draw_calendar_marquee()
  if conky_window == nil then return end
  local ok, err = pcall(draw_calendar_marquee_impl)
  if not ok then
    print("calendar marquee error: " .. tostring(err))
  end
end
