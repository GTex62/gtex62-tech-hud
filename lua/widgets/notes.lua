--[[
  ${CONKY_SUITE_DIR}/lua/widgets/notes.lua
  Notes panel background.

  Exposes:
    function conky_draw_notes_panel()
]]

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local scale = util.scale

pcall(require, "cairo")

local function pick(v, fallback)
  if v ~= nil then return v end
  return fallback
end

local function s(v, fallback)
  if v == nil then return fallback end
  local n = tonumber(v)
  if n == nil then return fallback end
  return scale(n)
end

local function draw_round_rect(cr, x, y, w, h, r)
  local radius = math.max(0, math.min(r or 0, math.min(w, h) / 2))
  if radius <= 0 then
    cairo_rectangle(cr, x, y, w, h)
    return
  end
  cairo_new_sub_path(cr)
  cairo_arc(cr, x + w - radius, y + radius, radius, -math.pi / 2, 0)
  cairo_arc(cr, x + w - radius, y + h - radius, radius, 0, math.pi / 2)
  cairo_arc(cr, x + radius, y + h - radius, radius, math.pi / 2, math.pi)
  cairo_arc(cr, x + radius, y + radius, radius, math.pi, math.pi * 1.5)
  cairo_close_path(cr)
end

local SEASON_CACHE = { ts = 0, label = nil }

local function seasonal_cache_path()
  local vars_path = SUITE_DIR .. "/config/owm.vars"
  local v = (util.parse_vars_file and util.parse_vars_file(vars_path)) or {}
  local cache = v.SEASONAL_CACHE
  if not cache or cache == "" then
    cache = CACHE_DIR .. "/seasonal.vars"
  end
  return cache
end

local function read_seasonal_vars()
  local out = {}
  local s = util.read_file and util.read_file(seasonal_cache_path())
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

local function draw_notes_bracket(cr, theme, notes, x0, y0, pw, ph)
  local b = notes.bracket or {}
  if b.enabled == false then return end

  local bx = x0 + s(b.x, 0)
  local by = y0 + s(b.y, 0)
  local flip_h = b.flip_h == true
  local flip_v = b.flip_v == true
  local dir_x = flip_h and -1 or 1
  local dir_y = flip_v and -1 or 1
  local short = s(b.short, 0) * dir_y
  local diag_dx = s(b.diag_dx, 0) * dir_x
  local diag_dy = s(b.diag_dy, 0) * dir_y
  local diag_scale = tonumber(b.diag_scale) or 1.0
  local diag_short = s(b.diag_short, 0) * dir_x
  local long_len_cfg = s(b.long_len, 0)
  local vert = s(b.vert, 0) * dir_x
  local width = s(b.width, scale(2.0))
  local alpha = tonumber(b.alpha) or 0.30
  local color = b.color or (theme.palette and theme.palette.white) or { 1.00, 1.00, 1.00 }
  local bottom_pad = s(b.bottom_pad, 0)

  local dx = diag_dx * diag_scale
  local dy = diag_dy * diag_scale
  local long_len
  if long_len_cfg <= 0 then
    local edge_space
    if dir_y > 0 then
      edge_space = ph - (by - y0) - bottom_pad
    else
      edge_space = (by - y0) - bottom_pad
    end
    local long_mag = edge_space - math.abs(short) - math.abs(dy)
    if long_mag < 0 then long_mag = 0 end
    long_len = long_mag * dir_y
  else
    long_len = long_len_cfg * dir_y
  end

  util.set_rgba(cr, color, alpha)
  cairo_set_line_width(cr, width)

  local long_x = bx + dx + diag_short
  cairo_move_to(cr, bx, by)
  cairo_line_to(cr, bx, by + short)
  cairo_line_to(cr, bx + dx, by + short + dy)
  cairo_line_to(cr, long_x, by + short + dy)
  cairo_line_to(cr, long_x, by + short + dy + long_len)
  cairo_line_to(cr, long_x + vert, by + short + dy + long_len)
  cairo_stroke(cr)
end

local function draw_notes_title(cr, theme, notes, x0, y0, pw, ph)
  local tcfg = notes.title or {}
  if tcfg.enabled == false then return end

  local text = tostring(tcfg.text or "NOTES")
  if text == "" then return end

  local font = tcfg.font
  if font == nil or font == "" or font == "auto" then
    font = (theme.fonts and theme.fonts.title) or "Sans"
  end
  local size = s(tcfg.size, scale(24))
  local alpha = tonumber(tcfg.alpha) or 0.75
  local color = tcfg.color or (theme.palette and theme.palette.black) or { 0.00, 0.00, 0.00 }
  local x = x0 + s(tcfg.x, 0)
  local y = y0 + s(tcfg.y, (ph / 2))
  local rot = tonumber(tcfg.rot_deg) or 180

  util.draw_text_center_rotated(cr, x, y, text, font, size, color, alpha, math.rad(rot))
end

function conky_draw_notes_panel()
  if conky_window == nil then return end
  local w = conky_window.width or 0
  local h = conky_window.height or 0
  if w <= 0 or h <= 0 then return end

  local theme = util.get_theme()
  local notes = theme.notes or {}
  local panel = notes.panel or {}
  if notes.enabled == false then return end

  local sys = (theme.system and theme.system.circle) or {}
  local sys_outer = (theme.system and theme.system.circle_outer) or {}
  local net = (theme.network and theme.network.circle) or {}
  local net_outer = (theme.network and theme.network.circle_outer) or {}

  local pad_x = s(panel.padding_x, scale(10))
  local pad_y = s(panel.padding_y, scale(8))

  local x0 = s(panel.offset_x, 0)
  local y0 = s(panel.offset_y, 0)
  local pw = panel.width
  local ph = panel.height

  if pw == nil then
    x0 = x0 + pad_x
    pw = w - (pad_x * 2)
  end
  if ph == nil then
    y0 = y0 + pad_y
    ph = h - (pad_y * 2)
  end
  if pw ~= nil then pw = s(pw, 0) end
  if ph ~= nil then ph = s(ph, 0) end

  if pw <= 0 or ph <= 0 then return end

  local radius = s(panel.radius, scale(12))
  local fill_color = panel.fill_color or sys.fill_color or net.fill_color or { 0.30, 0.30, 0.30 }
  local fill_alpha = pick(panel.fill_alpha, sys.fill_alpha or net.fill_alpha or 0.65)
  if panel.season_tint_enable == true then
    local season_tints = {
      WINTER = { 0.20, 0.30, 0.45 }, -- blue
      SPRING = { 0.85, 0.80, 0.40 }, -- orange/yellow
      SUMMER = { 0.30, 0.55, 0.30 }, -- green
      AUTUMN = { 0.75, 0.35, 0.25 }, -- orange/red
    }
    local season = current_season_label()
    local tint = season_tints[season]
    local amt = tonumber(panel.season_tint_amount) or 0.06
    if tint and type(fill_color) == "table" then
      fill_color = blend_color(fill_color, tint, amt)
    end
  end
  local stroke_color = panel.stroke_color
    or sys_outer.stroke_color
    or net_outer.stroke_color
    or sys.stroke_color
    or net.stroke_color
    or { 1.00, 1.00, 1.00 }
  local stroke_alpha = pick(panel.stroke_alpha, sys_outer.stroke_alpha or net_outer.stroke_alpha or sys.stroke_alpha or net.stroke_alpha or 0.30)
  local stroke_width = s(panel.stroke_width, scale(2.0))
  local outer = panel.outer_stroke or {}

  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  if panel.enabled ~= false then
    draw_round_rect(cr, x0, y0, pw, ph, radius)
    util.set_rgba(cr, fill_color, fill_alpha)
    cairo_fill_preserve(cr)
    util.set_rgba(cr, stroke_color, stroke_alpha)
    cairo_set_line_width(cr, stroke_width)
    cairo_stroke(cr)

    if outer.enabled ~= false then
      local outer_offset = s(outer.offset, scale(4))
      local outer_width = s(outer.width, stroke_width)
      local outer_color = outer.color or sys_outer.stroke_color or net_outer.stroke_color or stroke_color
      local outer_alpha = pick(outer.alpha, sys_outer.stroke_alpha or net_outer.stroke_alpha or stroke_alpha)

      local ox = x0 - outer_offset
      local oy = y0 - outer_offset
      local ow = pw + (outer_offset * 2)
      local oh = ph + (outer_offset * 2)
      local orad = radius + outer_offset

      if outer_width > 0 and ow > 0 and oh > 0 then
        draw_round_rect(cr, ox, oy, ow, oh, orad)
        util.set_rgba(cr, outer_color, outer_alpha)
        cairo_set_line_width(cr, outer_width)
        cairo_stroke(cr)
      end
    end
  end

  draw_notes_bracket(cr, theme, notes, x0, y0, pw, ph)
  draw_notes_title(cr, theme, notes, x0, y0, pw, ph)

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
