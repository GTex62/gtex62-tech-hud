--[[
  ${CONKY_SUITE_DIR}/lua/widgets/sitrep.lua
  SITREP status panel (no arcs).

  Exposes:
    function conky_draw_sitrep()
]]

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local WD_BLACK_PATH = os.getenv("WD_BLACK_PATH") or "/mnt/WD_Black"
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")

-- Load shared helpers (kept for consistency with other widgets)
pcall(dofile, SUITE_DIR .. "/lua/widgets/widgets.lua")
pcall(dofile, SUITE_DIR .. "/lua/widgets/pf_widget.lua")

-- Ensure Cairo bindings are available in this scope (Conky doesn't always preload)
pcall(require, "cairo")

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function get_sitrep_theme()
  local p = rawget(_G, "SITREP_THEME")
  if (not p or p == "") then
    p = os.getenv("SITREP_THEME")
  end
  if (not p or p == "") then
    local default_path = SUITE_DIR .. "/theme-sitrep.lua"
    if util.file_exists(default_path) then
      p = default_path
    end
  end
  if type(p) == "string" and p ~= "" then
    local ok, t = pcall(dofile, p)
    if ok and type(t) == "table" then return t end
  end
  return util.get_theme()
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function cparse(s)
  if type(conky_parse) == "function" then
    return conky_parse(s) or ""
  end
  return ""
end

local function refresh_wan_ip()
  cparse("${execi 15 " .. SUITE_DIR .. "/scripts/wan_ip.sh}")
end

local function wan_ip_label_short()
  local raw = trim(cparse("${execi 15 " .. SUITE_DIR .. "/scripts/net_extras.sh wan_ip_label}"))
  if raw == "" then return "WAN IP" end
  if raw:find("VPN") then return "WAN IP (VPN)" end
  return "WAN IP"
end

local function to_num(v)
  local n = tonumber(v or "") or 0
  if n ~= n then return 0 end
  return n
end

local function draw_text_right(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  util.set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y)
  cairo_show_text(cr, txt)
end

local function os_label_text()
  local raw = trim(cparse("${execi 3600 " .. SUITE_DIR .. "/scripts/mint_version.sh}"))
  if raw == "" then return "" end
  local ver = raw:match("(%d+%.%d+[%w%.%-]*)") or raw:match("(%d+%.%d+)")
  if ver and ver ~= "" then
    return "LM " .. ver
  end
  return raw
end

local OS_AGE_CACHE = {
  path = "",
  birth_ts = nil,
  ts = 0,
}

local function get_root_birth_ts(path, poll, fallback_mtime)
  local now = os.time()
  local ttl = tonumber(poll) or 3600
  if path == OS_AGE_CACHE.path and OS_AGE_CACHE.birth_ts and (now - OS_AGE_CACHE.ts) < ttl then
    return OS_AGE_CACHE.birth_ts
  end

  local cmd = string.format("stat -c %%W %q 2>/dev/null", path)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  local ts = tonumber(out:match("(%-?%d+)"))
  if (not ts or ts <= 0) and fallback_mtime == true then
    local cmd_m = string.format("stat -c %%Y %q 2>/dev/null", path)
    local pm = io.popen(cmd_m, "r")
    if pm then
      local out_m = pm:read("*a") or ""
      pm:close()
      ts = tonumber(out_m:match("(%-?%d+)"))
    end
  end
  if not ts or ts <= 0 then return nil end
  OS_AGE_CACHE.path = path
  OS_AGE_CACHE.birth_ts = ts
  OS_AGE_CACHE.ts = now
  return ts
end

local function text_width(cr, txt, font_face, font_size)
  if txt == nil or txt == "" then return 0 end
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  return ext.x_advance or (ext.width + ext.x_bearing)
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

local function parse_pct(val)
  local s = cparse(tostring(val or ""))
  s = s:gsub("%%", ""):gsub("%s+", "")
  local n = tonumber(s) or 0
  return clamp(n, 0, 100)
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

local function arc_span_ccw(start_a, end_a)
  if end_a >= start_a then return end_a - start_a end
  return (math.pi * 2) - (start_a - end_a)
end

local function arc_span_cw(start_a, end_a)
  if start_a >= end_a then return start_a - end_a end
  return (math.pi * 2) - (end_a - start_a)
end

local function draw_arc_meter(cr, cx, cy, radius, start_a, end_a, pct, color, alpha, width, cw)
  local p = clamp(pct or 0, 0, 1)
  if p <= 0 then return end
  local span = cw and arc_span_cw(start_a, end_a) or arc_span_ccw(start_a, end_a)
  local a2 = cw and (start_a - (span * p)) or (start_a + (span * p))
  util.set_rgba(cr, color or { 1, 1, 1 }, alpha or 1)
  cairo_set_line_width(cr, width or 2)
  cairo_new_sub_path(cr)
  if cw then
    cairo_arc_negative(cr, cx, cy, radius, start_a, a2)
  else
    cairo_arc(cr, cx, cy, radius, start_a, a2)
  end
  cairo_stroke(cr)
end

local function polar(cx, cy, radius, angle)
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

local function draw_text_arc(cr, cx, cy, r, angle_mid, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" or r <= 0 then return end
  util.set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)

  local parts = {}
  local total = 0
  for ch in tostring(txt):gmatch(".") do
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, ch, ext)
    local adv = ext.x_advance
    total = total + adv
    parts[#parts + 1] = { ch = ch, ext = ext, adv = adv }
  end

  if total <= 0 then return end

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

local net_ema = { up = nil, down = nil, p1 = nil, p2 = nil }
local PF_CACHE_DIR = CACHE_DIR .. "/pfsense"
local PF_CACHE_FULL = PF_CACHE_DIR .. "/sitrep_full.cache"
local pf_cache_ready = false
local AP_CACHE_DIR = CACHE_DIR .. "/ap"
local AP_STATUS_CACHE = AP_CACHE_DIR .. "/ap_status_all_clients.cache"
local AP_NAMED_CACHE = AP_CACHE_DIR .. "/ap_clients_named.cache"
local ap_cache_ready = false
local ap_last_status = ""
local ap_last_named = ""
local sitrep_start_ts = os.time()

local function parse_kv(raw)
  local out, cur = {}, nil
  for line in (raw or ""):gmatch("[^\r\n]+") do
    local sec = line:match("^section=(%S+)")
    if sec then
      cur = sec
      out[cur] = out[cur] or {}
    else
      local k, v = line:match("^([%w%._%-]+)=(.*)$")
      if k then
        if cur then
          out[cur][k] = v
        else
          out[k] = v
        end
      end
    end
  end
  return out
end

local function fmt_bytes_iec(bytes)
  local b = tonumber(bytes) or 0
  if b < 0 then b = 0 end
  if b < 1024 then
    return string.format("%.0f B", b)
  end
  local units = { "K", "M", "G", "T", "P" }
  local v = b / 1024
  local i = 1
  while v >= 1024 and i < #units do
    v = v / 1024
    i = i + 1
  end
  return string.format("%.2f %s", v, units[i])
end

local function fmt_int_commas(n)
  local v = tonumber(n) or 0
  if v < 0 then v = 0 end
  local s = string.format("%.0f", v)
  while true do
    local n2, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    s = n2
    if k == 0 then break end
  end
  return s
end

local function fmt_uptime(seconds)
  local s = tonumber(seconds or "")
  if not s or s <= 0 then return "" end
  local d = math.floor(s / 86400)
  s = s % 86400
  local h = math.floor(s / 3600)
  s = s % 3600
  local m = math.floor(s / 60)
  if d > 0 then
    return string.format("%dd %02dh", d, h)
  elseif h > 0 then
    return string.format("%dh %02dm", h, m)
  end
  return string.format("%dm", m)
end

local function pf_summary()
  local raw = trim(cparse("${execi 30 " .. SUITE_DIR .. "/scripts/pf-fetch-basic.sh medium}"))
  if raw == "" then
    return { status = "DOWN", cpu = "--", mem = "--", uptime = "", gateway_online = "" }
  end

  local data = parse_kv(raw)
  local status = "OK"
  local ssh_tripped = data.ssh_tripped or "0"
  local ssh_status = data.ssh_status or ""
  local gw_online = data.gateway and data.gateway.gateway_online or ""

  if ssh_tripped == "1" or ssh_status:match("^TRIPPED") then
    status = "WARN"
  end
  if gw_online == "0" then
    status = "WARN"
  end

  local sys = data.system or {}
  local idle = to_num(sys.cpu_idle)
  local cpu_used = 0
  if idle > 0 then
    cpu_used = math.max(0, 100 - idle)
  else
    cpu_used = to_num(sys.cpu_user) + to_num(sys.cpu_system) + to_num(sys.cpu_interrupt) + to_num(sys.cpu_nice)
  end

  local mem_used = to_num(sys.mem_used_pct)
  local uptime = fmt_uptime(sys.uptime_seconds)

  return {
    status = status,
    cpu = string.format("%.0f", cpu_used),
    mem = string.format("%.0f", mem_used),
    uptime = uptime,
    gateway_online = gw_online,
  }
end

local function pf_data_full(interval)
  local poll = tonumber(interval) or 90
  if not pf_cache_ready then
    os.execute("mkdir -p " .. PF_CACHE_DIR)
    pf_cache_ready = true
  end

  local cached = util.read_file and util.read_file(PF_CACHE_FULL) or nil
  local data = {}
  if cached and cached ~= "" then
    data = parse_kv(cached)
  end

  -- Trigger async refresh (background), return cached data immediately
  if (os.time() - sitrep_start_ts) >= 2 then
    cparse("${execi " .. poll .. " " .. SUITE_DIR ..
      "/scripts/pf-fetch-basic.sh full > " .. PF_CACHE_FULL .. " 2>/dev/null &}")
  end
  return data
end

local function ap_cached_output(script, cache_path, poll)
  local interval = tonumber(poll) or 30
  if not ap_cache_ready then
    os.execute("mkdir -p " .. AP_CACHE_DIR)
    ap_cache_ready = true
  end
  local cached = util.read_file and util.read_file(cache_path) or nil
  local out = cached or ""
  if out == "" then
    if script == "ap_status_all_clients.sh" then
      out = ap_last_status
    else
      out = ap_last_named
    end
  end
  if (os.time() - sitrep_start_ts) >= 2 then
    local tmp = "/tmp/" .. script .. ".tmp"
    cparse("${execi " .. interval .. " " .. SUITE_DIR .. "/scripts/" .. script ..
      " > " .. tmp .. " 2>/dev/null && mv " .. tmp .. " " .. cache_path .. " &}")
  end
  if out ~= "" then
    if script == "ap_status_all_clients.sh" then
      ap_last_status = out
    else
      ap_last_named = out
    end
  end
  return out
end

local function parse_ap_status(raw)
  local out = { order = {}, data = {} }
  for line in (raw or ""):gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" then
      local label = line:match("^(.-)%s*%(") or line:match("^(%S+)") or "AP"
      label = trim(label):gsub(":", ""):upper()
      if out.data[label] == nil then
        out.order[#out.order + 1] = label
        out.data[label] = {}
      end
      local cpu = trim(line:match("CPU:%s*([^|]+)") or "")
      local clients = tonumber(line:match("[Cc]lients:%s*(%d+)") or 0) or 0
      out.data[label].cpu = cpu ~= "" and cpu or "--"
      out.data[label].clients = clients
    end
  end
  return out
end

local function parse_ap_clients_named(raw)
  local out = { order = {}, data = {} }
  local cur = nil
  local mode = nil

  local function add_items(list, line)
    for item in (line or ""):gmatch("[^,]+") do
      item = trim(item)
      if item ~= "" and item:lower() ~= "none" then
        list[#list + 1] = item
      end
    end
  end

  for line in (raw or ""):gmatch("[^\r\n]+") do
    line = trim(line:gsub("%${[^}]+}", ""))
    if line == "" then
      mode = nil
    elseif line:find("Clients:") then
      local pre = line:match("^(.-)%s*Clients:") or ""
      local label = trim(pre:gsub("[^%w%s]+$", "")):upper()
      if out.data[label] == nil then
        out.order[#out.order + 1] = label
        out.data[label] = { known = {}, unknown = {}, clients = 0, unknown_count = 0 }
      end
      cur = label
      out.data[label].clients = tonumber(line:match("Clients:%s*(%d+)") or 0) or 0
      out.data[label].unknown_count = tonumber(line:match("Unknown:%s*(%d+)") or 0) or 0
      mode = nil
    elseif cur and line:match("^Connected:") then
      mode = "known"
      add_items(out.data[cur].known, line:gsub("^Connected:%s*", ""))
    elseif cur and line:match("^Unknown:") then
      mode = "unknown"
      add_items(out.data[cur].unknown, line:gsub("^Unknown:%s*", ""))
    elseif cur and mode == "known" then
      add_items(out.data[cur].known, line)
    elseif cur and mode == "unknown" then
      add_items(out.data[cur].unknown, line)
    end
  end
  return out
end

local function ap_blocks()
  local raw_status = trim(ap_cached_output("ap_status_all_clients.sh", AP_STATUS_CACHE, 30))
  local raw_named = trim(ap_cached_output("ap_clients_named.sh", AP_NAMED_CACHE, 30))

  if raw_status == "" and raw_named == "" then
    return {}
  end

  if raw_status:match("SSH PAUSED") or raw_named:match("SSH PAUSED") then
    return { { label = "AP", cpu = "--", conn = "--", unknown_count = 0, known = {}, unknown = {} } }
  end

  local status = parse_ap_status(raw_status)
  local named = parse_ap_clients_named(raw_named)
  local order = (#status.order > 0) and status.order or named.order
  local out = {}

  for _, label in ipairs(order) do
    local s = status.data[label] or {}
    local n = named.data[label] or {}
    out[#out + 1] = {
      label = label,
      cpu = s.cpu or "--",
      conn = (n.clients ~= nil and n.clients or s.clients) or 0,
      unknown_count = n.unknown_count or 0,
      known = n.known or {},
      unknown = n.unknown or {},
    }
  end

  return out
end

function conky_draw_sitrep()
  if conky_window == nil then return end
  if type(cairo_xlib_surface_create) ~= "function" then return end

  local t = get_sitrep_theme()
  local cfg = t.sitrep or {}

  local width = cfg.width or conky_window.width
  local height = conky_window.height
  local line_h = cfg.line_h or 20
  local pad = math.floor(line_h * 0.6)

  local title_size = cfg.title_size or 24
  local text_size = cfg.text_size or 16

  local title_font = cfg.title_font
  if not title_font or title_font == "auto" then
    title_font = (t.fonts and t.fonts.title) or "Sans"
  end

  local text_font = cfg.text_font
  if not text_font or text_font == "auto" then
    text_font = (t.fonts and (t.fonts.value_c or t.fonts.label)) or "Sans"
  end

  local title_color = cfg.color_title or { 1, 1, 1 }
  local text_color = cfg.color_text or { 1, 1, 1 }
  local title_alpha = tonumber(cfg.title_alpha) or title_color[4] or 1
  local text_alpha = text_color[4] or 1
  local label_color = cfg.label_color or (t.palette and t.palette.black) or { 0.00, 0.00, 0.00 }
  local label_alpha = tonumber(cfg.label_alpha) or 0.50
  local value_color = cfg.value_color or text_color
  local value_alpha = tonumber(cfg.value_alpha) or text_alpha
  local ip_value_color = cfg.ip_value_color or value_color
  local ip_value_alpha = tonumber(cfg.ip_value_alpha) or value_alpha
  local ping_value_color = cfg.ping_value_color or value_color
  local ping_value_alpha = tonumber(cfg.ping_value_alpha) or value_alpha
  local email_value_color = cfg.email_value_color or value_color
  local email_value_alpha = tonumber(cfg.email_value_alpha) or value_alpha
  local disk_value_color = cfg.disk_value_color or value_color
  local disk_value_alpha = tonumber(cfg.disk_value_alpha) or value_alpha

  local hr_cfg = cfg.hr or {}
  local hr_color = hr_cfg.color or (t.palette and t.palette.accent and t.palette.accent.maroon) or { 0.40, 0.08, 0.12 }
  local hr_alpha = tonumber(hr_cfg.alpha) or 0.85
  local hr_stroke = tonumber(hr_cfg.stroke) or 2.0
  local hr_len = tonumber(hr_cfg.length) or (width - (pad * 2))

  local cs = cairo_xlib_surface_create(conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    conky_window.width,
    conky_window.height)
  local cr = cairo_create(cs)

  local bg_alpha = tonumber(cfg.alpha) or 0
  if bg_alpha > 0 then
    local bg_color = (t.palette and t.palette.gray and t.palette.gray.g10) or { 0, 0, 0 }
    util.set_rgba(cr, bg_color, bg_alpha)
    cairo_rectangle(cr, 0, 0, conky_window.width, conky_window.height)
    cairo_fill(cr)
  end

  local panel = cfg.panel or {}
  if panel.enabled ~= false then
    local pad_x = tonumber(panel.padding_x) or 0
    local pad_y = tonumber(panel.padding_y) or 0

    local x0 = tonumber(panel.offset_x) or 0
    local y0 = tonumber(panel.offset_y) or 0
    local pw = panel.width
    local ph = panel.height

    if pw == nil then
      x0 = x0 + pad_x
      pw = conky_window.width - (pad_x * 2)
    end
    if ph == nil then
      y0 = y0 + pad_y
      ph = conky_window.height - (pad_y * 2)
    end

    if pw > 0 and ph > 0 then
      local radius = tonumber(panel.radius) or 0
      local fill_col = panel.fill_color or { 0.30, 0.30, 0.30 }
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
        if tint and type(fill_col) == "table" then
          fill_col = blend_color(fill_col, tint, amt)
        end
      end
      local fill_alpha = tonumber(panel.fill_alpha) or 0
      local stroke_col = panel.stroke_color or { 1, 1, 1 }
      local stroke_alpha = tonumber(panel.stroke_alpha) or 0
      local stroke_width = tonumber(panel.stroke_width) or 0

      if fill_alpha > 0 then
        util.set_rgba(cr, fill_col, fill_alpha)
        draw_round_rect(cr, x0, y0, pw, ph, radius)
        cairo_fill(cr)
      end
      if stroke_width > 0 and stroke_alpha > 0 then
        util.set_rgba(cr, stroke_col, stroke_alpha)
        cairo_set_line_width(cr, stroke_width)
        draw_round_rect(cr, x0, y0, pw, ph, radius)
        cairo_stroke(cr)
      end

      local outer = panel.outer_stroke or {}
      if outer.enabled ~= false then
        local outer_offset = tonumber(outer.offset) or 0
        local outer_width = tonumber(outer.width) or stroke_width
        local outer_color = outer.color or stroke_col
        local outer_alpha = tonumber(outer.alpha) or stroke_alpha

        local ox = x0 - outer_offset
        local oy = y0 - outer_offset
        local ow = pw + (outer_offset * 2)
        local oh = ph + (outer_offset * 2)
        local orad = radius + outer_offset

        if outer_width > 0 and outer_alpha > 0 and ow > 0 and oh > 0 then
          util.set_rgba(cr, outer_color, outer_alpha)
          cairo_set_line_width(cr, outer_width)
          draw_round_rect(cr, ox, oy, ow, oh, orad)
          cairo_stroke(cr)
        end
      end
    end
  end

  local content_offset_x = tonumber(cfg.content_offset_x) or 0
  local content_offset_y = tonumber(cfg.content_offset_y) or 0
  local did_translate = false
  if content_offset_x ~= 0 or content_offset_y ~= 0 then
    cairo_save(cr)
    cairo_translate(cr, content_offset_x, content_offset_y)
    did_translate = true
  end

  local title_text = cfg.title_text or "SITREP"
  local title_x = tonumber(cfg.title_x) or pad
  local title_y = tonumber(cfg.title_y) or (pad + title_size)
  local content_right = width - pad
  if content_right < pad + 80 then content_right = pad + 80 end
  local hr_right_limit = conky_window.width - pad

  local pf_poll = tonumber((t.poll and t.poll.slow) or 90) or 90
  local pf_data = nil
  local function get_pf_data()
    if not pf_data then
      pf_data = pf_data_full(pf_poll)
    end
    return pf_data
  end

  local y = pad + text_size

  -- Title (top-left)
  util.draw_text_left(cr, title_x, title_y, title_text, title_font, title_size, title_color, title_alpha)

  -- Gateway label (top-right)
  local gw_cfg = (t.pf and t.pf.gateway_label) or {}
  if gw_cfg.enabled ~= false then
    local gw_on = tostring((get_pf_data().gateway or {}).gateway_online or "")
    if gw_on == "" then gw_on = "0" end
    local gw_text = gw_cfg.text_ok or "ONLINE"
    local gw_color = gw_cfg.color_ok
    if gw_on ~= "1" then
      gw_text = gw_cfg.text_bad or "OFFLINE"
      gw_color = gw_cfg.color_bad
    end
    if gw_text and gw_text ~= "" then
      if not gw_color then
        if gw_on == "1" then
          gw_color = (t.colors and t.colors.good) or value_color
        else
          gw_color = (t.colors and t.colors.bad) or value_color
        end
      end
      local gw_size = tonumber(gw_cfg.size) or title_size
      local gw_alpha = tonumber(gw_cfg.alpha) or (gw_color[4] or title_alpha)
      local gw_weight = (gw_cfg.weight == "bold") and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
      local gw_dx = tonumber(gw_cfg.dx) or 0
      local gw_dy = tonumber(gw_cfg.dy) or 0
      local hr_end_x = pad + hr_len
      if hr_end_x > hr_right_limit then hr_end_x = hr_right_limit end
      util.set_rgba(cr, gw_color, gw_alpha)
      cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, gw_weight)
      cairo_set_font_size(cr, gw_size)
      local ext = cairo_text_extents_t:create()
      cairo_text_extents(cr, gw_text, ext)
      cairo_move_to(cr, hr_end_x - (ext.width + ext.x_bearing) + gw_dx, title_y + gw_dy)
      cairo_show_text(cr, gw_text)
    end
  end


  local function draw_row(label, value, font_face)
    local face = font_face or title_font
    util.draw_text_left(cr, pad, y, label, face, text_size, label_color, label_alpha)
    draw_text_right(cr, content_right, y, value or "", face, text_size, value_color, value_alpha)
    y = y + line_h
  end

  local function draw_row_value_left(label, value, font_face, value_x)
    local face = font_face or title_font
    util.draw_text_left(cr, pad, y, label, face, text_size, label_color, label_alpha)
    util.draw_text_left(cr, value_x, y, value or "", face, text_size, value_color, value_alpha)
    y = y + line_h
  end

  local function draw_row_value_left_light(label, value, font_face, value_x)
    local face = font_face or title_font
    util.draw_text_left(cr, pad, y, label, face, text_size, value_color, value_alpha)
    util.draw_text_left(cr, value_x, y, value or "", face, text_size, value_color, value_alpha)
    y = y + line_h
  end

  local function draw_row_value_left_custom(label, value, font_face, value_x, label_col, label_al, value_col, value_al)
    local face = font_face or title_font
    util.draw_text_left(cr, pad, y, label, face, text_size, label_col or label_color, label_al or label_alpha)
    util.draw_text_left(cr, value_x, y, value or "", face, text_size, value_col or value_color, value_al or value_alpha)
    y = y + line_h
  end

  local function draw_meters()
    local m = cfg.meters or {}
    if m.enabled == false then return end

    local x0 = tonumber(m.x) or 0
    local y0 = tonumber(m.y) or 0
    local w = tonumber(m.width) or 60
    local h = tonumber(m.height) or 160
    local radius = tonumber(m.radius) or 0
    local pad_top = tonumber(m.pad_top) or 0
    local pad_bottom = tonumber(m.pad_bottom) or 0

    local bg_color = m.bg_color or { 0, 0, 0 }
    local bg_alpha = tonumber(m.bg_alpha) or 0

    local bar_w = tonumber(m.bar_width) or 6
    local bar_gap = tonumber(m.bar_gap) or 6
    local bar_alpha = tonumber(m.bar_alpha) or 1
    local bar_colors = m.bar_colors or {}

    local label_font = m.label_font
    if not label_font or label_font == "auto" then
      label_font = title_font
    end
    local label_size = tonumber(m.label_size) or 12
    local label_color = m.label_color or { 0.30, 0.30, 0.30 }
    local label_alpha = tonumber(m.label_alpha) or 0.70
    local label_offset = tonumber(m.label_offset) or 8

    local labels = m.labels or { "VRM", "GPU", "RAM", "CPU" }
    local values = { m.value_vrm, m.value_gpu, m.value_ram, m.value_cpu }

    -- background box
    if bg_alpha > 0 then
      util.set_rgba(cr, bg_color, bg_alpha)
      draw_round_rect(cr, x0, y0, w, h, radius)
      cairo_fill(cr)
    end

    local total_w = (bar_w * 4) + (bar_gap * 3)
    local start_x = x0 + math.max(0, (w - total_w) / 2)
    local bottom = y0 + h - (bar_w / 2) - pad_bottom
    local usable_h = h - bar_w - pad_top - pad_bottom
    if usable_h < 0 then usable_h = 0 end

    for i = 1, 4 do
      local pct = parse_pct(values[i]) / 100
      local bar_len = usable_h * pct
      local cx = start_x + ((i - 1) * (bar_w + bar_gap)) + (bar_w / 2)
      local color = bar_colors[i] or { 1, 1, 1 }

      util.set_rgba(cr, color, bar_alpha)
      cairo_set_line_width(cr, bar_w)
      cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

      if bar_len <= 0 then
        cairo_arc(cr, cx, bottom, bar_w / 2, 0, math.pi * 2)
        cairo_fill(cr)
      else
        cairo_move_to(cr, cx, bottom)
        cairo_line_to(cr, cx, bottom - bar_len)
        cairo_stroke(cr)
      end

      local label = labels[i] or ""
      if label ~= "" then
        util.draw_text_center_rotated(cr, cx, y0 + h + label_offset, label, label_font, label_size, label_color,
          label_alpha, math.rad(90))
      end
    end
  end

  local function draw_pfsense_meters(y_override)
    local m = cfg.pfsense_meters or {}
    if m.enabled == false then return end

    local x0 = tonumber(m.x) or 0
    local y0 = tonumber(y_override) or tonumber(m.y) or 0
    local w = tonumber(m.width) or 0
    local h = tonumber(m.height) or 0
    local radius = tonumber(m.radius) or 0
    local pad_top = tonumber(m.pad_top) or 0
    local pad_bottom = tonumber(m.pad_bottom) or 0

    local bg_color = m.bg_color or { 0, 0, 0 }
    local bg_alpha = tonumber(m.bg_alpha) or 0

    local bar_w = tonumber(m.bar_width) or 6
    local bar_gap = tonumber(m.bar_gap) or 6
    local group_gap = tonumber(m.group_gap) or 12
    local bar_alpha = tonumber(m.bar_alpha) or 1
    local down_color = m.down_color or { 0.7, 0.7, 0.7 }
    local up_color = m.up_color or { 0.3, 0.3, 0.3 }

    local label_font = m.label_font
    if not label_font or label_font == "auto" then
      label_font = title_font
    end
    local label_size = tonumber(m.label_size) or text_size
    local label_color = m.label_color or label_color
    local label_alpha = tonumber(m.label_alpha) or 0.7
    local label_offset = tonumber(m.label_offset) or 8

    local rates = nil
    if type(conky_pf_rates) == "function" then
      rates = conky_pf_rates()
    end

    local labels = m.labels or {}
    local downs = (rates and rates.down_values) or m.down_values or {}
    local ups = (rates and rates.up_values) or m.up_values or {}
    local groups = math.max(#labels, #downs, #ups, 5)
    if groups < 1 then return end

    if bg_alpha > 0 then
      util.set_rgba(cr, bg_color, bg_alpha)
      draw_round_rect(cr, x0, y0, w, h, radius)
      cairo_fill(cr)
    end

    local group_w = (bar_w * 2) + bar_gap
    local total_w = (group_w * groups) + (group_gap * (groups - 1))
    local start_x = x0 + math.max(0, (w - total_w) / 2)
    local bottom = y0 + h - (bar_w / 2) - pad_bottom
    local usable_h = h - bar_w - pad_top - pad_bottom
    if usable_h < 0 then usable_h = 0 end

    for i = 1, groups do
      local pct_down = parse_pct(downs[i] or "0") / 100
      local pct_up = parse_pct(ups[i] or "0") / 100
      local down_len = usable_h * pct_down
      local up_len = usable_h * pct_up

      local gx = start_x + ((i - 1) * (group_w + group_gap))
      local cx_down = gx + (bar_w / 2)
      local cx_up = gx + bar_w + bar_gap + (bar_w / 2)

      cairo_set_line_width(cr, bar_w)
      cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

      util.set_rgba(cr, down_color, bar_alpha)
      if down_len <= 0 then
        cairo_arc(cr, cx_down, bottom, bar_w / 2, 0, math.pi * 2)
        cairo_fill(cr)
      else
        cairo_move_to(cr, cx_down, bottom)
        cairo_line_to(cr, cx_down, bottom - down_len)
        cairo_stroke(cr)
      end

      util.set_rgba(cr, up_color, bar_alpha)
      if up_len <= 0 then
        cairo_arc(cr, cx_up, bottom, bar_w / 2, 0, math.pi * 2)
        cairo_fill(cr)
      else
        cairo_move_to(cr, cx_up, bottom)
        cairo_line_to(cr, cx_up, bottom - up_len)
        cairo_stroke(cr)
      end

      local label = labels[i] or ""
      if label ~= "" then
        util.draw_text_center(cr, gx + (group_w / 2), y0 + h + label_offset, label, label_font, label_size,
          label_color, label_alpha)
      end
    end
  end

  local function draw_pfsense_totals(y_base, pf_center_x, pf_center_off)
    local TT = (t.pf and t.pf.totals_table) or {}
    if TT.enabled == false then return end
    local font = TT.font or (t.fonts and t.fonts.mono) or "DejaVu Sans Mono"
    local size_h = tonumber(TT.size_header) or 14
    local size_b = tonumber(TT.size_body) or 13
    local col_h = TT.color_header or { 0.85, 0.85, 0.85, 1.0 }
    local col_l = TT.color_label or { 0.85, 0.85, 0.85, 1.0 }
    local col_v = TT.color_value or { 0.95, 0.97, 0.99, 1.0 }

    local label_w = tonumber(TT.label_col_w) or 120
    local data_w = tonumber(TT.data_col_w) or 110
    local head_h = tonumber(TT.header_h) or 20
    local row_h = tonumber(TT.row_h) or 18
    local row_gap = tonumber(TT.row_gap) or 6
    local dx = tonumber(TT.dx) or 0
    local dy = tonumber(TT.dy) or 0

    local headers = TT.headers or { "WAN", "HOME", "IoT", "GUEST", "INFRA", "CAM" }
    local row_labels = TT.row_labels or { ["in"] = "Bytes In", ["out"] = "Bytes Out" }
    local order = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
    local ifaces = t.ifaces or {
      INFRA = "igc1.40",
      CAM   = "igc1.50",
      HOME  = "igc1.10",
      IOT   = "igc1.20",
      GUEST = "igc1.30",
      WAN   = "igc0",
    }

    local total_w = label_w + (#headers) * data_w
    local x0 = (pf_center_x + pf_center_off + dx) - total_w / 2
    local y0 = (y_base or y) + dy

    local function text_extents(txt, size)
      cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
      cairo_set_font_size(cr, size)
      local te = cairo_text_extents_t:create()
      cairo_text_extents(cr, txt, te)
      return te
    end

    local function draw_center(txt, x, y_pos, size, col)
      local te = text_extents(txt, size)
      util.set_rgba(cr, col, col[4] or 1)
      cairo_move_to(cr, x - (te.width or 0) / 2, y_pos)
      cairo_show_text(cr, txt)
    end

    local function draw_right(txt, x, y_pos, size, col)
      local te = text_extents(txt, size)
      util.set_rgba(cr, col, col[4] or 1)
      cairo_move_to(cr, x - (te.width or 0), y_pos)
      cairo_show_text(cr, txt)
    end

    local iface_data = get_pf_data().interfaces or {}
    local function iface_val(ifn, dir)
      return tonumber(iface_data["iface_" .. ifn .. "_" .. dir]) or 0
    end

    for i, h in ipairs(headers) do
      local cxh = x0 + label_w + (i - 0.5) * data_w
      local cyh = y0 + head_h
      draw_center(h, cxh, cyh, size_h, col_h)
    end

    do
      local cy_row = y0 + head_h + row_gap + row_h
      draw_right(row_labels["in"] or "Bytes In", x0 + label_w - 6, cy_row, size_b, col_l)
      for i, key in ipairs(order) do
        local ifn = ifaces[key]
        local val = ifn and iface_val(ifn, "ibytes") or 0
        local cxv = x0 + label_w + (i - 0.5) * data_w
        draw_center(fmt_bytes_iec(val), cxv, cy_row, size_b, col_v)
      end
    end

    do
      local cy_row = y0 + head_h + row_gap + row_h + row_gap + row_h
      draw_right(row_labels["out"] or "Bytes Out", x0 + label_w - 6, cy_row, size_b, col_l)
      for i, key in ipairs(order) do
        local ifn = ifaces[key]
        local val = ifn and iface_val(ifn, "obytes") or 0
        local cxv = x0 + label_w + (i - 0.5) * data_w
        draw_center(fmt_bytes_iec(val), cxv, cy_row, size_b, col_v)
      end
    end
  end

  local function draw_pfsense_status(y_base, pf_center_x, pf_center_off)
    local SB = (t.pf and t.pf.status_block) or {}
    if SB.enabled == false then return end
    local font = SB.font or (t.fonts and t.fonts.regular) or "DejaVu Sans"
    local size = tonumber(SB.size) or 14
    local col_l = SB.label_color or { 0.85, 0.85, 0.85, 1.0 }
    local col_v = SB.value_color or { 0.95, 0.97, 0.99, 1.0 }
    local field_sep = SB.field_sep or " | "
    local dx = tonumber(SB.dx) or 0
    local dy = tonumber(SB.dy) or 0
    local line_gap = tonumber(SB.line_gap) or 18

    local D = get_pf_data() or {}
    local pfb_cfg = SB.pfb or {}
    local ph_cfg = SB.pihole or {}

    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)

    local function draw_segments(y_pos, segments)
      local full = ""
      for _, seg in ipairs(segments) do full = full .. seg[1] end
      local te = cairo_text_extents_t:create()
      cairo_text_extents(cr, full, te)
      local x0 = (pf_center_x + pf_center_off + dx) - (te.width / 2 + te.x_bearing)
      cairo_move_to(cr, x0, y_pos)
      for _, seg in ipairs(segments) do
        local txt, col = seg[1], seg[2]
        util.set_rgba(cr, col, col[4] or 1)
        cairo_show_text(cr, txt)
      end
    end

    local y_cursor = (y_base or y) + dy

    local pfb_enabled = (pfb_cfg.enabled ~= false)
    local ph_enabled = (ph_cfg.enabled ~= false)

    if pfb_enabled then
      local pfb_ip = tonumber((D.pfblockerng or {}).pfb_ip_total) or 0
      local pfb_dns = tonumber((D.pfblockerng or {}).pfb_dnsbl_total) or 0
      local resolver_total = tonumber((D.pfblockerng or {}).resolver_total) or 0
      local pfb_total = (resolver_total > 0) and resolver_total or (pfb_ip + pfb_dns)
      local pfb_dns_pct = tonumber((D.pfblockerng or {}).pfb_dnsbl_pct) or 0
      local pfb_dns_pct_str = string.format("%.2f%%", pfb_dns_pct)

      local segments1 = {
        { pfb_cfg.prefix or "pfBlockerNG:", col_l },
        { " ",                              col_l },
        { "IP ",                            col_l }, { fmt_int_commas(pfb_ip), col_v },
        { field_sep, col_l },
        { "DNSBL ",  col_l }, { fmt_int_commas(pfb_dns), col_v },
      }

      local segments2 = {
        { "Hits: ", col_l }, { pfb_dns_pct_str, col_v },
      }
      if pfb_cfg.show_total ~= false then
        segments2[#segments2 + 1] = { field_sep, col_l }
        segments2[#segments2 + 1] = { "Total Queries ", col_l }
        segments2[#segments2 + 1] = { fmt_int_commas(pfb_total), col_v }
      end

      draw_segments(y_cursor, segments1)
      y_cursor = y_cursor + line_gap
      draw_segments(y_cursor, segments2)
      y_cursor = y_cursor + line_gap
    end

    if pfb_enabled and ph_enabled then
      y_cursor = y_cursor + line_gap
    end

    if ph_enabled then
      local active = (D.pihole or {}).pihole_active or "0"
      local status = (active == "1" or active == 1 or active == true) and "Active" or "Offline"

      local win = tonumber(ph_cfg.load_window) or 15
      if win ~= 1 and win ~= 5 and win ~= 15 then win = 15 end
      local load_key = "pihole_load" .. tostring(win)
      local load_val = tonumber((D.pihole or {})[load_key]) or 0
      local load_str = string.format("%.2f", load_val)

      local total = tonumber((D.pihole or {}).pihole_total) or 0
      local blocked = tonumber((D.pihole or {}).pihole_blocked) or 0
      local domains = tonumber((D.pihole or {}).pihole_domains) or 0
      local pct = 0
      if total > 0 then pct = (blocked / total) * 100 end
      local pct_dec = tonumber(ph_cfg.decimals_pct) or 2
      local pct_str = string.format("%." .. tostring(pct_dec) .. "f", pct)

      local segments1 = {
        { ph_cfg.prefix or "Pi-hole:", col_l },
        { " ",                         col_l },
        { status,                      col_v },
        { field_sep,                   col_l },
        { ("L%d: "):format(win),       col_l }, { load_str, col_v },
        { field_sep, col_l },
        { "Total: ", col_l }, { fmt_int_commas(total), col_v },
      }

      local segments2 = {
        { "Blocked: ",    col_l }, { fmt_int_commas(blocked), col_v },
        { field_sep,      col_l },
        { pct_str .. "%", col_v },
        { field_sep,      col_l },
        { "Domains: ",    col_l }, { fmt_int_commas(domains), col_v },
      }

      draw_segments(y_cursor, segments1)
      y_cursor = y_cursor + line_gap
      draw_segments(y_cursor, segments2)
    end
  end

  local function draw_hr_at(ypos)
    if not ypos then return end
    util.set_rgba(cr, hr_color, hr_alpha)
    cairo_set_line_width(cr, hr_stroke)
    local x1 = pad
    local x2 = pad + hr_len
    if x2 > hr_right_limit then x2 = hr_right_limit end
    cairo_move_to(cr, x1, ypos)
    cairo_line_to(cr, x2, ypos)
    cairo_stroke(cr)
  end

  -- Header HR
  draw_hr_at(hr_cfg.header_line_y)

  -- AP block
  local ap_cfg = cfg.ap or {}
  local ap_enabled = ap_cfg.enabled ~= false
  if ap_enabled then
    draw_hr_at(hr_cfg.ap_line_y)
  end
  local ap_font = ap_cfg.font
  if not ap_font or ap_font == "auto" then
    ap_font = title_font
  end
  local ap_size = tonumber(ap_cfg.size) or text_size
  local ap_color = ap_cfg.color or value_color
  local ap_alpha = tonumber(ap_cfg.alpha) or value_alpha
  local ap_name_color = ap_cfg.name_color or ap_color
  local ap_name_alpha = tonumber(ap_cfg.name_alpha) or ap_alpha
  local ap_device_font = ap_cfg.device_font
  if not ap_device_font or ap_device_font == "auto" then
    ap_device_font = text_font
  end
  local ap_device_size = tonumber(ap_cfg.device_size) or text_size
  local ap_device_color = ap_cfg.device_color or ap_color
  local ap_device_alpha = tonumber(ap_cfg.device_alpha) or ap_alpha
  local ap_device_line_h = tonumber(ap_cfg.device_line_h) or line_h
  local unk_value_color = ap_cfg.unk_value_color or (t.palette and t.palette.accent and t.palette.accent.maroon) or { 0.40, 0.08, 0.12 }
  local unk_value_alpha = tonumber(ap_cfg.unk_value_alpha) or ap_alpha
  local unk_ip_color = ap_cfg.unk_ip_color or unk_value_color
  local unk_ip_alpha = tonumber(ap_cfg.unk_ip_alpha) or ap_device_alpha
  local ap_device_max_w = tonumber(ap_cfg.device_max_w) or (content_right - pad)
  local ap_device_center_x = tonumber(ap_cfg.device_center_x) or (pad + ((content_right - pad) / 2))
  local ap_device_align = tostring(ap_cfg.device_align or "center"):lower()
  local ap_device_left_x = tonumber(ap_cfg.device_left_x) or pad
  local ap_value_x = tonumber(ap_cfg.value_x) or content_right

  if ap_enabled then
    y = y + (line_h * 3)
    util.draw_text_left(cr, pad, y, "WBE530", ap_font, ap_size, label_color, label_alpha)
    local ap_head_w = text_width(cr, "WBE530 ", ap_font, ap_size)
    util.draw_text_left(cr, pad + ap_head_w, y, "ACCESS POINTS", ap_font, ap_size, value_color, value_alpha)
    y = y + line_h
    for _, ap in ipairs(ap_blocks()) do
      local cpu_n = tonumber(tostring(ap.cpu or ""):match("(%d+)")) or 0
      local conn_n = tonumber(ap.conn or 0) or 0
      local unk_n = tonumber(ap.unknown_count or 0) or 0
      util.draw_text_left(cr, pad, y, ap.label, ap_font, ap_size, ap_name_color, ap_name_alpha)
      local cpu_label = "CPU "
      local cpu_val = string.format("%02d%%", cpu_n)
      local conn_label = "CONN "
      local conn_val = string.format("%02d", conn_n)
      local unk_label = "UNKWN "
      local unk_val = string.format("%02d", unk_n)
      local sep = " | "

      local w_cpu_label = text_width(cr, cpu_label, ap_font, ap_size)
      local w_cpu_val = text_width(cr, cpu_val, ap_font, ap_size)
      local w_sep = text_width(cr, sep, ap_font, ap_size)
      local w_conn_label = text_width(cr, conn_label, ap_font, ap_size)
      local w_conn_val = text_width(cr, conn_val, ap_font, ap_size)
      local w_unk_label = text_width(cr, unk_label, ap_font, ap_size)
      local w_unk_val = text_width(cr, unk_val, ap_font, ap_size)
      local total_w = w_cpu_label + w_cpu_val + w_sep + w_conn_label + w_conn_val + w_sep + w_unk_label + w_unk_val
      local x = ap_value_x - total_w

      util.draw_text_left(cr, x, y, cpu_label, ap_font, ap_size, label_color, label_alpha)
      x = x + w_cpu_label
      util.draw_text_left(cr, x, y, cpu_val, ap_font, ap_size, ap_color, ap_alpha)
      x = x + w_cpu_val
      util.draw_text_left(cr, x, y, sep, ap_font, ap_size, ap_color, ap_alpha)
      x = x + w_sep
      util.draw_text_left(cr, x, y, conn_label, ap_font, ap_size, label_color, label_alpha)
      x = x + w_conn_label
      util.draw_text_left(cr, x, y, conn_val, ap_font, ap_size, ap_color, ap_alpha)
      x = x + w_conn_val
      util.draw_text_left(cr, x, y, sep, ap_font, ap_size, ap_color, ap_alpha)
      x = x + w_sep
      util.draw_text_left(cr, x, y, unk_label, ap_font, ap_size, label_color, label_alpha)
      x = x + w_unk_label
      local unk_val_color = (unk_n >= 1) and unk_value_color or ap_color
      local unk_val_alpha = (unk_n >= 1) and unk_value_alpha or ap_alpha
      util.draw_text_left(cr, x, y, unk_val, ap_font, ap_size, unk_val_color, unk_val_alpha)
      y = y + line_h

      local function draw_device_line(line, col, alpha)
        if line ~= "" then
          local a = alpha or ap_device_alpha
          if ap_device_align == "left" then
            util.draw_text_left(cr, ap_device_left_x, y, line, ap_device_font, ap_device_size, col, a)
          else
            util.draw_text_center(cr, ap_device_center_x, y, line, ap_device_font, ap_device_size, col, a)
          end
          y = y + ap_device_line_h
        end
      end

      local line_names = ""
      for i, name in ipairs(ap.known or {}) do
        local raw = tostring(name or "")
        local piece = (line_names == "" and raw or (line_names .. ", " .. raw))
        if text_width(cr, piece, ap_device_font, ap_device_size) > ap_device_max_w and line_names ~= "" then
          draw_device_line(line_names .. ",", ap_device_color)
          line_names = raw
        else
          line_names = piece
        end
      end
      if line_names ~= "" then
        draw_device_line(line_names, ap_device_color)
      end

      if ap.unknown and #ap.unknown > 0 then
        local unk_list_color = unk_ip_color
        local line_ips = ""
        for i, ip in ipairs(ap.unknown) do
          local raw = tostring(ip or "")
          local piece = (line_ips == "" and raw or (line_ips .. ", " .. raw))
          if text_width(cr, piece, ap_device_font, ap_device_size) > ap_device_max_w and line_ips ~= "" then
            draw_device_line(line_ips .. ",", unk_list_color, unk_ip_alpha)
            line_ips = raw
          else
            line_ips = piece
          end
        end
        if line_ips ~= "" then
          draw_device_line(line_ips, unk_list_color, unk_ip_alpha)
        end
      end

      y = y + line_h
    end
  end

  local pf_cfg = cfg.pfsense or {}
  local pf_enabled = pf_cfg.enabled ~= false
  if pf_enabled then
    y = y + (line_h * 3)
    local pf_flow_base = y
    local pf_hr_y = hr_cfg.pfsense_line_y
    if hr_cfg.pfsense_line_follow then
      pf_hr_y = pf_flow_base + (tonumber(hr_cfg.pfsense_line_offset) or 0)
    end
    draw_hr_at(pf_hr_y)
    if hr_cfg.pfsense_line_follow then
      y = pf_hr_y + line_h
    end
    if pf_cfg.follow_flow == false then
      y = tonumber(pf_cfg.text_y) or (pf_hr_y + line_h)
    end

    -- pfSense block
    local pf_version = pf_cfg.version or "--"
    local pf_cpu = pf_cfg.cpu or "N5105"
    local pf_bios = pf_cfg.bios or "0.9.3"
    local pf_sys = (get_pf_data().system or {})
    if pf_sys.version and pf_sys.version ~= "" then
      pf_version = tostring(pf_sys.version):gsub("%-RELEASE.*$", "")
    end
    if pf_sys.bios_version and pf_sys.bios_version ~= "" then
      local b = tostring(pf_sys.bios_version)
      local v = b:match("v%d+%.%d+%.%d+") or b:match("v%d+%.%d+")
      if v then
        pf_bios = v:gsub("^v", "")
      else
        pf_bios = b:match("%d+%.%d+%.%d+") or b:match("%d+%.%d+") or b
      end
    end
    local pf_center_x = tonumber(pf_cfg.text_center_x) or (pad + ((content_right - pad) / 2))
    local pf_center_off = tonumber(pf_cfg.text_center_offset_x) or 0
    local function draw_centered_segments(segments, y_pos)
      local total_w = 0
      for _, seg in ipairs(segments) do
        total_w = total_w + text_width(cr, seg.text, title_font, text_size)
      end
      local x = (pf_center_x + pf_center_off) - (total_w / 2)
      for _, seg in ipairs(segments) do
        util.draw_text_left(cr, x, y_pos, seg.text, title_font, text_size, seg.color, seg.alpha)
        x = x + text_width(cr, seg.text, title_font, text_size)
      end
    end

    draw_centered_segments({
      { text = "SYSTEM ",      color = label_color, alpha = label_alpha },
      { text = "PFSENSE",      color = value_color, alpha = value_alpha },
      { text = " | HARDWARE ", color = label_color, alpha = label_alpha },
      { text = "V1211",        color = value_color, alpha = value_alpha },
    }, y)
    y = y + line_h

    draw_centered_segments({
      { text = "VERSION ",           color = label_color, alpha = label_alpha },
      { text = tostring(pf_version), color = value_color, alpha = value_alpha },
      { text = " | CPU ",            color = label_color, alpha = label_alpha },
      { text = tostring(pf_cpu),     color = value_color, alpha = value_alpha },
      { text = " | BIOS ",           color = label_color, alpha = label_alpha },
      { text = tostring(pf_bios),    color = value_color, alpha = value_alpha },
    }, y)
    y = y + line_h

    do
      local load_cfg = (t.pf and t.pf.load) or {}
      local win = tonumber(load_cfg.window) or 5
      if win ~= 1 and win ~= 5 and win ~= 15 then win = 5 end
      local load_val = tonumber(pf_sys["load_" .. tostring(win)] or "")
      local load_str = load_val and string.format("%.2f", load_val) or "?"

      local cores_cfg = load_cfg.cores
      local cores = nil
      local cores_star = ""
      if cores_cfg == nil or cores_cfg == "auto" then
        cores = tonumber(pf_sys.ncpu or "")
        if not cores or cores <= 0 then
          cores = 4
          cores_star = "*"
        end
      else
        cores = tonumber(cores_cfg)
        if not cores or cores <= 0 then
          cores = 4
          cores_star = "*"
        end
      end

      local load_lbl = string.format("L%d %s / %dc%s", win, load_str, cores, cores_star)
      draw_centered_segments({
        { text = "LOAD ",  color = label_color, alpha = label_alpha },
        { text = load_lbl, color = value_color, alpha = value_alpha },
      }, y)
      y = y + line_h
    end

    -- pfSense totals + status blocks
    local pf_blocks_y = y + line_h
    draw_pfsense_totals(pf_blocks_y, pf_center_x, pf_center_off)
    draw_pfsense_status(pf_blocks_y, pf_center_x, pf_center_off)
  end
  if did_translate then
    cairo_restore(cr)
  end
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_draw_system()
  if conky_window == nil then return end
  local t = util.get_theme()
  local sys = t.system or {}
  if sys.enabled == false then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local scale = util.scale
  local base_cx = (w / 2) + scale(tonumber(sys.center_x_offset) or 0)
  local base_cy = (h / 2) + scale(tonumber(sys.center_y_offset) or 0)
  local circle = sys.circle or {}
  local circle_outer = sys.circle_outer or {}
  local center_x = base_cx
  local center_y = base_cy + scale(tonumber(circle.offset_y) or 0)

  if circle.enabled ~= false then
    local radius = scale(tonumber(circle.radius) or 115)
    local stroke = scale(tonumber(circle.stroke_width) or 4.0)
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
    local stroke_col = circle.stroke_color or { 0.20, 0.20, 0.20 }
    local stroke_alpha = tonumber(circle.stroke_alpha) or 0.90

    if fill_alpha > 0 then
      util.set_rgba(cr, fill_col, fill_alpha)
      cairo_arc(cr, center_x, center_y, radius, 0, 2 * math.pi)
      cairo_fill(cr)
    end
    if stroke > 0 and stroke_alpha > 0 then
      util.set_rgba(cr, stroke_col, stroke_alpha)
      cairo_set_line_width(cr, stroke)
      cairo_arc(cr, center_x, center_y, radius, 0, 2 * math.pi)
      cairo_stroke(cr)
    end
    if circle_outer.enabled ~= false then
      local outer_stroke = scale(tonumber(circle_outer.stroke_width) or 8.0)
      local outer_offset = scale(tonumber(circle_outer.radius_offset) or 10)
      local outer_radius = scale(tonumber(circle_outer.radius) or (radius + outer_offset))
      local outer_col = circle_outer.stroke_color or { 1.00, 1.00, 1.00 }
      local outer_alpha = tonumber(circle_outer.stroke_alpha) or 0.30
      if outer_stroke > 0 and outer_alpha > 0 then
        util.set_rgba(cr, outer_col, outer_alpha)
        cairo_set_line_width(cr, outer_stroke)
        cairo_arc(cr, center_x, center_y, outer_radius, 0, 2 * math.pi)
        cairo_stroke(cr)
      end
    end
  end

  local center_label = sys.center_label or {}
  if center_label.enabled ~= false then
    local label_font = center_label.font
    if not label_font or label_font == "auto" then
      label_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local label_size = scale(tonumber(center_label.size) or 18)
    local label_color = center_label.color or { 0.00, 0.00, 0.00 }
    local label_alpha = tonumber(center_label.alpha) or 1
    local ox = scale(tonumber(center_label.offset_x) or 0)
    local oy = scale(tonumber(center_label.offset_y) or 0)
    util.draw_text_center(cr, center_x + ox, center_y + oy, tostring(center_label.text or "SYS"),
      label_font, label_size, label_color, label_alpha)
  end

  local os_label = sys.os_label or {}
  if os_label.enabled ~= false then
    local os_text = os_label.text
    if not os_text or os_text == "" or os_text == "auto" then
      os_text = os_label_text()
    end
    if os_text and os_text ~= "" then
      local os_font = os_label.font
      if not os_font or os_font == "auto" then
        os_font = center_label.font
        if not os_font or os_font == "auto" then
          os_font = (t.fonts and t.fonts.title) or "Sans"
        end
      end
      local os_size = scale(tonumber(os_label.size) or 16)
      local os_color = os_label.color or (center_label.color or { 0.00, 0.00, 0.00 })
      local os_alpha = tonumber(os_label.alpha) or 0.70
      local ox = scale(tonumber(os_label.offset_x) or 0)
      local oy = scale(tonumber(os_label.offset_y) or -18)
      util.draw_text_center(cr, center_x + ox, center_y + oy, tostring(os_text), os_font, os_size, os_color, os_alpha)
    end
  end

  local kernel_label = sys.kernel_label or {}
  if kernel_label.enabled ~= false then
    local k_text = kernel_label.text
    if not k_text or k_text == "" or k_text == "auto" then
      k_text = trim(cparse("${kernel}"))
      if k_text ~= "" then
        if k_text:find("generic") then
          k_text = k_text:gsub("generic.*$", "g")
        else
          k_text = k_text:gsub("([%-_])([A-Za-z]).*$", "%1%2")
        end
      end
    end
    if k_text and k_text ~= "" then
      local k_font = kernel_label.font
      if not k_font or k_font == "auto" then
        k_font = center_label.font
        if not k_font or k_font == "auto" then
          k_font = (t.fonts and t.fonts.title) or "Sans"
        end
      end
      local k_size = scale(tonumber(kernel_label.size) or 10)
      local k_color = kernel_label.color or { 1.00, 1.00, 1.00 }
      local k_alpha = tonumber(kernel_label.alpha) or 0.70
      local ox = scale(tonumber(kernel_label.offset_x) or 0)
      local oy = scale(tonumber(kernel_label.offset_y) or -30)
      util.draw_text_center(cr, center_x + ox, center_y + oy, tostring(k_text), k_font, k_size, k_color, k_alpha)
    end
  end

  local os_age = sys.os_age or {}
  if os_age.enabled ~= false then
    local birth_ts = nil
    local raw_val = os_age.value
    if raw_val and raw_val ~= "" and raw_val ~= "auto" then
      local raw = trim(cparse(tostring(raw_val)))
      birth_ts = tonumber(raw) or tonumber(raw:match("(%d+)"))
    end
    if not birth_ts or birth_ts <= 0 then
      local root_path = tostring(os_age.root_path or (sys.disk_label and sys.disk_label.root_path) or "/")
      birth_ts = get_root_birth_ts(root_path, os_age.poll, os_age.fallback_mtime)
    end
    if birth_ts and birth_ts > 0 then
      local days = math.floor((os.time() - birth_ts) / 86400)
      if days < 0 then days = 0 end
      local digits = tonumber(os_age.pad_digits) or 4
      if digits < 1 then digits = 1 end
      local fmt = os_age.format
      local value = string.format("%0" .. digits .. "dd", days)
      if fmt and fmt ~= "" and fmt ~= "auto" then
        local ok, out = pcall(string.format, fmt, days)
        if ok and out and out ~= "" then
          value = out
        end
      end

      local a_font = os_age.font
      if not a_font or a_font == "auto" then
        a_font = (t.fonts and t.fonts.value) or "Sans"
      end
      local a_size = scale(tonumber(os_age.size) or 12)
      local a_color = os_age.color or { 0.40, 0.08, 0.12 }
      local a_alpha = tonumber(os_age.alpha) or 0.90
      local a_ox = scale(tonumber(os_age.offset_x) or 0)
      local a_oy = scale(tonumber(os_age.offset_y) or 8)
      util.draw_text_center(cr, center_x + a_ox, center_y + a_oy, tostring(value),
        a_font, a_size, a_color, a_alpha)
    end
  end

  local disk_label = sys.disk_label or {}
  if disk_label.enabled ~= false then
    local d_font = disk_label.font
    if not d_font or d_font == "auto" then
      d_font = center_label.font
      if not d_font or d_font == "auto" then
        d_font = (t.fonts and t.fonts.title) or "Sans"
      end
    end
    local d_size = scale(tonumber(disk_label.size) or 14)
    local d_color = disk_label.color or { 1.00, 1.00, 1.00 }
    local d_alpha = tonumber(disk_label.alpha) or 0.70
    local d_ox = scale(tonumber(disk_label.offset_x) or 0)
    local d_oy = scale(tonumber(disk_label.offset_y) or 30)
    local d_line_h = scale(tonumber(disk_label.line_h) or (d_size + 2))
    local root_label = tostring(disk_label.root_label or "/ROOT")
    local wd_label = tostring(disk_label.wd_label or "/WD_BLACK")
    local root_path = tostring(disk_label.root_path or "/")
    local wd_path = tostring(disk_label.wd_path or WD_BLACK_PATH)

    local root_used = trim(cparse("${fs_used_perc " .. root_path .. "}"))
    if root_used == "" then root_used = "0" end
    local wd_used = trim(cparse("${fs_used_perc " .. wd_path .. "}"))
    if wd_used == "" then wd_used = "0" end

    util.draw_text_center(cr, center_x + d_ox, center_y + d_oy,
      string.format("%s %s%%", root_label, root_used), d_font, d_size, d_color, d_alpha)
    util.draw_text_center(cr, center_x + d_ox, center_y + d_oy + d_line_h,
      string.format("%s %s%%", wd_label, wd_used), d_font, d_size, d_color, d_alpha)
  end

  local meters = sys.meters or {}
  if meters.enabled ~= false then
    local circle = sys.circle or {}
    local radius = scale(tonumber(circle.radius) or 115)
    local meter_radius = radius + scale(tonumber(meters.radius_offset) or 0)
    local meter_width = scale(tonumber(meters.stroke_width) or 6)
    local meter_alpha = tonumber(meters.alpha) or 0.9

    local cpu_pct = parse_pct(meters.value_cpu) / 100
    local ram_pct = parse_pct(meters.value_ram) / 100
    local gpu_pct = parse_pct(meters.value_gpu) / 100
    local vrm_pct = parse_pct(meters.value_vrm) / 100

    local a_3 = 0
    local a_12 = math.rad(90)
    local a_9 = math.rad(180)
    local a_6 = math.rad(270)

    local labels = meters.labels or {}
    local swap_tb = meters.swap_top_bottom == true
    local top_left_pct = swap_tb and gpu_pct or cpu_pct
    local top_right_pct = swap_tb and vrm_pct or ram_pct
    local bottom_left_pct = swap_tb and cpu_pct or gpu_pct
    local bottom_right_pct = swap_tb and ram_pct or vrm_pct

    local top_left_label = swap_tb and (labels.GPU or "GPU") or (labels.CPU or "CPU")
    local top_right_label = swap_tb and (labels.VRM or "VRM") or (labels.RAM or "RAM")
    local bottom_left_label = swap_tb and (labels.CPU or "CPU") or (labels.GPU or "GPU")
    local bottom_right_label = swap_tb and (labels.RAM or "RAM") or (labels.VRM or "VRM")

    local top_left_color = swap_tb and meters.gpu_color or meters.cpu_color
    local top_right_color = swap_tb and meters.vrm_color or meters.ram_color
    local bottom_left_color = swap_tb and meters.cpu_color or meters.gpu_color
    local bottom_right_color = swap_tb and meters.ram_color or meters.vrm_color

    -- Quadrant meters
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_9, a_12, top_left_pct, top_left_color, meter_alpha,
      meter_width, true)  -- TOP-LEFT: 9 -> 12 (clockwise)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_3, a_12, top_right_pct, top_right_color, meter_alpha,
      meter_width, false) -- TOP-RIGHT: 3 -> 12 (ccw)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_9, a_6, bottom_left_pct, bottom_left_color, meter_alpha,
      meter_width, false) -- BOTTOM-LEFT: 9 -> 6 (ccw)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_3, a_6, bottom_right_pct, bottom_right_color, meter_alpha,
      meter_width, true)  -- BOTTOM-RIGHT: 3 -> 6 (clockwise)

    -- Quadrant labels
    local label_font = meters.label_font
    if not label_font or label_font == "auto" then
      label_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local label_size = scale(tonumber(meters.label_size) or 14)
    local label_color = meters.label_color or { 0.20, 0.20, 0.20 }
    local label_alpha = tonumber(meters.label_alpha) or 0.9
    local label_offset = scale(tonumber(meters.label_offset) or -22)
    local label_radius = meter_radius + label_offset

    local function draw_label_at(angle, text)
      if not text or text == "" then return end
      draw_text_arc(cr, center_x, center_y, label_radius, angle, text, label_font, label_size, label_color, label_alpha)
    end

    draw_label_at(math.rad(135), top_left_label)
    draw_label_at(math.rad(45), top_right_label)
    draw_label_at(math.rad(225), bottom_left_label)
    draw_label_at(math.rad(315), bottom_right_label)
  end

  local ticks = sys.ticks or {}
  if ticks.enabled ~= false then
    local radius = scale(tonumber(circle.radius) or 115)
    local len = scale(tonumber(ticks.length) or 12)
    local width = scale(tonumber(ticks.width) or 3)
    local offset = scale(tonumber(ticks.offset) or 4)
    local col = ticks.color or { 0.40, 0.08, 0.12 }
    local alpha = tonumber(ticks.alpha) or 0.70
    local r0 = radius + offset
    local r1 = r0 + len
    local angles = { 0, math.pi / 2, math.pi, math.pi * 1.5 }
    util.set_rgba(cr, col, alpha)
    cairo_set_line_width(cr, width)
    for _, a in ipairs(angles) do
      local x0 = center_x + (r0 * math.cos(a))
      local y0 = center_y + (r0 * math.sin(a))
      local x1 = center_x + (r1 * math.cos(a))
      local y1 = center_y + (r1 * math.sin(a))
      cairo_move_to(cr, x0, y0)
      cairo_line_to(cr, x1, y1)
      cairo_stroke(cr)
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_draw_network()
  if conky_window == nil then return end
  local t = util.get_theme()
  local net = t.network or {}
  if net.enabled == false then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local scale = util.scale
  local base_cx = (w / 2) + scale(tonumber(net.center_x_offset) or 0)
  local base_cy = (h / 2) + scale(tonumber(net.center_y_offset) or 0)
  local circle = net.circle or {}
  local circle_outer = net.circle_outer or {}
  local center_x = base_cx
  local center_y = base_cy + scale(tonumber(circle.offset_y) or 0)

  if circle.enabled ~= false then
    local radius = scale(tonumber(circle.radius) or 115)
    local stroke = scale(tonumber(circle.stroke_width) or 4.0)
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
    local stroke_col = circle.stroke_color or { 0.20, 0.20, 0.20 }
    local stroke_alpha = tonumber(circle.stroke_alpha) or 0.90

    if fill_alpha > 0 then
      util.set_rgba(cr, fill_col, fill_alpha)
      cairo_arc(cr, center_x, center_y, radius, 0, 2 * math.pi)
      cairo_fill(cr)
    end
    if stroke > 0 and stroke_alpha > 0 then
      util.set_rgba(cr, stroke_col, stroke_alpha)
      cairo_set_line_width(cr, stroke)
      cairo_arc(cr, center_x, center_y, radius, 0, 2 * math.pi)
      cairo_stroke(cr)
    end
    if circle_outer.enabled ~= false then
      local outer_stroke = scale(tonumber(circle_outer.stroke_width) or 8.0)
      local outer_offset = scale(tonumber(circle_outer.radius_offset) or 10)
      local outer_radius = scale(tonumber(circle_outer.radius) or (radius + outer_offset))
      local outer_col = circle_outer.stroke_color or { 1.00, 1.00, 1.00 }
      local outer_alpha = tonumber(circle_outer.stroke_alpha) or 0.30
      if outer_stroke > 0 and outer_alpha > 0 then
        util.set_rgba(cr, outer_col, outer_alpha)
        cairo_set_line_width(cr, outer_stroke)
        cairo_arc(cr, center_x, center_y, outer_radius, 0, 2 * math.pi)
        cairo_stroke(cr)
      end
    end
  end

  local center_label = net.center_label or {}
  if center_label.enabled ~= false then
    local label_font = center_label.font
    if not label_font or label_font == "auto" then
      label_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local label_size = scale(tonumber(center_label.size) or 18)
    local label_color = center_label.color or { 0.00, 0.00, 0.00 }
    local label_alpha = tonumber(center_label.alpha) or 1
    local ox = scale(tonumber(center_label.offset_x) or 0)
    local oy = scale(tonumber(center_label.offset_y) or 0)
    util.draw_text_center(cr, center_x + ox, center_y + oy, tostring(center_label.text or "NET"),
      label_font, label_size, label_color, label_alpha)
  end

  local status_label = net.status_label or {}
  if status_label.enabled ~= false then
    local st_font = status_label.font
    if not st_font or st_font == "auto" then
      st_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local st_size = scale(tonumber(status_label.size) or 14)
    local st_color = status_label.color or { 1.00, 1.00, 1.00 }
    local st_alpha = tonumber(status_label.alpha) or 1
    local st_ox = scale(tonumber(status_label.offset_x) or 0)
    local st_oy = scale(tonumber(status_label.offset_y) or -18)
    local st = trim(cparse("${execi 15 " .. SUITE_DIR .. "/scripts/net_extras.sh wan_status}"))
    if st == "" then st = "--" end
    st = st:upper()
    util.draw_text_center(cr, center_x + st_ox, center_y + st_oy, st, st_font, st_size, st_color, st_alpha)
  end

  local wan_label = net.wan_label or {}
  if wan_label.enabled ~= false then
    local wl_font = wan_label.font
    if not wl_font or wl_font == "auto" then
      wl_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local wl_size = scale(tonumber(wan_label.size) or 12)
    local wl_color = wan_label.color or { 1.00, 1.00, 1.00 }
    local wl_alpha = tonumber(wan_label.alpha) or 0.9
    local wl_ox = scale(tonumber(wan_label.offset_x) or 0)
    local wl_oy = scale(tonumber(wan_label.offset_y) or 20)
    refresh_wan_ip()
    local wan_ip = trim(cparse("${execi 15 " .. SUITE_DIR .. "/scripts/wan_read.sh}"))
    if wan_ip == "" then wan_ip = "--" end
    util.draw_text_center(cr, center_x + wl_ox, center_y + wl_oy, wan_ip, wl_font, wl_size, wl_color, wl_alpha)

    local vpn_label = trim(cparse("${execi 15 " .. SUITE_DIR .. "/scripts/net_extras.sh wan_ip_label}"))
    if vpn_label:find("VPN") then
      local v_text = tostring(wan_label.vpn_text or "V")
      if v_text ~= "" then
        local v_size = scale(tonumber(wan_label.vpn_size) or (wl_size - 2))
        local v_oy = scale(tonumber(wan_label.vpn_offset_y) or 12)
        local v_color = wan_label.vpn_color or wl_color
        local v_alpha = tonumber(wan_label.vpn_alpha) or wl_alpha
        util.draw_text_center(cr, center_x + wl_ox, center_y + wl_oy + v_oy, v_text, wl_font, v_size, v_color, v_alpha)
      end
    end
  end

  local meters = net.meters or {}
  if meters.enabled ~= false then
    local circle = net.circle or {}
    local radius = scale(tonumber(circle.radius) or 115)
    local meter_radius = radius + scale(tonumber(meters.radius_offset) or 0)
    local meter_width = scale(tonumber(meters.stroke_width) or 6)
    local meter_alpha = tonumber(meters.alpha) or 0.9

    local iface = tostring(net.iface or "eno1")
    local up_kib = to_num(trim(cparse("${upspeedf " .. iface .. "}")))
    local down_kib = to_num(trim(cparse("${downspeedf " .. iface .. "}")))
    local up_mbps = up_kib * 8 / 1024
    local down_mbps = down_kib * 8 / 1024
    local max_up = tonumber(meters.max_up_mbps) or 100
    local max_down = tonumber(meters.max_down_mbps) or 100
    local up_pct = max_up > 0 and clamp(up_mbps / max_up, 0, 1) or 0
    local down_pct = max_down > 0 and clamp(down_mbps / max_down, 0, 1) or 0

    local ping1 = trim(cparse(
      "${execi 10 sh -c 'h=1.1.1.1; t=$(ping -n -c1 -W1 $h 2>/dev/null | grep -o \"time=[0-9.]*\" | head -n1 | cut -d= -f2); [ -n \"$t\" ] && echo \"$t\" || echo \"0\"'}"))
    local ping2 = trim(cparse(
      "${execi 10 sh -c 'h=8.8.8.8; t=$(ping -n -c1 -W1 $h 2>/dev/null | grep -o \"time=[0-9.]*\" | head -n1 | cut -d= -f2); [ -n \"$t\" ] && echo \"$t\" || echo \"0\"'}"))
    local ping1_ms = to_num(ping1)
    local ping2_ms = to_num(ping2)
    local max_ping = tonumber(meters.max_ping_ms) or 200
    local ping1_pct = max_ping > 0 and clamp(ping1_ms / max_ping, 0, 1) or 0
    local ping2_pct = max_ping > 0 and clamp(ping2_ms / max_ping, 0, 1) or 0

    local smoothing = meters.smoothing or {}
    local alpha = tonumber(smoothing.alpha) or 0.35
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    if net_ema.up == nil then net_ema.up = up_pct end
    if net_ema.down == nil then net_ema.down = down_pct end
    if net_ema.p1 == nil then net_ema.p1 = ping1_pct end
    if net_ema.p2 == nil then net_ema.p2 = ping2_pct end
    net_ema.up = alpha * up_pct + (1 - alpha) * net_ema.up
    net_ema.down = alpha * down_pct + (1 - alpha) * net_ema.down
    net_ema.p1 = alpha * ping1_pct + (1 - alpha) * net_ema.p1
    net_ema.p2 = alpha * ping2_pct + (1 - alpha) * net_ema.p2

    local a_3 = 0
    local a_12 = math.rad(90)
    local a_9 = math.rad(180)
    local a_6 = math.rad(270)

    local labels = meters.labels or {}
    local swap_ud = meters.swap_up_down == true
    local up_pct = swap_ud and net_ema.down or net_ema.up
    local down_pct = swap_ud and net_ema.up or net_ema.down
    local up_label = swap_ud and (labels.DOWN or "DOWN") or (labels.UP or "UP")
    local down_label = swap_ud and (labels.UP or "UP") or (labels.DOWN or "DOWN")
    local up_color = swap_ud and meters.down_color or meters.up_color
    local down_color = swap_ud and meters.up_color or meters.down_color

    draw_arc_meter(cr, center_x, center_y, meter_radius, a_9, a_12, up_pct, up_color, meter_alpha,
      meter_width, true)  -- UP: 9 -> 12 (clockwise)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_9, a_6, down_pct, down_color, meter_alpha,
      meter_width, false) -- DOWN: 9 -> 6 (ccw)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_3, a_12, net_ema.p1, meters.ping1_color, meter_alpha,
      meter_width, false) -- 1.1.1.1: 3 -> 12 (ccw)
    draw_arc_meter(cr, center_x, center_y, meter_radius, a_3, a_6, net_ema.p2, meters.ping2_color, meter_alpha,
      meter_width, true)  -- 8.8.8.8: 3 -> 6 (clockwise)

    local label_font = meters.label_font
    if not label_font or label_font == "auto" then
      label_font = (t.fonts and t.fonts.title) or "Sans"
    end
    local label_size = scale(tonumber(meters.label_size) or 14)
    local label_color = meters.label_color or { 0.20, 0.20, 0.20 }
    local label_alpha = tonumber(meters.label_alpha) or 0.9
    local label_offset = scale(tonumber(meters.label_offset) or -17)
    local label_radius = meter_radius + label_offset
    local value_font = meters.value_font or "Nimbus Mono PS"
    local value_size = scale(tonumber(meters.value_size) or 12)
    local value_color = meters.value_color or { 1.00, 1.00, 1.00 }
    local value_alpha = tonumber(meters.value_alpha) or 0.9
    local value_offset = scale(tonumber(meters.value_offset) or -34)
    local value_radius = meter_radius + value_offset
    local function draw_label_at(angle, text)
      if not text or text == "" then return end
      draw_text_arc(cr, center_x, center_y, label_radius, angle, text, label_font, label_size, label_color, label_alpha)
    end

    local function draw_value_at(angle, text)
      if not text or text == "" then return end
      local vx = center_x + (value_radius * math.cos(angle))
      local vy = center_y + (value_radius * math.sin(angle))
      util.draw_text_center(cr, vx, vy, text, value_font, value_size, value_color, value_alpha)
    end

    draw_label_at(math.rad(135), up_label)
    draw_label_at(math.rad(225), down_label)
    draw_label_at(math.rad(45), labels.P1 or "1.1.1.1")
    draw_label_at(math.rad(315), labels.P2 or "8.8.8.8")

    draw_value_at(math.rad(135), string.format("%.0f", up_kib))
    draw_value_at(math.rad(225), string.format("%.0f", down_kib))
    draw_value_at(math.rad(45), string.format("%.0f", ping1_ms))
    draw_value_at(math.rad(315), string.format("%.0f", ping2_ms))
  end

  local ticks = net.ticks or {}
  if ticks.enabled ~= false then
    local radius = scale(tonumber(circle.radius) or 115)
    local len = scale(tonumber(ticks.length) or 12)
    local width = scale(tonumber(ticks.width) or 3)
    local offset = scale(tonumber(ticks.offset) or 4)
    local col = ticks.color or { 0.40, 0.08, 0.12 }
    local alpha = tonumber(ticks.alpha) or 0.70
    local r0 = radius + offset
    local r1 = r0 + len
    local angles = { 0, math.pi / 2, math.pi, math.pi * 1.5 }
    util.set_rgba(cr, col, alpha)
    cairo_set_line_width(cr, width)
    for _, a in ipairs(angles) do
      local x0 = center_x + (r0 * math.cos(a))
      local y0 = center_y + (r0 * math.sin(a))
      local x1 = center_x + (r1 * math.cos(a))
      local y1 = center_y + (r1 * math.sin(a))
      cairo_move_to(cr, x0, y0)
      cairo_line_to(cr, x1, y1)
      cairo_stroke(cr)
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
