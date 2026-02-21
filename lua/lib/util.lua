-- Shared theme/drawing helpers for widgets.
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local THEME = nil

local function theme_path()
  return SUITE_DIR .. "/theme.lua"
end

local function safe_dofile(path)
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" then return t end
  return {}
end

local function get_theme()
  if THEME ~= nil then return THEME end
  THEME = safe_dofile(theme_path())
  return THEME
end

local function scale(v)
  local t = get_theme()
  local s = tonumber(t.scale) or 1.0
  return v * s
end

local function layout_base_size(t, key, field, fallback)
  local L = t.layout or {}
  local size = (L.sizes or {})[key] or {}
  local v = size[field]
  if v == nil then v = fallback end
  return tonumber(v)
end

local function embedded_corner_offset(key)
  local t = get_theme()
  local emb = t.embedded_corners or {}
  local cfg = emb[key] or {}
  local anchor = cfg.anchor or emb.anchor
  local dx = tonumber(cfg.x) or 0
  local dy = tonumber(cfg.y) or 0
  if not anchor then
    return dx, dy
  end

  local time_w = layout_base_size(t, "time", "min_w", 1200) or 1200
  local time_h = layout_base_size(t, "time", "min_h", 1200) or 1200
  local w = layout_base_size(t, key, "min_w", 400) or 400
  local h = layout_base_size(t, key, "min_h", 400) or 400
  local mx = tonumber(cfg.margin_x or cfg.margin or emb.margin_x or emb.margin) or 0
  local my = tonumber(cfg.margin_y or cfg.margin or emb.margin_y or emb.margin) or 0
  local half_w = (time_w / 2) - (w / 2) - mx
  local half_h = (time_h / 2) - (h / 2) - my
  local ax = 0
  local ay = 0

  if anchor == "top_left" then
    ax, ay = -half_w, -half_h
  elseif anchor == "top_right" then
    ax, ay = half_w, -half_h
  elseif anchor == "bottom_left" then
    ax, ay = -half_w, half_h
  elseif anchor == "bottom_right" then
    ax, ay = half_w, half_h
  end

  return ax + dx, ay + dy
end

local function font_profile_for(font_face)
  if type(font_face) ~= "string" then return nil end
  local family = font_face
  local colon = family:find(":")
  if colon then family = family:sub(1, colon - 1) end
  family = family:gsub("^%s+", ""):gsub("%s+$", "")
  local t = get_theme()
  local profiles = t.font_profiles
  if type(profiles) ~= "table" then return nil end
  return profiles[family]
end

local function font_y_offset(font_face)
  local profile = font_profile_for(font_face)
  local offset = profile and tonumber(profile.y_offset)
  if not offset or offset == 0 then return 0 end
  return scale(offset)
end

local function font_size_scale(font_face)
  local profile = font_profile_for(font_face)
  local s = profile and tonumber(profile.size_scale)
  if not s or s == 0 then return 1.0 end
  return s
end

local function font_scaled_size(font_face, font_size)
  local size = tonumber(font_size) or 0
  return size * font_size_scale(font_face)
end

local function set_rgba(cr, c, a)
  if type(c) == "table" then
    local r = c[1] or 1
    local g = c[2] or 1
    local b = c[3] or 1
    local alpha = (a ~= nil) and a or (c[4] or 1)
    cairo_set_source_rgba(cr, r, g, b, alpha)
    return
  end
  cairo_set_source_rgba(cr, 1, 1, 1, a or 1)
end

local function hex_to_rgba(hex, a)
  if type(hex) == "table" then
    return hex[1] or 1, hex[2] or 1, hex[3] or 1, (a ~= nil and a or (hex[4] or 1))
  end
  if type(hex) ~= "string" then
    return 1, 1, 1, (a ~= nil and a or 1)
  end
  hex = hex:gsub("#", "")
  local r_ = tonumber(hex:sub(1, 2), 16) or 255
  local g_ = tonumber(hex:sub(3, 4), 16) or 255
  local b_ = tonumber(hex:sub(5, 6), 16) or 255
  return r_ / 255, g_ / 255, b_ / 255, (a ~= nil and a or 1)
end

local function draw_text_center(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(font_face)
  local size = font_scaled_size(font_face, font_size)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y)
  cairo_show_text(cr, txt)
end

local function draw_text_center_mid(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(font_face)
  local size = font_scaled_size(font_face, font_size)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, txt)
end

local function draw_text_center_rotated(cr, x, y, txt, font_face, font_size, col, alpha, rot)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(font_face)
  local size = font_scaled_size(font_face, font_size)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_save(cr)
  cairo_translate(cr, x, y)
  cairo_rotate(cr, rot)
  cairo_move_to(cr, -(ext.width / 2 + ext.x_bearing), ext.height / 2)
  cairo_show_text(cr, txt)
  cairo_restore(cr)
end

local function draw_text_center_fixed(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(font_face)
  local size = font_scaled_size(font_face, font_size)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)

  local ext_digit = cairo_text_extents_t:create()
  cairo_text_extents(cr, "8", ext_digit)
  local digit_w = ext_digit.x_advance

  local ext_colon = cairo_text_extents_t:create()
  cairo_text_extents(cr, ":", ext_colon)
  local colon_w = ext_colon.x_advance

  local total_w = 0
  for ch in txt:gmatch(".") do
    total_w = total_w + (ch == ":" and colon_w or digit_w)
  end

  local cursor_x = x - total_w / 2
  for ch in txt:gmatch(".") do
    local slot_w = (ch == ":" and colon_w or digit_w)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, ch, ext)
    local draw_x = cursor_x + (slot_w / 2) - (ext.width / 2 + ext.x_bearing)
    cairo_move_to(cr, draw_x, y)
    cairo_show_text(cr, ch)
    cursor_x = cursor_x + slot_w
  end
end

local function draw_text_left(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(font_face)
  local size = font_scaled_size(font_face, font_size)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, txt)
end

local function draw_text_block_left(cr, x, y, txt, font_face, font_size, col, alpha, line_gap)
  if txt == nil or txt == "" then return end
  local step = font_scaled_size(font_face, font_size) + (line_gap or 0)
  local i = 0
  for line in tostring(txt):gmatch("[^\r\n]+") do
    if line ~= "" then
      draw_text_left(cr, x, y + (i * step), line, font_face, font_size, col, alpha)
      i = i + 1
    end
  end
end

local function count_text_lines(txt)
  if txt == nil or txt == "" then return 0 end
  local n = 0
  for line in tostring(txt):gmatch("[^\r\n]+") do
    if line ~= "" then n = n + 1 end
  end
  return n
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close(); return true
  end
  return false
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function expand_vars(val)
  if type(val) ~= "string" then return val end
  local function get_var(k)
    if k == "CONKY_SUITE_DIR" then return SUITE_DIR end
    if k == "CONKY_CACHE_DIR" then return CACHE_DIR end
    if k == "XDG_CACHE_HOME" then return os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache") end
    if k == "HOME" then return HOME end
    return os.getenv(k) or ""
  end
  local out = val
  out = out:gsub("^~", HOME)
  out = out:gsub("%${([%w_]+)}", function(k) return get_var(k) end)
  out = out:gsub("%$([%w_]+)", function(k) return get_var(k) end)
  return out
end

local function parse_vars_file(path)
  local out = {}
  local s = read_file(path)
  if not s then return out end
  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local k, v = line:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$")
      if k and v then out[k] = expand_vars(v) end
    end
  end
  return out
end

local function draw_png_centered(cr, path, cx, cy, size)
  if not file_exists(path) then return false end
  local img = cairo_image_surface_create_from_png(path)
  if (not img) or (cairo_surface_status(img) ~= 0) then
    if img then cairo_surface_destroy(img) end
    return false
  end
  local w = cairo_image_surface_get_width(img)
  local h = cairo_image_surface_get_height(img)
  if (not w or w == 0) or (not h or h == 0) then
    cairo_surface_destroy(img)
    return false
  end
  local scale_f = size / math.max(w, h)
  local sw, sh = w * scale_f, h * scale_f
  local ox, oy = cx - (sw / 2), cy - (sh / 2)

  cairo_save(cr)
  cairo_translate(cr, ox, oy)
  cairo_scale(cr, scale_f, scale_f)
  cairo_set_source_surface(cr, img, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)

  cairo_surface_destroy(img)
  return true
end

M.get_theme = get_theme
M.scale = scale
M.set_rgba = set_rgba
M.hex_to_rgba = hex_to_rgba
M.draw_text_center = draw_text_center
M.draw_text_center_mid = draw_text_center_mid
M.draw_text_center_rotated = draw_text_center_rotated
M.draw_text_center_fixed = draw_text_center_fixed
M.draw_text_left = draw_text_left
M.draw_text_block_left = draw_text_block_left
M.count_text_lines = count_text_lines
M.file_exists = file_exists
M.read_file = read_file
M.parse_vars_file = parse_vars_file
M.draw_png_centered = draw_png_centered
M.expand_vars = expand_vars
M.embedded_corner_offset = embedded_corner_offset
M.suite_dir = SUITE_DIR
M.cache_dir = CACHE_DIR

return M
