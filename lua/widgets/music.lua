--[[
  ${CONKY_SUITE_DIR}/lua/widgets/music.lua
  Music + lyrics panel.

  Exposes:
    function conky_draw_music_widget()
    function conky_music_visible()
]]

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local CACHE_DIR = os.getenv("CONKY_CACHE_DIR") or ((os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/conky")
local util = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local scale = util.scale

local has_cairo = pcall(require, "cairo")

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

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function font_profile_for(theme, font_face)
  if type(font_face) ~= "string" then return nil end
  local family = font_face
  local colon = family:find(":")
  if colon then family = family:sub(1, colon - 1) end
  family = family:gsub("^%s+", ""):gsub("%s+$", "")
  local profiles = theme and theme.font_profiles
  if type(profiles) ~= "table" then return nil end
  return profiles[family]
end

local function font_y_offset(theme, font_face)
  local profile = font_profile_for(theme, font_face)
  local offset = profile and tonumber(profile.y_offset)
  if not offset or offset == 0 then return 0 end
  return offset * (tonumber(theme and theme.scale) or 1.0)
end

local function font_scaled_size(theme, font_face, font_size)
  local size = tonumber(font_size) or 0
  local profile = font_profile_for(theme, font_face)
  local s = profile and tonumber(profile.size_scale)
  if not s or s == 0 then s = 1.0 end
  return size * s
end

local function draw_text_left(cr, theme, x, y, txt, font_face, font_size, col, alpha, weight)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(theme, font_face)
  local size = font_scaled_size(theme, font_face, font_size)
  util.set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, txt)
end

local function draw_text_right(cr, theme, x, y, txt, font_face, font_size, col, alpha, weight)
  if txt == nil or txt == "" then return end
  y = y + font_y_offset(theme, font_face)
  local size = font_scaled_size(theme, font_face, font_size)
  util.set_rgba(cr, col, alpha)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y)
  cairo_show_text(cr, txt)
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

local function read_cmd(cmd)
  local f = io.popen(cmd)
  if not f then return nil end
  local out = f:read("*a") or ""
  f:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

local function get_player_status()
  return read_cmd("playerctl status 2>/dev/null") or ""
end

local function get_player_meta()
  return {
    artist = read_cmd("playerctl metadata xesam:artist 2>/dev/null") or "",
    title = read_cmd("playerctl metadata xesam:title 2>/dev/null") or "",
    album = read_cmd("playerctl metadata xesam:album 2>/dev/null") or "",
  }
end

local function get_player_times()
  local pos_ms = 0
  do
    local pos_s = read_cmd("playerctl position 2>/dev/null")
    if pos_s and pos_s ~= "" then
      local p = tonumber(pos_s) or 0
      pos_ms = math.floor(p * 1000 + 0.5)
    end
  end

  local len_ms = 0
  do
    local len_us_str = read_cmd("playerctl metadata mpris:length 2>/dev/null")
    if len_us_str and len_us_str ~= "" then
      local us = tonumber(len_us_str) or 0
      len_ms = math.floor(us / 1000 + 0.5)
    end
  end

  if len_ms < pos_ms then len_ms = pos_ms end
  return pos_ms, len_ms
end

local function fmt_clock_ms(ms)
  if not ms or ms <= 0 or ms ~= ms then return "0:00" end
  local s = math.floor(ms / 1000 + 0.5)
  local m = math.floor(s / 60)
  s = s % 60
  return string.format("%d:%02d", m, s)
end

local COVER_CACHE = CACHE_DIR .. "/nowplaying_cover.png"
local COVER_TMP = CACHE_DIR .. "/nowplaying_cover.tmp"
local COVER_STATE = {
  last_url = "",
}

local function exec_ok(cmd)
  local ok = os.execute(cmd)
  if ok == true then return true end
  if type(ok) == "number" then return ok == 0 end
  if type(ok) == "boolean" then return ok end
  return false
end

local function has_cmd(name)
  return exec_ok("command -v " .. name .. " >/dev/null 2>&1")
end

local function is_png(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local sig = f:read(8) or ""
  f:close()
  return sig == "\137PNG\r\n\26\n"
end

local function write_cover_from_tmp()
  if not util.file_exists(COVER_TMP) then return false end
  if is_png(COVER_TMP) then
    exec_ok(string.format("cp -f %q %q", COVER_TMP, COVER_CACHE))
    return util.file_exists(COVER_CACHE)
  end
  if has_cmd("magick") then
    exec_ok(string.format("magick %q %q", COVER_TMP, COVER_CACHE))
  elseif has_cmd("convert") then
    exec_ok(string.format("convert %q %q", COVER_TMP, COVER_CACHE))
  elseif has_cmd("ffmpeg") then
    exec_ok(string.format("ffmpeg -y -loglevel error -i %q %q", COVER_TMP, COVER_CACHE))
  else
    return false
  end
  return util.file_exists(COVER_CACHE)
end

local function ensure_cover_cached()
  local url = read_cmd("playerctl metadata mpris:artUrl 2>/dev/null")
  if not url or url == "" then
    COVER_STATE.last_url = ""
    return nil
  end

  if url == COVER_STATE.last_url and util.file_exists(COVER_CACHE) then
    return COVER_CACHE
  end

  if util.file_exists(COVER_TMP) then
    os.remove(COVER_TMP)
  end

  if url:match("^file://") then
    local path = url:gsub("^file://", "")
    exec_ok(string.format("cp -f %q %q", path, COVER_TMP))
  elseif url:match("^https?://") then
    exec_ok(string.format("curl -LfsS %q -o %q", url, COVER_TMP))
  else
    return nil
  end

  if write_cover_from_tmp() then
    COVER_STATE.last_url = url
    os.remove(COVER_TMP)
    return COVER_CACHE
  end
  os.remove(COVER_TMP)

  return nil
end

local function clear_cover_cache()
  if util.file_exists(COVER_CACHE) then
    os.remove(COVER_CACHE)
  end
  COVER_STATE.last_url = ""
end

local function resolve_fallback_path(path)
  if not path or path == "" then return nil end
  if path:sub(1, 1) == "/" then return path end
  return SUITE_DIR .. "/" .. path
end

local function draw_cover_art(cr, x, y, w, h, fallback)
  local path = util.file_exists(COVER_CACHE) and COVER_CACHE or resolve_fallback_path(fallback)
  if not path or path == "" then return end

  local img = cairo_image_surface_create_from_png(path)
  if (not img) or (cairo_surface_status(img) ~= 0) then
    if img then cairo_surface_destroy(img) end
    local fb = resolve_fallback_path(fallback)
    if not fb or fb == "" or fb == path then return end
    img = cairo_image_surface_create_from_png(fb)
    if (not img) or (cairo_surface_status(img) ~= 0) then
      if img then cairo_surface_destroy(img) end
      return
    end
  end
  local iw = cairo_image_surface_get_width(img)
  local ih = cairo_image_surface_get_height(img)
  if (not iw or iw == 0) or (not ih or ih == 0) then
    cairo_surface_destroy(img)
    return
  end
  local scale_f = math.min(w / iw, h / ih)
  local sw, sh = iw * scale_f, ih * scale_f
  local ox, oy = x + (w - sw) / 2, y + (h - sh) / 2

  cairo_save(cr)
  cairo_translate(cr, ox, oy)
  cairo_scale(cr, scale_f, scale_f)
  cairo_set_source_surface(cr, img, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)

  cairo_surface_destroy(img)
end

local function unquote_val(v)
  local s = tostring(v or "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  return s
end

local function load_lyrics_vars()
  local path = SUITE_DIR .. "/config/lyrics.vars"
  local vars = util.parse_vars_file and util.parse_vars_file(path) or {}
  for k, v in pairs(vars) do
    if type(v) == "string" then
      vars[k] = unquote_val(v)
    end
  end
  return vars
end

local function is_online_enabled()
  local vars = load_lyrics_vars()
  local v = vars.LYRICS_ENABLE_ONLINE
  if v == nil or v == "" then return true end
  return tostring(v) ~= "0"
end

local function is_lyrics_curl_silent()
  local vars = load_lyrics_vars()
  local v = vars.LYRICS_CURL_SILENT
  if v == nil or v == "" then return true end
  return tostring(v) ~= "0"
end

local function get_local_dirs()
  local vars = load_lyrics_vars()
  local list = vars.LYRICS_LOCAL_DIRS or ""
  local dirs = {}
  for part in tostring(list):gmatch("[^,]+") do
    local dir = part:gsub("^%s+", ""):gsub("%s+$", "")
    if dir ~= "" then
      table.insert(dirs, dir)
    end
  end
  if #dirs == 0 then
    dirs = { HOME .. "/Music/lyrics" }
  end
  return dirs
end

local function get_cache_dir()
  local vars = load_lyrics_vars()
  local dir = vars.LYRICS_CACHE_DIR or ""
  dir = tostring(dir):gsub("^%s+", ""):gsub("%s+$", "")
  if dir ~= "" then
    return dir
  end
  return CACHE_DIR .. "/lyrics"
end

local function get_noapi_providers()
  local vars = load_lyrics_vars()
  local list = vars.LYRICS_PROVIDERS_NOAPI or "lrclib,lyrics_ovh"
  if list == "" then
    list = "lrclib,lyrics_ovh"
  end
  local providers = {}
  for part in tostring(list):gmatch("[^,]+") do
    local name = part:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if name ~= "" then
      table.insert(providers, name)
    end
  end
  return providers
end

local function json_get_string(json, field)
  if not json or json == "" then return nil end
  local pattern = '"' .. field .. '"%s*:%s*"(.-)"'
  local val = json:match(pattern)
  if not val then return nil end
  val = val:gsub("\\n", "\n")
  val = val:gsub("\\r", "\r")
  val = val:gsub("\\t", "\t")
  val = val:gsub('\\"', '"')
  val = val:gsub("\\\\", "\\")
  return val
end

local function normalize_lyrics_text(s)
  if not s or s == "" then return s end
  s = s:gsub("\\\\n", "\n")
  s = s:gsub("\\n", "\n")
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("<%s*[Bb][Rr]%s*/?>", "\n")
  s = s:gsub("[ \t]+(\n)", "%1")
  s = s:gsub("[ \t]+$", "")
  return s
end

local function strip_lrc_prefix(line, cfg)
  if not cfg.strip_lrc_timestamps then return line end
  local out = line or ""
  while out:match("^%[%d+:%d+%.?%d*%]") do
    out = out:gsub("^%[%d+:%d+%.?%d*%]", "", 1)
  end
  if out:sub(1, 1) == " " then
    out = out:sub(2)
  end
  return out
end

local function is_lrc_text(s)
  if not s or s == "" then return false end
  return s:match("%[%d+:%d+%.?%d*%]") ~= nil
end

local function sanitize_key(s)
  s = tostring(s or ""):lower()
  s = s:gsub("[/%\\:%*%?%\"%<%>%|]", " ")
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function shell_quote(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function url_encode(s)
  s = tostring(s or ""):gsub("\n", " ")
  return (s:gsub("([^%w%-%._~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function ensure_dir(path)
  os.execute("mkdir -p " .. shell_quote(path) .. " >/dev/null 2>&1")
end

local function is_offline()
  local ok_ip = read_cmd("getent hosts 1.1.1.1 >/dev/null 2>&1; echo $?")
  local ok_host = read_cmd("getent hosts lyrics.ovh >/dev/null 2>&1; echo $?")
  if ok_ip ~= "0" or ok_host ~= "0" then
    return true
  end
  return false
end

local function read_lines(path, max_bytes, cfg)
  local f = io.open(path, "r")
  if not f then return nil end
  local bytes = tonumber(max_bytes) or 200000
  local data = f:read(bytes) or ""
  f:close()
  local lines = {}
  for line in (data .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r$", "")
    table.insert(lines, line)
  end
  if cfg.normalize_blank_lines then
    local max_run = tonumber(cfg.max_blank_run or 1) or 1
    if max_run < 0 then max_run = 0 end
    local whitespace_blank = (cfg.whitespace_only_is_blank ~= false)
    local out = {}
    local blank_run = 0
    for _, line in ipairs(lines) do
      local is_blank = whitespace_blank and line:match("^%s*$") or line == ""
      if is_blank then
        blank_run = blank_run + 1
        if max_run > 0 and blank_run <= max_run then
          table.insert(out, "")
        end
      else
        blank_run = 0
        table.insert(out, line)
      end
    end
    lines = out
  end
  return lines
end

local function track_key(meta)
  local artist = meta and meta.artist or ""
  local title = meta and meta.title or ""
  if artist == "" or title == "" then return "" end
  return sanitize_key(artist) .. " - " .. sanitize_key(title)
end

local function find_local_lyrics(meta)
  local artist = meta and meta.artist or ""
  local title = meta and meta.title or ""
  if artist == "" or title == "" then return nil end
  local stem = artist .. " - " .. title
  local safe_stem = sanitize_key(artist) .. " - " .. sanitize_key(title)
  local dirs = get_local_dirs()
  for _, dir in ipairs(dirs) do
    local paths = {
      dir .. "/" .. stem .. ".lrc",
      dir .. "/" .. stem .. ".txt",
      dir .. "/" .. safe_stem .. ".lrc",
      dir .. "/" .. safe_stem .. ".txt",
      dir .. "/lyrics.txt",
    }
    for _, path in ipairs(paths) do
      local f = io.open(path, "r")
      if f then
        f:close()
        return path
      end
    end
  end
  return nil
end

local function find_cached_lyrics(meta)
  local artist = meta and meta.artist or ""
  local title = meta and meta.title or ""
  if artist == "" or title == "" then return nil end
  local stem = artist .. " - " .. title
  local safe_stem = sanitize_key(artist) .. " - " .. sanitize_key(title)
  local dir = get_cache_dir()
  local paths = {
    dir .. "/" .. stem .. ".lrc",
    dir .. "/" .. stem .. ".txt",
    dir .. "/" .. safe_stem .. ".lrc",
    dir .. "/" .. safe_stem .. ".txt",
  }
  for _, path in ipairs(paths) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return path
    end
  end
  return nil
end

local function fetch_lyrics_ovh(artist, title)
  local url = "https://api.lyrics.ovh/v1/" .. url_encode(artist) .. "/" .. url_encode(title)
  local cmd = "curl -fsSL --max-time 8 " .. shell_quote(url)
  if is_lyrics_curl_silent() then
    cmd = cmd .. " 2>/dev/null"
  end
  local json = read_cmd(cmd)
  if not json or json == "" then return nil end
  local text = json_get_string(json, "lyrics")
  return normalize_lyrics_text(text)
end

local function fetch_lrclib(artist, title)
  local url = "https://lrclib.net/api/get?artist_name=" .. url_encode(artist) .. "&track_name=" ..
      url_encode(title)
  local cmd = "curl -fsSL --max-time 8 " .. shell_quote(url)
  if is_lyrics_curl_silent() then
    cmd = cmd .. " 2>/dev/null"
  end
  local json = read_cmd(cmd)
  if not json or json == "" then return nil end
  local synced = normalize_lyrics_text(json_get_string(json, "syncedLyrics"))
  if synced and synced ~= "" then
    return synced, "lrc"
  end
  local plain = normalize_lyrics_text(json_get_string(json, "plainLyrics") or json_get_string(json, "lyrics"))
  if plain and plain ~= "" then
    return plain, "txt"
  end
  return nil
end

local function save_cached_lyrics(meta, text, ext)
  local artist = meta and meta.artist or ""
  local title = meta and meta.title or ""
  if artist == "" or title == "" then return nil end
  local dir = get_cache_dir()
  ensure_dir(dir)
  local stem = artist .. " - " .. title
  local safe_stem = sanitize_key(artist) .. " - " .. sanitize_key(title)
  local path = dir .. "/" .. stem .. "." .. ext
  local f = io.open(path, "w")
  if not f then
    path = dir .. "/" .. safe_stem .. "." .. ext
    f = io.open(path, "w")
  end
  if not f then return nil end
  f:write(text)
  f:close()
  return path
end

local FETCH_THROTTLE_S = 30
local MISS_RETRY_S = 12 * 60 * 60
local LYRICS_FETCH_STATE = {
  last_track_key = "",
  last_fetch_time = 0,
  last_result = "",
  last_saved_track_key = "",
  last_saved_path = "",
}

local function update_track_state(key)
  if key ~= LYRICS_FETCH_STATE.last_track_key then
    LYRICS_FETCH_STATE.last_track_key = key
    LYRICS_FETCH_STATE.last_fetch_time = 0
    LYRICS_FETCH_STATE.last_result = ""
    LYRICS_FETCH_STATE.last_saved_track_key = ""
    LYRICS_FETCH_STATE.last_saved_path = ""
  end
end

local function fetch_online_lyrics(meta, key)
  local now = os.time()
  if key == "" then
    return nil, "miss"
  end
  if key == LYRICS_FETCH_STATE.last_track_key then
    if LYRICS_FETCH_STATE.last_result == "miss" and (now - LYRICS_FETCH_STATE.last_fetch_time) < MISS_RETRY_S then
      return nil, "miss"
    end
    if (now - LYRICS_FETCH_STATE.last_fetch_time) < FETCH_THROTTLE_S then
      return nil, "throttled"
    end
  end
  LYRICS_FETCH_STATE.last_fetch_time = now

  local artist = meta and meta.artist or ""
  local title = meta and meta.title or ""
  local providers = get_noapi_providers()
  for _, name in ipairs(providers) do
    local text, forced_ext
    if name == "lyrics_ovh" then
      text = fetch_lyrics_ovh(artist, title)
    elseif name == "lrclib" then
      text, forced_ext = fetch_lrclib(artist, title)
    end
    if text and text ~= "" then
      local instrumental = text:match("^%s*[Ii]nstrumental%s*$")
      if instrumental then
        LYRICS_FETCH_STATE.last_result = "instrumental"
        return nil, "instrumental"
      end
      local ext = forced_ext or (is_lrc_text(text) and "lrc" or "txt")
      local path = save_cached_lyrics(meta, text, ext)
      if path then
        LYRICS_FETCH_STATE.last_result = "hit"
        LYRICS_FETCH_STATE.last_saved_track_key = key
        LYRICS_FETCH_STATE.last_saved_path = path
        return path, "hit"
      end
    end
  end
  LYRICS_FETCH_STATE.last_result = "miss"
  return nil, "miss"
end

local MUSIC_LAST_SEEN = os.time()

function conky_music_visible()
  local theme = util.get_theme()
  local cfg = theme.music or {}
  if cfg.enabled == false then
    return "0"
  end

  if cfg.hide_when_inactive == false then
    return "1"
  end

  local now = os.time()
  local status = get_player_status()
  if status == "Playing" or status == "Paused" then
    MUSIC_LAST_SEEN = now
    return "1"
  end

  local threshold = tonumber(cfg.idle_hide_after_s) or 10
  if (now - MUSIC_LAST_SEEN) < threshold then
    return "1"
  end

  return "0"
end

local function resolve_panel_geometry(w, h, panel)
  local pad_x = s(panel.padding_x, scale(10))
  local pad_y = s(panel.padding_y, scale(8))

  local x0 = s(panel.offset_x, 0)
  local y0 = s(panel.offset_y, 0)
  local pw = panel.width
  local ph = panel.height

  if pw == nil then
    x0 = x0 + pad_x
    pw = w - (pad_x * 2)
  else
    pw = s(pw, 0)
  end
  if ph == nil then
    y0 = y0 + pad_y
    ph = h - (pad_y * 2)
  else
    ph = s(ph, 0)
  end

  return x0, y0, pw, ph
end

local function draw_panel(cr, w, h, theme, panel)
  if panel.enabled == false then
    return 0, 0, w, h
  end

  local x0, y0, pw, ph = resolve_panel_geometry(w, h, panel)
  if pw <= 0 or ph <= 0 then return 0, 0, w, h end

  local radius = s(panel.radius, scale(12))
  local fill_color = panel.fill_color or { 0.30, 0.30, 0.30 }
  local fill_alpha = pick(panel.fill_alpha, 0.45)
  if panel.season_tint_enable == true then
    local season_tints = {
      WINTER = { 0.20, 0.30, 0.45 },
      SPRING = { 0.85, 0.80, 0.40 },
      SUMMER = { 0.30, 0.55, 0.30 },
      AUTUMN = { 0.75, 0.35, 0.25 },
    }
    local season = current_season_label()
    local tint = season_tints[season]
    local amt = tonumber(panel.season_tint_amount) or 0.06
    if tint and type(fill_color) == "table" then
      fill_color = blend_color(fill_color, tint, amt)
    end
  end

  local stroke_color = panel.stroke_color or { 1.00, 1.00, 1.00 }
  local stroke_alpha = pick(panel.stroke_alpha, 0.30)
  local stroke_width = s(panel.stroke_width, scale(2.0))
  local outer = panel.outer_stroke or {}

  draw_round_rect(cr, x0, y0, pw, ph, radius)
  util.set_rgba(cr, fill_color, fill_alpha)
  cairo_fill_preserve(cr)
  util.set_rgba(cr, stroke_color, stroke_alpha)
  cairo_set_line_width(cr, stroke_width)
  cairo_stroke(cr)

  if outer.enabled ~= false then
    local outer_offset = s(outer.offset, scale(4))
    local outer_width = s(outer.width, stroke_width)
    local outer_color = outer.color or stroke_color
    local outer_alpha = pick(outer.alpha, stroke_alpha)

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

  return x0, y0, pw, ph
end

local function draw_music_bracket(cr, theme, cfg, x0, y0, pw, ph)
  local b = cfg.bracket or {}
  if b.enabled == false then return end

  local bx = x0 + s(b.x, 0)
  local by = y0 + s(b.y, 0)
  local flip_v = b.flip_v == true
  local dir = flip_v and -1 or 1
  local short = s(b.short, 0) * dir
  local diag_dx = s(b.diag_dx, 0)
  local diag_dy = s(b.diag_dy, 0) * dir
  local diag_scale = tonumber(b.diag_scale) or 1.0
  local diag_short = s(b.diag_short, 0)
  local long_len_cfg = s(b.long_len, 0)
  local vert = s(b.vert, 0)
  local width = s(b.width, scale(2.0))
  local alpha = tonumber(b.alpha) or 0.30
  local color = b.color or (theme.palette and theme.palette.white) or { 1.00, 1.00, 1.00 }
  local bottom_pad = s(b.bottom_pad, 0)

  local dx = diag_dx * diag_scale
  local dy = diag_dy * diag_scale
  local long_len
  if long_len_cfg <= 0 then
    local edge_space
    if dir > 0 then
      edge_space = ph - (by - y0) - bottom_pad
    else
      edge_space = (by - y0) - bottom_pad
    end
    local long_mag = edge_space - math.abs(short) - math.abs(dy)
    if long_mag < 0 then long_mag = 0 end
    long_len = long_mag * dir
  else
    long_len = long_len_cfg * dir
  end

  util.set_rgba(cr, color, alpha)
  cairo_set_line_width(cr, width)

  cairo_move_to(cr, bx, by)
  cairo_line_to(cr, bx, by + short)
  cairo_line_to(cr, bx + dx, by + short + dy)
  local long_x = bx + dx + diag_short
  cairo_line_to(cr, long_x, by + short + dy)
  cairo_line_to(cr, long_x, by + short + dy + long_len)
  cairo_line_to(cr, long_x + vert, by + short + dy + long_len)
  cairo_stroke(cr)
end

local function draw_music_title(cr, theme, cfg, x0, y0, pw, ph)
  local tcfg = cfg.title or {}
  if tcfg.enabled == false then return end

  local text = tostring(tcfg.text or "MUSIC")
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
  local rot = tonumber(tcfg.rot_deg) or -90

  util.draw_text_center_rotated(cr, x, y, text, font, size, color, alpha, math.rad(rot))
end

local function text_width(cr, theme, font_face, font_size, txt)
  if txt == nil or txt == "" then return 0 end
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_scaled_size(theme, font_face, font_size))
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  return ext.x_advance or (ext.width + ext.x_bearing)
end

local function wrap_lines_for_width(cr, theme, lines, font_face, font_size, max_w)
  if not lines or max_w <= 0 then return lines or {} end
  local out = {}
  for _, line in ipairs(lines) do
    local s = tostring(line or "")
    if s == "" then
      table.insert(out, "")
    else
      local current = ""
      for word in s:gmatch("%S+") do
        local cand = (current == "") and word or (current .. " " .. word)
        if text_width(cr, theme, font_face, font_size, cand) <= max_w or current == "" then
          current = cand
        else
          table.insert(out, current)
          current = word
        end
      end
      if current ~= "" then
        table.insert(out, current)
      end
    end
  end
  return out
end

local function draw_text_marquee(cr, theme, x, y, txt, font_face, font_size, col, alpha, mq)
  if txt == nil or txt == "" then return end
  local cfg = mq or {}
  local enabled = (cfg.enabled ~= false)
  local max_w = s(cfg.max_w, 0)
  local gap_px = s(cfg.gap_px, scale(40))
  local speed_px_u = s(cfg.speed_px_u, scale(2))
  local wtxt = text_width(cr, theme, font_face, font_size, txt)

  if not enabled or max_w <= 0 or wtxt <= max_w then
    draw_text_left(cr, theme, x, y, txt, font_face, font_size, col, alpha)
    return
  end

  local updates = tonumber(conky_parse("${updates}")) or 0
  local period = wtxt + gap_px
  local offset = (updates * speed_px_u) % period

  cairo_save(cr)
  local h = font_scaled_size(theme, font_face, font_size)
  cairo_rectangle(cr, x, y - h, max_w, h * 2)
  cairo_clip(cr)

  draw_text_left(cr, theme, x - offset, y, txt, font_face, font_size, col, alpha)
  draw_text_left(cr, theme, x - offset + period, y, txt, font_face, font_size, col, alpha)

  cairo_restore(cr)
end

local function resolve_lyrics_lines(meta, cfg, max_lines, status)
  local playing = (status == "Playing" or status == "Paused")
  if cfg.hide_when_inactive == true and not playing then
    return nil, nil
  end

  if not playing and cfg.inactive_message and cfg.inactive_message ~= "" then
    return { cfg.inactive_message }, nil
  end

  local key = track_key(meta)
  update_track_state(key)

  local show_footer = (cfg.show_saved_path == true)
      and (LYRICS_FETCH_STATE.last_saved_track_key == key)
      and (LYRICS_FETCH_STATE.last_saved_path ~= "")

  local path = find_local_lyrics(meta) or find_cached_lyrics(meta)
  if not path then
    if is_online_enabled() then
      if is_offline() then
        return { cfg.offline_message or "Offline" }, nil
      end
      local fetched_path, result = fetch_online_lyrics(meta, key)
      if result == "instrumental" then
        return { cfg.instrumental_message or "Instrumental" }, nil
      elseif result == "throttled" then
        return { cfg.searching_message or "Searching..." }, nil
      else
        path = fetched_path or LYRICS_FETCH_STATE.last_saved_path
        if not path then
          return { cfg.not_found_message or "Lyrics not found" }, nil
        end
      end
    else
      return { cfg.not_found_message or "Lyrics not found" }, nil
    end
  end

  local max_body = max_lines
  if show_footer then
    max_body = max_body - 1
    if max_body < 1 then
      max_body = 1
      show_footer = false
    end
  end

  local lines = read_lines(path, cfg.max_bytes, cfg) or {}
  local total = #lines
  local show_lines = math.min(total, max_body)
  local out = {}
  for i = 1, show_lines do
    out[i] = strip_lrc_prefix(lines[i] or "", cfg)
  end
  if total > max_body then
    out[show_lines] = cfg.more_marker or "...more..."
  end

  local footer_txt = nil
  if show_footer then
    footer_txt = (cfg.saved_prefix or "Saved to: ") .. LYRICS_FETCH_STATE.last_saved_path
  end

  return out, footer_txt
end

function conky_draw_music_widget()
  if not has_cairo then return end
  if conky_window == nil then return end
  local w = conky_window.width or 0
  local h = conky_window.height or 0
  if w <= 0 or h <= 0 then return end

  local theme = util.get_theme()
  local cfg = theme.music or {}
  if cfg.enabled == false then return end

  local status = get_player_status()
  local playing = (status == "Playing" or status == "Paused")

  if cfg.hide_when_inactive ~= false then
    local now = os.time()
    if playing then
      MUSIC_LAST_SEEN = now
    else
      local threshold = tonumber(cfg.idle_hide_after_s) or 10
      if (now - MUSIC_LAST_SEEN) >= threshold then
        clear_cover_cache()
        return
      end
    end
  end

  if playing then
    ensure_cover_cached()
  else
    clear_cover_cache()
  end

  local cs = cairo_xlib_surface_create(
    conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    w,
    h
  )
  local cr = cairo_create(cs)

  cairo_save(cr)
  cairo_new_path(cr)

  local panel = cfg.panel or {}
  local x0, y0, pw, ph = draw_panel(cr, w, h, theme, panel)
  draw_music_bracket(cr, theme, cfg, x0, y0, pw, ph)
  draw_music_title(cr, theme, cfg, x0, y0, pw, ph)

  local content_x = x0 + s(cfg.content_offset_x, 0)
  local content_y = y0 + s(cfg.content_offset_y, 0)

  local art = cfg.art or {}
  local art_x = content_x + s(art.x, scale(30))
  local art_y = content_y + s(art.y, scale(30))
  local art_w = s(art.w, scale(96))
  local art_h = s(art.h, scale(96))

  draw_cover_art(cr, art_x, art_y, art_w, art_h, art.fallback or "icons/horn-of-odin.png")

  local meta = get_player_meta()

  local header = cfg.header or {}
  local header_gap_x = s(header.gap_x, scale(16))
  local header_line_gap = s(header.line_gap, scale(6))
  local header_x = header.x
  if header_x == nil then
    header_x = art_x + art_w + header_gap_x
  else
    header_x = content_x + s(header_x, 0)
  end
  local header_y = header.y
  if header_y == nil then
    header_y = art_y
  else
    header_y = content_y + s(header_y, 0)
  end

  local artist_cfg = header.artist or {}
  local album_cfg = header.album or {}
  local title_cfg = header.title or {}

  local artist_txt = meta.artist
  local album_txt = meta.album
  local title_txt = meta.title

  if not playing and cfg.inactive_message and cfg.inactive_message ~= "" then
    title_txt = cfg.inactive_message
    artist_txt = ""
    album_txt = ""
  end

  if artist_txt and artist_txt ~= "" and artist_cfg.uppercase ~= false then
    artist_txt = artist_txt:upper()
  end

  local line_y = header_y
  if artist_txt and artist_txt ~= "" then
    local size = s(artist_cfg.size, scale(20))
    local font = artist_cfg.font or (theme.fonts and theme.fonts.title) or "Sans"
    draw_text_marquee(cr, theme, header_x, line_y + size, artist_txt, font, size,
      artist_cfg.color or (theme.palette and theme.palette.white) or { 1, 1, 1 },
      artist_cfg.alpha or 1.0, artist_cfg.marquee)
    line_y = line_y + size + header_line_gap
  end

  if album_txt and album_txt ~= "" then
    local size = s(album_cfg.size, scale(16))
    local font = album_cfg.font or (theme.fonts and theme.fonts.value) or "Sans"
    draw_text_marquee(cr, theme, header_x, line_y + size, album_txt, font, size,
      album_cfg.color or (theme.palette and theme.palette.gray and theme.palette.gray.g90) or { 1, 1, 1 },
      album_cfg.alpha or 0.85, album_cfg.marquee)
    line_y = line_y + size + header_line_gap
  end

  if title_txt and title_txt ~= "" then
    local size = s(title_cfg.size, scale(18))
    local font = title_cfg.font or (theme.fonts and theme.fonts.value) or "Sans"
    draw_text_marquee(cr, theme, header_x, line_y + size, title_txt, font, size,
      title_cfg.color or (theme.palette and theme.palette.white) or { 1, 1, 1 },
      title_cfg.alpha or 0.95, title_cfg.marquee)
  end

  local progress = cfg.progress or {}
  local prog_x = content_x + s(progress.x, scale(30))
  local prog_y
  if progress.y ~= nil then
    prog_y = content_y + s(progress.y, 0)
  else
    prog_y = art_y + art_h + scale(24)
  end
  local prog_len = progress.length ~= nil
      and s(progress.length, 0)
      or (pw - (prog_x - x0) - scale(30))
  if prog_len < 0 then prog_len = 0 end

  local pos_ms, len_ms = get_player_times()
  local frac = (len_ms > 0) and clamp(pos_ms / len_ms, 0, 1) or 0

  local prog_col = progress.color or (theme.palette and theme.palette.gray and theme.palette.gray.g80) or { 1, 1, 1 }
  local prog_alpha = tonumber(progress.alpha) or 0.8
  local prog_stroke = s(progress.stroke, scale(2.0))

  if prog_len > 0 then
    util.set_rgba(cr, prog_col, prog_alpha)
    cairo_set_line_width(cr, prog_stroke)
    cairo_move_to(cr, prog_x, prog_y)
    cairo_line_to(cr, prog_x + prog_len, prog_y)
    cairo_stroke(cr)

    local marker = progress.marker or {}
    local md = s(marker.diameter, scale(10))
    local mcol = marker.color or (theme.palette and theme.palette.accent and theme.palette.accent.maroon) or { 0.40, 0.08, 0.12 }
    local malpha = tonumber(marker.alpha) or 1.0
    local mx = prog_x + prog_len * frac
    util.set_rgba(cr, mcol, malpha)
    cairo_arc(cr, mx, prog_y, md / 2, 0, 2 * math.pi)
    cairo_fill(cr)
  end

  local time_cfg = progress.time or {}
  local time_font = time_cfg.font or (theme.fonts and theme.fonts.value_mono) or "Sans"
  local time_size = s(time_cfg.size, scale(12))
  local time_color = time_cfg.color or prog_col
  local time_alpha = tonumber(time_cfg.alpha) or 0.8
  local time_dy = s(time_cfg.dy, scale(18))

  local played_str = fmt_clock_ms(pos_ms)
  local remain_str = (len_ms > 0) and ("-" .. fmt_clock_ms(len_ms - pos_ms)) or "-0:00"

  draw_text_left(cr, theme, prog_x, prog_y + time_dy, played_str, time_font, time_size, time_color, time_alpha)
  draw_text_right(cr, theme, prog_x + prog_len, prog_y + time_dy, remain_str, time_font, time_size, time_color, time_alpha)

  local lyrics_cfg = cfg.lyrics or {}
  local lyrics_x = content_x + s(lyrics_cfg.x, scale(30))
  local lyrics_y
  if lyrics_cfg.y ~= nil then
    lyrics_y = content_y + s(lyrics_cfg.y, 0)
  else
    lyrics_y = prog_y + s(lyrics_cfg.gap_y, scale(28))
  end
  local lyrics_w = lyrics_cfg.w ~= nil
      and s(lyrics_cfg.w, 0)
      or (prog_len > 0 and prog_len or (pw - (lyrics_x - x0) - scale(30)))
  local bottom_pad = s(lyrics_cfg.bottom_pad, scale(20))
  local lyrics_h = lyrics_cfg.h ~= nil
      and s(lyrics_cfg.h, 0)
      or (y0 + ph - lyrics_y - bottom_pad)

  if lyrics_w > 0 and lyrics_h > 0 then
    local lfont = lyrics_cfg.font or (theme.fonts and theme.fonts.value_mono) or "Sans"
    local lsize = s(lyrics_cfg.size, scale(13))
    local lcolor = lyrics_cfg.color or (theme.palette and theme.palette.white) or { 1, 1, 1 }
    local lalpha = tonumber(lyrics_cfg.alpha) or 0.85
    local line_px = s(lyrics_cfg.line_px, nil) or (lsize + scale(3))
    local wrap_w = lyrics_w
    if lyrics_cfg.wrap_enabled == true and prog_len > 0 then
      wrap_w = math.min(lyrics_w, prog_len)
    end
    local max_lines = math.max(1, math.floor(lyrics_h / line_px))

    local lines, footer = resolve_lyrics_lines(meta, lyrics_cfg, max_lines, status)
    if lines then
      if lyrics_cfg.wrap_enabled == true then
        lines = wrap_lines_for_width(cr, theme, lines, lfont, lsize, wrap_w)
      end
      if #lines > max_lines then
        lines = { unpack(lines, 1, max_lines) }
        lines[max_lines] = lyrics_cfg.more_marker or "...more..."
      end
      cairo_save(cr)
      cairo_rectangle(cr, lyrics_x, lyrics_y, lyrics_w, lyrics_h)
      cairo_clip(cr)

      for i, line in ipairs(lines) do
        draw_text_left(cr, theme, lyrics_x, lyrics_y + lsize + (i - 1) * line_px,
          line, lfont, lsize, lcolor, lalpha)
      end

      if footer and footer ~= "" then
        local footer_pt = math.max(scale(9), lsize - scale(1))
        local footer_line_px = s(lyrics_cfg.footer_line_px, nil) or (footer_pt + scale(3))
        local footer_y = lyrics_y + (lyrics_h - footer_line_px) + footer_pt
        draw_text_left(cr, theme, lyrics_x, footer_y, footer, lfont, footer_pt, lcolor, 0.75)
      end

      cairo_restore(cr)
    end
  end

  cairo_new_path(cr)
  cairo_restore(cr)
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
