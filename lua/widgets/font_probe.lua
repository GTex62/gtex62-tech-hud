--[[
  ${CONKY_SUITE_DIR}/lua/widgets/font_probe.lua
  Eurostile font probe widget (standalone test).
]]

require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local FONT_LIST = nil

local function read_eurostile_fonts()
  local entries = {}
  local seen = {}
  local cmd = "sh -lc \"fc-list | grep -i 'Eurostile'\""
  local p = io.popen(cmd)
  if not p then return entries end

  for line in p:lines() do
    local families, styles = line:match(":%s*([^:]+):style=([^:]+)")
    if families and styles then
      styles = styles:gsub("%s+$", "")
      for fam in families:gmatch("([^,]+)") do
        fam = fam:gsub("^%s+", ""):gsub("%s+$", "")
        local key = fam .. "|" .. styles
        if not seen[key] then
          table.insert(entries, { family = fam, style = styles })
          seen[key] = true
        end
      end
    end
  end

  p:close()
  table.sort(entries, function(a, b)
    if a.family == b.family then return a.style < b.style end
    return a.family < b.family
  end)
  return entries
end

local function get_font_entries()
  if FONT_LIST then return FONT_LIST end
  FONT_LIST = read_eurostile_fonts()
  return FONT_LIST
end

local function draw_text(cr, x, y, txt, font_face, font_size, col, alpha, weight)
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, txt)
end

local function draw_font_probe_impl()
  if conky_window == nil then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local t = get_theme()
  local palette = (type(t.palette) == "table") and t.palette or {}
  local gray = (type(palette.gray) == "table") and palette.gray or {}

  local label_font = (t.fonts and t.fonts.label) or "Rajdhani"
  local title_font = (t.fonts and t.fonts.title) or label_font

  local margin = scale(30)
  local line_h = scale(72)
  local label_w = scale(840)
  local col_w = scale(1800)
  local start_x = margin
  local start_y = margin + scale(26)

  local title = "EUROSTILE FONT PROBE"
  draw_text(cr, start_x, margin, title, title_font, scale(48), gray.g60 or { 0.60, 0.60, 0.60 }, 0.90)

  local entries = get_font_entries()
  if #entries == 0 then
    draw_text(cr, start_x, start_y, "No Eurostile fonts found.", label_font, scale(42), gray.g50 or { 0.50, 0.50, 0.50 }, 0.90)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    return
  end

  local sample = "The quick brown fox 0123456789"
  local x = start_x
  local y = start_y + scale(10)

  for _, e in ipairs(entries) do
    if y + line_h > (h - margin) then
      x = x + col_w
      y = start_y + scale(10)
    end

    local label = e.family .. " (" .. e.style .. ")"
    draw_text(cr, x, y, label, label_font, scale(33), gray.g60 or { 0.60, 0.60, 0.60 }, 0.85)

    local weight = e.style:match("Bold") and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
    draw_text(cr, x + label_w, y, sample, e.family, scale(42), palette.white or { 1.00, 1.00, 1.00 }, 0.95, weight)

    y = y + line_h
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

---@diagnostic disable-next-line: lowercase-global
function conky_draw_font_probe()
  if conky_window == nil then return end
  local ok, err = pcall(draw_font_probe_impl)
  if not ok then
    print("font probe error: " .. tostring(err))
  end
end
