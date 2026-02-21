--[[
  ${CONKY_SUITE_DIR}/lua/widgets/station_model.lua
  METAR-driven station model widget.
]]

require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local get_theme = util.get_theme
local scale = util.scale
local set_rgba = util.set_rgba
local draw_text_center = util.draw_text_center
local draw_text_left = util.draw_text_left
local read_file = util.read_file
local parse_vars_file = util.parse_vars_file

local METAR_CACHE = { ts = 0, raw = "" }
local SEASON_CACHE = { ts = 0, label = nil }

local function utf8_char(code)
  if utf8 and utf8.char then return utf8.char(code) end
  if code <= 0x7F then
    return string.char(code)
  elseif code <= 0x7FF then
    local b1 = 0xC0 + math.floor(code / 0x40)
    local b2 = 0x80 + (code % 0x40)
    return string.char(b1, b2)
  elseif code <= 0xFFFF then
    local b1 = 0xE0 + math.floor(code / 0x1000)
    local b2 = 0x80 + (math.floor(code / 0x40) % 0x40)
    local b3 = 0x80 + (code % 0x40)
    return string.char(b1, b2, b3)
  else
    local b1 = 0xF0 + math.floor(code / 0x40000)
    local b2 = 0x80 + (math.floor(code / 0x1000) % 0x40)
    local b3 = 0x80 + (math.floor(code / 0x40) % 0x40)
    local b4 = 0x80 + (code % 0x40)
    return string.char(b1, b2, b3, b4)
  end
end

local function draw_text_right(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y)
  cairo_show_text(cr, txt)
end

local function draw_text_left_centered(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  local cy = y - (ext.height / 2 + ext.y_bearing)
  cairo_move_to(cr, x, cy)
  cairo_show_text(cr, txt)
end

local function draw_text_right_centered(cr, x, y, txt, font_face, font_size, col, alpha)
  if txt == nil or txt == "" then return end
  set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  local cy = y - (ext.height / 2 + ext.y_bearing)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), cy)
  cairo_show_text(cr, txt)
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

local function text_width(cr, txt, font_face, font_size)
  if txt == nil or txt == "" then return 0 end
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  return ext.width + ext.x_bearing
end

local function normalize_metar(s)
  if not s then return "" end
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
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

local function get_file_mtime(path)
  local cmd = string.format("stat -c %%Y %q 2>/dev/null", path)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  local ts = tonumber(out:match("(%d+)"))
  return ts
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

local function fetch_metar(sm)
  local ttl = tonumber(sm.cache_ttl) or 60
  local now = os.time()
  if sm.debug_metar and sm.debug_metar ~= "" then
    local ob = extract_ob_line(sm.debug_metar)
    if ob == "" then ob = normalize_metar(sm.debug_metar) end
    return ob
  end
  if METAR_CACHE.raw ~= "" and (now - METAR_CACHE.ts) < ttl then
    return METAR_CACHE.raw
  end

  local station = sm.station or "KMEM"
  local cache_path = sm.cache_path
  if cache_path == nil or cache_path == "" then
    cache_path = CACHE_DIR .. "/metar_" .. station .. "_raw.txt"
  elseif cache_path:find("%%s") then
    cache_path = string.format(cache_path, station)
  end
  local cache_mtime = get_file_mtime(cache_path)
  if cache_mtime and (now - cache_mtime) < ttl then
    local raw_cache = util.read_file(cache_path)
    local ob = extract_ob_line(raw_cache)
    if ob ~= "" then
      METAR_CACHE.raw = ob
      METAR_CACHE.ts = now
      return ob
    end
  end

  local wrap_col = tonumber(sm.wrap_col) or 240
  local cmd = string.format("%q %q %d",
    SUITE_DIR .. "/scripts/metar_ob.sh", station, wrap_col)
  local p = io.popen(cmd, "r")
  if not p then return METAR_CACHE.raw or "" end
  local raw = p:read("*a") or ""
  p:close()
  raw = normalize_metar(raw)
  if raw == "" and cache_mtime then
    local raw_cache = util.read_file(cache_path)
    raw = extract_ob_line(raw_cache)
  end
  if raw ~= "" then
    METAR_CACHE.raw = raw
    METAR_CACHE.ts = now
  end
  return METAR_CACHE.raw
end

local function temp_to_num(s)
  if not s then return nil end
  local neg = s:sub(1, 1) == "M"
  local v = tonumber(neg and s:sub(2) or s)
  if v == nil then return nil end
  if neg then v = -v end
  return v
end

local function slp_code_from_hpa(hpa)
  if not hpa then return nil end
  local tenths = math.floor(hpa * 10 + 0.5)
  local code = tenths % 1000
  return string.format("%03d", code)
end

local function inhg_to_hpa(inhg)
  if not inhg then return nil end
  return inhg * 33.8639
end

local function parse_wind(tokens)
  for _, tok in ipairs(tokens) do
    local dir_g, spd_g, gust_g = tok:match("^(%d%d%d)(%d+)G(%d+)KT$")
    if dir_g then
      return tonumber(dir_g), tonumber(spd_g), tonumber(gust_g), false
    end
    local dir, spd = tok:match("^(%d%d%d)(%d+)KT$")
    if dir then
      return tonumber(dir), tonumber(spd), nil, false
    end
    local vrb_spd_g, vrb_gust_g = tok:match("^VRB(%d+)G(%d+)KT$")
    if vrb_spd_g then
      return nil, tonumber(vrb_spd_g), tonumber(vrb_gust_g), true
    end
    local vrb_spd = tok:match("^VRB(%d+)KT$")
    if vrb_spd then
      return nil, tonumber(vrb_spd), nil, true
    end
  end
  return nil, nil, nil, false
end

local function parse_visibility(tokens)
  for i, tok in ipairs(tokens) do
    if tok:match("SM$") then
      local raw = tok
      local prev = tokens[i - 1]
      if prev and prev:match("^%d+$") and tok:match("^%d/%dSM$") then
        raw = prev .. " " .. tok
      end
      raw = raw:gsub("SM$", "")
      return raw
    end
  end
  return nil
end

local function parse_temp_dew(tokens)
  for _, tok in ipairs(tokens) do
    local t, d = tok:match("^(M?%d%d)/(M?%d%d)$")
    if t then
      return temp_to_num(t), temp_to_num(d)
    end
  end
  return nil, nil
end

local function parse_altimeter(tokens)
  for _, tok in ipairs(tokens) do
    local a = tok:match("^A(%d%d%d%d)$")
    if a then
      return tonumber(a) / 100.0, nil
    end
    local q = tok:match("^Q(%d%d%d%d)$")
    if q then
      return nil, tonumber(q)
    end
  end
  return nil, nil
end

local function parse_clouds(tokens)
  local highest = nil
  local clear = false

  for _, tok in ipairs(tokens) do
    if tok:match("^VV") or tok == "OVX" then
      return "N_9"
    end
    if tok == "SKC" or tok == "CLR" or tok == "NSC" or tok == "NCD" or tok == "CAVOK" then
      clear = true
    end
    local cov = tok:match("^(FEW)") or tok:match("^(SCT)")
        or tok:match("^(BKN)") or tok:match("^(OVC)")
    if cov == "FEW" then
      highest = math.max(highest or 0, 2)
    elseif cov == "SCT" then
      highest = math.max(highest or 0, 4)
    elseif cov == "BKN" then
      highest = math.max(highest or 0, 6)
    elseif cov == "OVC" then
      highest = math.max(highest or 0, 8)
    end
  end

  if highest then return "N_" .. tostring(highest) end
  if clear then return "N_0" end
  return "N_Slash"
end

local PHENOMENA = {
  "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP",
  "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO",
  "SQ", "FC", "SS", "DS",
}

local function has_any(list, s)
  for _, code in ipairs(list) do
    if s:find(code, 1, true) then return true end
  end
  return false
end

local function is_wx_token(tok)
  if tok == "RMK" then return false end
  if tok == "NOSIG" or tok == "AUTO" or tok == "COR" then return false end
  if tok:match("^%d%d%d%d%d?Z$") then return false end
  if tok:match("KT$") then return false end
  if tok:match("SM$") then return false end
  if tok:match("^(M?%d%d)/(M?%d%d)$") then return false end
  if tok:match("^A%d%d%d%d$") or tok:match("^Q%d%d%d%d$") then return false end
  if tok:match("^(FEW|SCT|BKN|OVC|VV|OVX|SKC|CLR|NSC|NCD)") then return false end
  if tok:match("^R%d%d") then return false end
  local t = tok
  if t:sub(1, 1) == "+" or t:sub(1, 1) == "-" then t = t:sub(2) end
  if t:sub(1, 2) == "VC" then t = t:sub(3) end
  if t:find("TS", 1, true) then return true end
  if not t:match("%a") then return false end
  return has_any(PHENOMENA, t)
end

local function parse_wx_tokens(tokens)
  local out = {}
  for _, tok in ipairs(tokens) do
    if is_wx_token(tok) then
      out[#out + 1] = tok
    end
  end
  return out
end

local function parse_rmk(tokens)
  local rmk = { slp = nil, tend_a = nil, tend_ppp = nil, precip6h = nil }
  for _, tok in ipairs(tokens) do
    local slp = tok:match("^SLP(%d%d%d)$")
    if slp then rmk.slp = slp end
    local a, ppp = tok:match("^5(%d)(%d%d%d)$")
    if a then
      rmk.tend_a = tonumber(a)
      rmk.tend_ppp = tonumber(ppp)
    end
    local precip = tok:match("^6(%d%d%d%d)$")
    if precip then
      rmk.precip6h = precip
    elseif tok:match("^6////") then
      rmk.precip6h = "/"
    end
  end
  return rmk
end

local function split_rmk(tokens)
  local main = {}
  local rmk = {}
  local in_rmk = false
  for _, tok in ipairs(tokens) do
    if tok == "RMK" then
      in_rmk = true
    elseif in_rmk then
      rmk[#rmk + 1] = tok
    else
      main[#main + 1] = tok
    end
  end
  return main, rmk
end

local function tendency_sign(a)
  if a == nil then return "" end
  if a >= 0 and a <= 3 then return "+" end
  if a >= 5 and a <= 8 then return "-" end
  return ""
end

local function tendency_glyph(a)
  if a == nil then return nil end
  if a >= 0 and a <= 3 then return utf8_char(0xE030) end
  if a == 4 then return utf8_char(0xE031) end
  if a >= 5 and a <= 8 then return utf8_char(0xE032) end
  return nil
end

local CLOUD_GLYPHS = {
  N_0 = utf8_char(0xE03A),
  N_1 = utf8_char(0xE03B),
  N_2 = utf8_char(0xE03C),
  N_3 = utf8_char(0xE03D),
  N_4 = utf8_char(0xE03E),
  N_5 = utf8_char(0xE03F),
  N_6 = utf8_char(0xE040),
  N_7 = utf8_char(0xE041),
  N_8 = utf8_char(0xE042),
  N_9 = utf8_char(0xE043),
  N_Slash = utf8_char(0xE044),
}

local function wx_glyph_for(kind, intensity, token)
  if kind == "TS" then return utf8_char(0xE004) end
  if kind == "FZRA" then
    return intensity == "-" and utf8_char(0xE016) or utf8_char(0xE017)
  end
  if kind == "FZDZ" then
    return intensity == "-" and utf8_char(0xE00C) or utf8_char(0xE00D)
  end
  if kind == "SN" then
    if intensity == "-" then return utf8_char(0xE01A) end
    if intensity == "+" then return utf8_char(0xE01E) end
    return utf8_char(0xE01C)
  end
  if kind == "PL" then return utf8_char(0xE01F) end
  if kind == "RAIN" then
    if token and token:find("DZ", 1, true) and not token:find("RA", 1, true) then
      if intensity == "-" then return utf8_char(0xE007) end
      if intensity == "+" then return utf8_char(0xE00B) end
      return utf8_char(0xE009)
    end
    if token and token:find("SH", 1, true) then
      if intensity == "-" then return utf8_char(0xE020) end
      if intensity == "+" then return utf8_char(0xE022) end
      return utf8_char(0xE021)
    end
    if intensity == "-" then return utf8_char(0xE011) end
    if intensity == "+" then return utf8_char(0xE015) end
    return utf8_char(0xE013)
  end
  if kind == "FG" then return utf8_char(0xE003) end
  if kind == "BR" then return utf8_char(0xE003) end
  if kind == "HZ" then
    if token and token:find("FU", 1, true) then return utf8_char(0xE000) end
    return utf8_char(0xE001)
  end
  return nil
end

local function classify_wx_token(tok)
  local intensity
  local t = tok
  local first = t:sub(1, 1)
  if first == "+" or first == "-" then
    intensity = first
    t = t:sub(2)
  end
  if t:sub(1, 2) == "VC" then
    t = t:sub(3)
  end

  if t:find("TS", 1, true) then
    return { rank = 1, kind = "TS", intensity = intensity, token = t }
  end
  if t:find("FZRA", 1, true) or (t:find("FZ", 1, true) and t:find("RA", 1, true)) then
    return { rank = 2, kind = "FZRA", intensity = intensity, token = t }
  end
  if t:find("FZDZ", 1, true) or (t:find("FZ", 1, true) and t:find("DZ", 1, true)) then
    return { rank = 2, kind = "FZDZ", intensity = intensity, token = t }
  end
  if t:find("SN", 1, true) then
    return { rank = 3, kind = "SN", intensity = intensity, token = t }
  end
  if t:find("PL", 1, true) then
    return { rank = 4, kind = "PL", intensity = intensity, token = t }
  end
  if t:find("RA", 1, true) or t:find("DZ", 1, true) or t:find("SH", 1, true) then
    return { rank = 5, kind = "RAIN", intensity = intensity, token = t }
  end
  if t:find("FG", 1, true) then
    return { rank = 6, kind = "FG", intensity = intensity, token = t }
  end
  if t:find("BR", 1, true) then
    return { rank = 7, kind = "BR", intensity = intensity, token = t }
  end
  if t:find("HZ", 1, true) or t:find("FU", 1, true) then
    return { rank = 8, kind = "HZ", intensity = intensity, token = t }
  end
  return nil
end

local function select_present_weather(tokens)
  local best = nil
  for _, tok in ipairs(tokens or {}) do
    local cand = classify_wx_token(tok)
    if cand and (not best or cand.rank < best.rank) then
      best = cand
    end
  end
  if not best then return nil end
  best.glyph = wx_glyph_for(best.kind, best.intensity, best.token)
  return best
end

local function parse_metar(raw)
  local out = {
    raw = raw or "",
    wind_dir_deg = nil,
    wind_speed_kt = nil,
    wind_gust_kt = nil,
    wind_is_vrb = false,
    vis_sm = nil,
    temp_c = nil,
    dew_c = nil,
    altimeter_inhg = nil,
    altimeter_hpa = nil,
    cloud_code = nil,
    slp_code = nil,
    tendency_char = nil,
    tendency_dhpa = nil,
    precip6h = nil,
    wx_tokens = {},
    present_wx = nil,
  }

  if out.raw == "" then return out end

  local tokens = {}
  for tok in out.raw:gmatch("%S+") do
    tokens[#tokens + 1] = tok
  end

  local main, rmk = split_rmk(tokens)

  out.wind_dir_deg, out.wind_speed_kt, out.wind_gust_kt, out.wind_is_vrb = parse_wind(main)
  out.vis_sm = parse_visibility(main)
  out.temp_c, out.dew_c = parse_temp_dew(main)
  out.altimeter_inhg, out.altimeter_hpa = parse_altimeter(main)
  out.cloud_code = parse_clouds(main)
  out.wx_tokens = parse_wx_tokens(main)
  out.present_wx = select_present_weather(out.wx_tokens)

  local r = parse_rmk(rmk)
  out.slp_code = r.slp
  out.tendency_char = r.tend_a
  if r.tend_ppp then
    out.tendency_dhpa = r.tend_ppp / 10.0
  end
  out.precip6h = r.precip6h

  if not out.slp_code then
    if out.altimeter_hpa then
      out.slp_code = slp_code_from_hpa(out.altimeter_hpa)
    elseif out.altimeter_inhg then
      out.slp_code = slp_code_from_hpa(inhg_to_hpa(out.altimeter_inhg))
    end
  end

  return out
end

local function value_or_slash(v)
  if v == nil then return "/" end
  if v == "" then return "/" end
  return tostring(v)
end

local function format_visibility_sm(v, use_glyphs)
  if v == nil then return nil end
  if v == "" then return "" end
  local frac_map = {
    ["1/8"] = "⅛",
    ["1/4"] = "¼",
    ["3/8"] = "⅜",
    ["1/2"] = "½",
    ["5/8"] = "⅝",
    ["3/4"] = "¾",
    ["7/8"] = "⅞",
  }
  local function decimal_from_fraction(whole, frac)
    local num, den = frac:match("^(%d+)/(%d+)$")
    if not num then return nil end
    local val = (tonumber(whole) or 0) + (tonumber(num) / tonumber(den))
    local txt = string.format("%.2f", val)
    txt = txt:gsub("0+$", ""):gsub("%.$", "")
    if txt:sub(1, 2) == "0." then
      return txt:sub(2)
    end
    return txt
  end
  if v:match("^%d+%s+%d+/%d+$") then
    local whole, frac = v:match("^(%d+)%s+(%d+/%d+)$")
    if use_glyphs ~= false then
      local glyph = frac_map[frac]
      if glyph then
        return string.format("%s%s", whole, glyph)
      end
    end
    return decimal_from_fraction(whole, frac) or v
  end
  if v:match("^%d+/%d+$") then
    if use_glyphs ~= false then
      local glyph = frac_map[v]
      if glyph then
        return glyph
      end
    end
    return decimal_from_fraction(0, v) or v
  end
  return v
end

local function format_precip6h(v)
  if v == nil then return nil end
  if v == "/" then return "/" end
  local num = tonumber(v)
  if not num then return tostring(v) end
  local txt = string.format("%.2f", num / 100.0)
  if txt:sub(1, 2) == "0." then
    return txt:sub(2)
  end
  return txt
end

local function draw_wind_barb(cr, cx, cy, data, sm, col, alpha)
  local spd = data.wind_speed_kt
  if spd == nil then return end

  local wind = sm.wind or {}
  local staff_len = scale(tonumber(wind.staff_len) or 52)
  local base_cloud = tonumber(sm.cloud_size) or 40
  local staff_start = scale(tonumber(wind.staff_start) or (base_cloud * 0.45))
  local line_width = scale(tonumber(wind.line_width) or 2.0)
  local barb_len = scale(tonumber(wind.barb_len) or 14)
  local half_len = scale(tonumber(wind.half_barb_len) or 8)
  local barb_spacing = scale(tonumber(wind.barb_spacing) or 8)
  local barb_angle = math.rad(tonumber(wind.barb_angle_deg) or 60)
  local pennant_len = scale(tonumber(wind.pennant_len) or 18)
  local pennant_width = scale(tonumber(wind.pennant_width) or 10)
  local calm_circle = wind.calm_circle ~= false
  local calm_radius = scale(tonumber(wind.calm_radius) or 8)
  local wind_col = wind.color or col
  local wind_alpha = tonumber(wind.alpha) or alpha

  local dir = data.wind_dir_deg
  if data.wind_is_vrb then dir = 0 end
  local angle = ((dir or 0) - 90) * math.pi / 180
  local ux, uy = math.cos(angle), math.sin(angle)

  if spd <= 0 then
    if calm_circle then
      set_rgba(cr, col, alpha)
      cairo_set_line_width(cr, line_width)
      cairo_new_sub_path(cr)
      cairo_arc(cr, cx, cy, calm_radius, 0, 2 * math.pi)
      cairo_stroke(cr)
    end
    return
  end

  local start_x = cx + ux * staff_start
  local start_y = cy + uy * staff_start
  local end_x = start_x + ux * staff_len
  local end_y = start_y + uy * staff_len

  set_rgba(cr, wind_col, wind_alpha)
  cairo_set_line_width(cr, line_width)
  cairo_move_to(cr, start_x, start_y)
  cairo_line_to(cr, end_x, end_y)
  cairo_stroke(cr)

  local rounded = math.floor((spd + 2.5) / 5) * 5
  local n50 = math.floor(rounded / 50)
  rounded = rounded % 50
  local n10 = math.floor(rounded / 10)
  rounded = rounded % 10
  local n5 = math.floor(rounded / 5)

  local function rot(x, y, ang)
    local ca, sa = math.cos(ang), math.sin(ang)
    return x * ca - y * sa, x * sa + y * ca
  end

  local side = tostring(wind.barb_side or "cw"):lower()
  local dir = (side == "ccw" or side == "counter" or side == "counterclockwise") and -1 or 1
  local bx, by = rot(ux, uy, barb_angle * dir)
  local offset = 0

  for _ = 1, n50 do
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    local p1x = base_x
    local p1y = base_y
    local p2x = base_x + bx * pennant_len
    local p2y = base_y + by * pennant_len
    local p3x = base_x - ux * pennant_width
    local p3y = base_y - uy * pennant_width
    cairo_move_to(cr, p1x, p1y)
    cairo_line_to(cr, p2x, p2y)
    cairo_line_to(cr, p3x, p3y)
    cairo_close_path(cr)
    cairo_fill(cr)
    offset = offset + barb_spacing
  end

  for _ = 1, n10 do
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    cairo_move_to(cr, base_x, base_y)
    cairo_line_to(cr, base_x + bx * barb_len, base_y + by * barb_len)
    cairo_stroke(cr)
    offset = offset + barb_spacing
  end

  if n5 > 0 then
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    cairo_move_to(cr, base_x, base_y)
    cairo_line_to(cr, base_x + bx * half_len, base_y + by * half_len)
    cairo_stroke(cr)
  end

  if data.wind_is_vrb and (wind.vrb_label ~= false) then
    local font = sm.font_numbers or sm.font_value or "Exo 2"
    local size = scale(tonumber(wind.vrb_size) or 12)
    local dx = scale(tonumber(wind.vrb_offset_x) or -10)
    local dy = scale(tonumber(wind.vrb_offset_y) or -52)
    local vcol = wind.vrb_color or col
    local valpha = tonumber(wind.vrb_alpha) or alpha
    local draw_vrb = sm.center_text_y == true and draw_text_left_centered or draw_text_left
    draw_vrb(cr, cx + dx, cy + dy, "VRB", font, size, vcol, valpha)
  end
end

local function draw_station_model_impl(extra_dx, extra_dy)
  if conky_window == nil then return end

  local t = get_theme()
  local sm = t.station_model or {}
  if sm.enabled == false then return end

  local w, h = conky_window.width, conky_window.height
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(cs)

  local dx = scale(tonumber(extra_dx) or 0)
  local dy = scale(tonumber(extra_dy) or 0)
  local base_cx = (w / 2) + scale(tonumber(sm.center_x_offset) or 0) + dx
  local base_cy = (h / 2) + scale(tonumber(sm.center_y_offset) or 0) + dy
  local circle = sm.circle or {}
  local circle_outer = sm.circle_outer or {}
  local center_x = base_cx
  local center_y = base_cy + scale(tonumber(circle.offset_y) or 0)

  local metar = fetch_metar(sm)
  local data = parse_metar(metar)

  if sm.debug then
    print(string.format("[station_model] METAR: %s", data.raw))
    print(string.format("[station_model] wind dir=%s spd=%s vrb=%s",
      tostring(data.wind_dir_deg), tostring(data.wind_speed_kt), tostring(data.wind_is_vrb)))
    print(string.format("[station_model] vis=%s temp=%s dew=%s slp=%s tend=%s",
      tostring(data.vis_sm), tostring(data.temp_c), tostring(data.dew_c),
      tostring(data.slp_code), tostring(data.tendency_char)))
  end

  local font_symbol = sm.font_symbol or "WX Symbols"
  local font_value = sm.font_value
  if font_value == nil or font_value == "" or font_value == "auto" then
    font_value = (t.fonts and t.fonts.value) or "Exo 2"
  end
  local font_numbers = sm.font_numbers
  if font_numbers == nil or font_numbers == "" or font_numbers == "auto" then
    font_numbers = font_value
  end
  local font_small = sm.font_small
  if font_small == nil or font_small == "" or font_small == "auto" then
    font_small = (t.fonts and t.fonts.label) or font_value
  end
  local center_text_y = sm.center_text_y == true
  local draw_center = center_text_y and draw_text_center_centered or draw_text_center
  local draw_left = center_text_y and draw_text_left_centered or draw_text_left
  local draw_right = center_text_y and draw_text_right_centered or draw_text_right

  local col_text = sm.color_text or { 0.90, 0.90, 0.90 }
  local col_dim = sm.color_dim or { 0.70, 0.70, 0.70 }
  local col_symbol = sm.color_symbol or col_text
  local col_cloud = sm.color_cloud or col_symbol
  local col_wx = sm.color_wx or col_symbol
  local col_tendency = sm.color_tendency or col_symbol
  local alpha_text = tonumber(sm.alpha_text) or 0.95
  local alpha_symbol = tonumber(sm.alpha_symbol) or 0.95

  local cloud_size = scale(tonumber(sm.cloud_size) or 40)
  local wx_size = scale(tonumber(sm.wx_size) or 32)
  local value_size = scale(tonumber(sm.value_size) or 20)
  local vis_size = scale(tonumber(sm.vis_size) or 18)
  local tendency_size = scale(tonumber(sm.tendency_size) or 16)
  local base_radius = tonumber(circle.radius) or ((tonumber(sm.cloud_size) or 36) * 0.6)
  local circle_radius = scale(base_radius)
  local circle_stroke = scale(tonumber(circle.stroke_width) or 2.0)

  local cloud_x = center_x + scale(tonumber(sm.cloud_offset_x) or 0)
  local cloud_y = center_y + scale(tonumber(sm.cloud_offset_y) or 0)
  local wx_x = center_x + scale(tonumber(sm.wx_offset_x) or -70)
  local wx_y = center_y + scale(tonumber(sm.wx_offset_y) or 6)
  local vis_x = center_x + scale(tonumber(sm.vis_offset_x) or -110)
  local vis_y = center_y + scale(tonumber(sm.vis_offset_y) or -2)
  local temp_x = center_x + scale(tonumber(sm.temp_offset_x) or -46)
  local temp_y = center_y + scale(tonumber(sm.temp_offset_y) or -30)
  local dew_x = center_x + scale(tonumber(sm.dew_offset_x) or -46)
  local dew_y = center_y + scale(tonumber(sm.dew_offset_y) or 34)
  local slp_x = center_x + scale(tonumber(sm.slp_offset_x) or 48)
  local slp_y = center_y + scale(tonumber(sm.slp_offset_y) or -30)
  local tend_x = center_x + scale(tonumber(sm.tendency_offset_x) or 46)
  local tend_y = center_y + scale(tonumber(sm.tendency_offset_y) or 34)
  local tend_dx = scale(tonumber(sm.tendency_value_dx) or 16)
  local precip_x = center_x + scale(tonumber(sm.precip_offset_x) or 46)
  local precip_y = center_y + scale(tonumber(sm.precip_offset_y) or 60)
  local precip_size = scale(tonumber(sm.precip_size) or value_size)

  local cloud_code = data.cloud_code or "N_Slash"
  local cloud_glyph = CLOUD_GLYPHS[cloud_code] or CLOUD_GLYPHS.N_Slash

  do
    if circle.enabled ~= false then
      local radius = circle_radius
      local stroke = circle_stroke
      local fill_col = circle.fill_color or col_dim
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
      local fill_alpha = tonumber(circle.fill_alpha) or 0.15
      local stroke_col = circle.stroke_color or col_text
      local stroke_alpha = tonumber(circle.stroke_alpha) or 0.65
      local cx = center_x
      local cy = center_y

      if fill_alpha > 0 then
        set_rgba(cr, fill_col, fill_alpha)
        cairo_arc(cr, cx, cy, radius, 0, 2 * math.pi)
        cairo_fill(cr)
      end
      if stroke > 0 and stroke_alpha > 0 then
        set_rgba(cr, stroke_col, stroke_alpha)
        cairo_set_line_width(cr, stroke)
        cairo_arc(cr, cx, cy, radius, 0, 2 * math.pi)
        cairo_stroke(cr)
      end
      if circle_outer.enabled ~= false then
        local outer_stroke = scale(tonumber(circle_outer.stroke_width) or 4.0)
        local outer_offset = tonumber(circle_outer.radius_offset) or 4
        local outer_radius = tonumber(circle_outer.radius) or (base_radius + outer_offset)
        outer_radius = scale(outer_radius)
        local outer_col = circle_outer.stroke_color or { 1.00, 1.00, 1.00 }
        local outer_alpha = tonumber(circle_outer.stroke_alpha) or 0.95
        if outer_stroke > 0 and outer_alpha > 0 then
          set_rgba(cr, outer_col, outer_alpha)
          cairo_set_line_width(cr, outer_stroke)
          cairo_arc(cr, cx, cy, outer_radius, 0, 2 * math.pi)
          cairo_stroke(cr)
        end
      end
    end
  end

  do
    local compass = sm.compass or {}
    if compass.enabled ~= false then
      local offset = scale(tonumber(compass.offset) or 0)
      local base_radius = circle_radius + (circle_stroke / 2) + offset
      local alpha = tonumber(compass.alpha) or 0.80
      local len_major = scale(tonumber(compass.length_major) or 12)
      local len_mid = scale(tonumber(compass.length_mid) or 8)
      local len_minor = scale(tonumber(compass.length_minor) or 5)
      local width_major = scale(tonumber(compass.width_major) or 2.6)
      local width_mid = scale(tonumber(compass.width_mid) or 2.0)
      local width_minor = scale(tonumber(compass.width_minor) or 1.2)
      local col_major = compass.color_major or { 1.00, 1.00, 1.00 }
      local col_mid = compass.color_mid or { 0.85, 0.85, 0.85 }
      local col_minor = compass.color_minor or { 0.70, 0.70, 0.70 }
      local col_wind = compass.color_wind or { 1.00, 0.62, 0.00 }
      local alpha_wind = tonumber(compass.wind_alpha) or 0.95

      local major = { [0] = true, [90] = true, [180] = true, [270] = true }
      local mid = {
        [30] = true, [60] = true, [120] = true, [150] = true,
        [210] = true, [240] = true, [300] = true, [330] = true,
      }
      local wind_deg = data.wind_is_vrb and nil or data.wind_dir_deg
      if not wind_deg or not data.wind_speed_kt or data.wind_speed_kt <= 0 then
        wind_deg = nil
      end
      local wind_tick = nil
      if wind_deg ~= nil then
        wind_tick = (math.floor((wind_deg + 5) / 10) * 10) % 360
      end

      for deg = 0, 350, 10 do
        local len, width, col
        if major[deg] then
          len = len_major
          width = width_major
          col = col_major
        elseif mid[deg] then
          len = len_mid
          width = width_mid
          col = col_mid
        else
          len = len_minor
          width = width_minor
          col = col_minor
        end
        local tick_alpha = alpha
        if wind_tick ~= nil and deg == wind_tick then
          col = col_wind
          tick_alpha = alpha_wind
        end
        local ang = math.rad(deg - 90)
        local x0 = center_x + base_radius * math.cos(ang)
        local y0 = center_y + base_radius * math.sin(ang)
        local x1 = center_x + (base_radius + len) * math.cos(ang)
        local y1 = center_y + (base_radius + len) * math.sin(ang)
        set_rgba(cr, col, tick_alpha)
        cairo_set_line_width(cr, width)
        cairo_move_to(cr, x0, y0)
        cairo_line_to(cr, x1, y1)
        cairo_stroke(cr)
      end

      local n_label = compass.n_label or {}
      if n_label.enabled ~= false then
        local label_txt = n_label.text or "N"
        local label_font = (t.fonts and t.fonts.title) or font_value
        local label_size = scale(tonumber(n_label.size) or 18)
        local label_col = n_label.color or { 0.40, 0.08, 0.12 }
        local label_alpha = tonumber(n_label.alpha) or 1.00
        local label_offset = scale(tonumber(n_label.offset) or 0)
        local label_radius = base_radius - label_offset
        local ang = -math.pi / 2
        local lx = center_x + label_radius * math.cos(ang)
        local ly = center_y + label_radius * math.sin(ang)
        draw_center(cr, lx, ly, label_txt, label_font, label_size, label_col, label_alpha)
      end
    end
  end

  draw_center(cr, cloud_x, cloud_y, cloud_glyph, font_symbol, cloud_size, col_cloud, alpha_symbol)

  draw_wind_barb(cr, cloud_x, cloud_y, data, sm, col_text, alpha_text)

  local wx_glyph = data.present_wx and data.present_wx.glyph or nil
  if wx_glyph and wx_glyph ~= "" then
    draw_center(cr, wx_x, wx_y, wx_glyph, font_symbol, wx_size, col_wx, alpha_symbol)
  end

  local vis_txt = value_or_slash(format_visibility_sm(data.vis_sm, sm.vis_fraction_glyphs))
  draw_right(cr, vis_x, vis_y, vis_txt, font_numbers, vis_size, col_dim, alpha_text)

  local temp_txt = value_or_slash(data.temp_c)
  local dew_txt = value_or_slash(data.dew_c)
  local temp_dew_x = center_x + scale(tonumber(sm.temp_dew_center_x) or 0)
  draw_center(cr, temp_dew_x, temp_y, temp_txt, font_numbers, value_size, col_text, alpha_text)
  draw_center(cr, temp_dew_x, dew_y, dew_txt, font_numbers, value_size, col_text, alpha_text)

  local slp_txt = value_or_slash(data.slp_code)
  draw_left(cr, slp_x, slp_y, slp_txt, font_numbers, value_size, col_text, alpha_text)

  if sm.show_tendency ~= false and (data.tendency_char ~= nil or data.tendency_dhpa ~= nil) then
    local tend_glyph = tendency_glyph(data.tendency_char)
    local tend_txt = "/"
    if data.tendency_dhpa ~= nil then
      local sign = tendency_sign(data.tendency_char)
      local tenths = math.floor((data.tendency_dhpa * 10) + 0.5)
      tend_txt = string.format("%s%d", sign, tenths)
    end
    if not tend_glyph then tend_glyph = "/" end
    draw_left(cr, tend_x, tend_y, tend_txt, font_numbers, tendency_size, col_dim, alpha_text)
    local min_dx = tend_dx
    local pad = scale(4)
    local value_w = text_width(cr, tend_txt, font_numbers, tendency_size)
    local glyph_dx = math.max(min_dx, value_w + pad)
    draw_left(cr, tend_x + glyph_dx, tend_y, tend_glyph, font_symbol, tendency_size, col_tendency, alpha_symbol)
  end

  if sm.show_precip == true and data.precip6h ~= nil then
    local precip_txt = format_precip6h(data.precip6h) or "/"
    draw_left(cr, precip_x, precip_y, precip_txt, font_numbers, precip_size, col_dim, alpha_text)
  end

  do
    local station_label = sm.station_label or {}
    if station_label.enabled ~= false then
      local station_id = sm.station or "KMEM"
      local label_font = station_label.font
      if label_font == nil or label_font == "" or label_font == "auto" then
        label_font = (t.fonts and t.fonts.title) or font_value
      end
      local label_size = tonumber(station_label.size) or 20
      local label_col = station_label.color or { 0.00, 0.00, 0.00 }
      local label_alpha = tonumber(station_label.alpha) or 1.00
      local label_offset = scale(tonumber(station_label.y_offset) or 0)
      local label_size_px = scale(label_size)
      local label_y = center_y + circle_radius - (circle_stroke / 2) - (label_size_px / 2) + label_offset
      draw_center(cr, center_x, label_y, station_id, label_font, label_size_px, label_col, label_alpha)
    end
  end

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

---@diagnostic disable-next-line: lowercase-global
function conky_station_model(key)
  if key ~= "draw" then return "" end
  local ok, err = pcall(draw_station_model_impl, 0, 0)
  if not ok then
    print("station model error: " .. tostring(err))
  end
  return ""
end

function conky_draw_station_model_embed()
  local t = get_theme()
  local emb = t.embedded_corners or {}
  local cfg = emb.station_model or {}
  if emb.enabled ~= true then return end
  if cfg.enabled == false then return end
  local dx, dy = util.embedded_corner_offset("station_model")
  local ok, err = pcall(draw_station_model_impl, dx, dy)
  if not ok then
    print("station model embed error: " .. tostring(err))
  end
end
