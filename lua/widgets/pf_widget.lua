-- ${CONKY_SUITE_DIR}/lua/pf_widget.lua
-- pfSense widget: live text + arc with moving markers, trails, labels, baseline.
-- Theme knobs come from theme-pf.lua (hot-reloaded each refresh).

---------------------------------------------------------------------------
-- Paths / helpers
---------------------------------------------------------------------------
local HOME          = os.getenv("HOME") or ""
local SUITE_DIR     = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-tech-hud")
local util          = dofile(SUITE_DIR .. "/lua/lib/util.lua")
local CACHE_DIR     = util.cache_dir
local THEME_PF_PATH = SUITE_DIR .. "/theme-pf.lua"
local FETCH_SCRIPT  = SUITE_DIR .. "/scripts/pf-fetch-basic.sh"
local GATE_SCRIPT   = SUITE_DIR .. "/scripts/pf-ssh-gate.sh"

-- Run a shell command with /usr/bin/env bash (so pipefail etc. work)
local function sh(cmd)
  if type(cmd) ~= "string" or cmd == "" then return "" end
  local f = io.popen("/usr/bin/env bash -lc " .. string.format("%q", cmd) .. " 2>/dev/null")
  if not f then return "" end
  local out = f:read("*a") or ""
  f:close()
  return out
end

local function sh_ok(cmd)
  if type(cmd) ~= "string" or cmd == "" then return false end
  local ok, reason, code = os.execute("/usr/bin/env bash -lc " .. string.format("%q", cmd) .. " >/dev/null 2>&1")
  if type(ok) == "number" then return ok == 0 end
  if ok == true then return true end
  if reason == "exit" and code == 0 then return true end
  return false
end

local function sh_with_status(cmd)
  if type(cmd) ~= "string" or cmd == "" then return "", false end
  local f = io.popen("/usr/bin/env bash -lc " .. string.format("%q", cmd) .. " 2>/dev/null")
  if not f then return "", false end
  local out = f:read("*a") or ""
  local ok, reason, code = f:close()
  if type(ok) == "number" then return out, ok == 0 end
  if ok == true then return out, true end
  if reason == "exit" and code == 0 then return out, true end
  return out, false
end

-- file mtime for hot-reload
local function _file_mtime(path)
  local f = io.popen(("stat -c %%Y %q 2>/dev/null || date -r %q +%%s 2>/dev/null"):format(path, path))
  if not f then return 0 end
  local out = f:read("*a") or ""
  f:close()
  return tonumber(out:match("(%d+)%s*$")) or 0
end

-- hot-reload theme table
local _pf_theme, _pf_mtime = nil, 0
local function pf_theme()
  local mt = _file_mtime(THEME_PF_PATH)
  if mt ~= _pf_mtime or not _pf_theme then
    local ok, Tp = pcall(dofile, THEME_PF_PATH)
    if ok and type(Tp) == "table" then _pf_theme, _pf_mtime = Tp, mt end
  end
  return _pf_theme or {}
end

-- dotted lookup
local function tget(root, dotted)
  local node = root
  for key in string.gmatch(dotted or "", "[^.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]; if node == nil then return nil end
  end
  return node
end

-- nested set via a.b.c = v
local function set_path(tbl, dotted, val)
  local cur = tbl
  local keys = {}
  for key in string.gmatch(dotted, "[^.]+") do keys[#keys + 1] = key end
  for i = 1, #keys - 1 do
    local k = keys[i]
    if type(cur[k]) ~= "table" then cur[k] = {} end
    cur = cur[k]
  end
  cur[keys[#keys]] = val
end

-- parse sectioned k=v output (supports: section=system / interfaces / gateway / pfblockerng)
local function parse_kv(raw)
  local t, cur = {}, nil
  for line in string.gmatch(raw or "", "[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      local k, v = line:match("^([^=%s]+)%s*=%s*(.*)$")
      if k then
        if k == "section" then
          cur = (v or ""):match("^%s*(.-)%s*$")
        else
          v = v:gsub('^"(.*)"$', "%1")
          local path = (cur and cur ~= "") and (cur .. "." .. k) or k
          set_path(t, path, v)
        end
      end
    end
  end
  return t
end

-- Run a quick remote command on pfSense (uses theme host); cache metadata briefly
local _meta = { last = 0, version = nil, bios = nil }
local function _trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function _pf_remote_version_and_bios()
  local now = os.time()
  if (now - (_meta.last or 0)) < 60 and _meta.version then
    return _meta.version, _meta.bios
  end
  if not sh_ok(string.format("%q allow", GATE_SCRIPT)) then
    return _meta.version, _meta.bios
  end
  local TP   = pf_theme()
  -- Use SSH config host alias
  local base = "ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o ServerAliveInterval=5 -o ServerAliveCountMax=1 -o LogLevel=ERROR pf"

  ---@type string|nil, boolean
  local ver, ok1 = sh_with_status(base .. " 'cat /etc/version'")
  local ven, ok2 = sh_with_status(base .. " 'kenv smbios.bios.vendor'")
  local bv, ok3  = sh_with_status(base .. " 'kenv smbios.bios.version'")
  local bd, ok4  = sh_with_status(base .. " 'kenv smbios.bios.reldate'")
  local ok_all = ok1 and ok2 and ok3 and ok4

  ver = _trim(ver)
  ven = _trim(ven)
  bv = _trim(bv)
  bd = _trim(bd)

  if ok_all then
    sh_ok(string.format("%q reset", GATE_SCRIPT))
  else
    sh_ok(string.format("%q trip PF_LUA_SSH_FAIL", GATE_SCRIPT))
  end

  local bios = bv
  if ven ~= "" then bios = (ven .. (bv ~= "" and " " .. bv or "")) end
  if bd ~= "" then bios = (bios ~= "" and (bios .. " (" .. bd .. ")") or bd) end

  if ver == "" then ver = nil end
  if bios == "" then bios = nil end

  _meta.version, _meta.bios, _meta.last = ver, bios, now
  return ver, bios
end

---------------------------------------------------------------------------
-- Fetch/cache pfSense values from script
---------------------------------------------------------------------------
local cache_if, cache_med, cache_slow = nil, nil, nil
local last_if, last_med, last_slow = 0, 0, 0
local function _merge_data(med, slow, fast)
  if not med and not fast and not slow then return nil end
  local out = {}
  if type(med) == "table" then
    for k, v in pairs(med) do out[k] = v end
  end
  if type(slow) == "table" then
    for k, v in pairs(slow) do out[k] = v end
  end
  if type(fast) == "table" and type(fast.interfaces) == "table" then
    out.interfaces = fast.interfaces
  end
  return out
end

local function maybe_fetch()
  local now  = os.time()
  local TP   = pf_theme()
  local fast = tonumber(tget(TP, "poll.fast")) or 1
  local med  = tonumber(tget(TP, "poll.medium")) or 10
  local slow = tonumber(tget(TP, "poll.slow")) or 30

  if (now - last_if) >= fast or not cache_if then
    local raw = sh(string.format("%q interfaces", FETCH_SCRIPT))
    if raw and raw ~= "" then
      cache_if = parse_kv(raw)
      last_if = now
    end
  end

  if (now - last_med) >= med or not cache_med then
    local raw = sh(string.format("%q medium", FETCH_SCRIPT))
    if raw and raw ~= "" then
      cache_med = parse_kv(raw)
      last_med = now
    end
  end

  if (now - last_slow) >= slow or not cache_slow then
    local raw = sh(string.format("%q slow", FETCH_SCRIPT))
    if raw and raw ~= "" then
      cache_slow = parse_kv(raw)
      last_slow = now
    end
  end

  return _merge_data(cache_med, cache_slow, cache_if)
end

-- Public helper for other widgets: get pfSense version + BIOS with clean-suite logic
function conky_pf_meta()
  local D       = maybe_fetch() or {}
  local version = tget(D, "system.version") or tget(D, "system.pf_version")
  local bios    = tget(D, "system.bios_version") or tget(D, "system.bios")

  if (not version or version == "?") or (not bios or bios == "?") then
    local v2, b2 = _pf_remote_version_and_bios()
    if (not version or version == "?") and v2 then version = v2 end
    if (not bios or bios == "?") and b2 then bios = b2 end
  end

  version = tostring(version or "?"):gsub("%-RELEASE.*$", "")

  do
    local b = tostring(bios or "?")
    local v = b:match("v%d+%.%d+%.%d+") or b:match("v%d+%.%d+")
    if v then
      bios = v
    else
      bios = b:match("%d+%.%d+%.%d+") or b:match("%d+%.%d+") or b
    end
  end

  return version, bios
end

---------------------------------------------------------------------------
-- Scaling & math helpers
---------------------------------------------------------------------------
local function safe_num(x)
  local n = tonumber(x or 0) or 0; if n ~= n then return 0 end; return n
end

-- Nonlinear scaler driven by theme (linear | sqrt | log)
local function scale_pct(mbps, linkMb, TP, label)
  local link = tonumber(linkMb or 1000) or 1000
  if link <= 0 then return 0 end

  local floors = (tget(TP, "scale.floors_mbps") or {})
  local floor_mbps = tonumber(floors[label or "WAN"] or 0) or 0
  local adj = mbps - floor_mbps
  if adj < 0 then adj = 0 end

  local norm = adj / link
  if norm < 0 then norm = 0 elseif norm > 1 then norm = 1 end

  local mode = (tget(TP, "scale.mode") or "linear")
  if mode == "linear" then
    return norm
  elseif mode == "sqrt" then
    local gamma = tonumber(tget(TP, "scale.sqrt.gamma")) or 0.5
    if gamma <= 0 then gamma = 0.5 end
    return norm ^ gamma
  elseif mode == "log" then
    local base     = tonumber(tget(TP, "scale.log.base")) or 10.0
    local min_norm = tonumber(tget(TP, "scale.log.min_norm")) or 0.001
    if base < 1.001 then base = 10.0 end
    local nn = norm
    if nn > 0 and nn < min_norm then nn = min_norm end
    local num = math.log(1 + (base - 1) * nn)
    local den = math.log(base)
    local out = (den ~= 0) and (num / den) or nn
    if out < 0 then out = 0 elseif out > 1 then out = 1 end
    return out
  end
  return norm
end

-- pretty percent string
local function fmt_pct01(p)
  if not p or p <= 0 then return "0.00" end
  local v = p * 100
  if v < 0.01 then return "<0.01" end
  return string.format("%.2f", v)
end

---------------------------------------------------------------------------
-- Public helper for other widgets: per-interface in/out percentages (0..100)
---------------------------------------------------------------------------
local prev_in_bytes_rates, prev_out_bytes_rates, prev_time_rates = {}, {}, {}
local ema_in_rates, ema_out_rates = {}, {}
function conky_pf_rates()
  local TP = pf_theme()
  local data = maybe_fetch()
  if not data then return nil end

  local order = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
  local downs, ups = {}, {}
  local now = os.time()
  local S = tget(TP, "pf.smoothing") or {}
  local alpha = tonumber(S.alpha) or 0.35
  if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end

  local function iface_val(ifn, suffix)
    if not ifn then return nil end
    local v = tget(data, ("interfaces.iface_%s_%s"):format(ifn, suffix))
    if v == nil and ifn:find("%.") then
      local ifn_u = ifn:gsub("%.", "_")
      v = tget(data, ("interfaces.iface_%s_%s"):format(ifn_u, suffix))
    end
    return v
  end

  for i, key in ipairs(order) do
    local ifn = tget(TP, "ifaces." .. key)
    local ibytes = safe_num(iface_val(ifn, "ibytes"))
    local obytes = safe_num(iface_val(ifn, "obytes"))

    local prev_in = prev_in_bytes_rates[key]
    local prev_out = prev_out_bytes_rates[key]
    local last = prev_time_rates[key] or 0
    local dt = now - last

    local in_rate, out_rate = 0, 0
    if prev_in and dt > 0 and ibytes >= prev_in then
      in_rate = (ibytes - prev_in) / dt
    end
    if prev_out and dt > 0 and obytes >= prev_out then
      out_rate = (obytes - prev_out) / dt
    end

    prev_in_bytes_rates[key] = ibytes
    prev_out_bytes_rates[key] = obytes
    prev_time_rates[key] = now

    local mbps_in = in_rate * 8 / 1e6
    local mbps_out = out_rate * 8 / 1e6

    local link_in = tget(TP, ("link_mbps_in.%s"):format(key))
    local link_out = tget(TP, ("link_mbps_out.%s"):format(key))
    local link = tget(TP, ("link_mbps.%s"):format(key)) or 1000
    local cap_in = tonumber(link_in or link) or 1000
    local cap_out = tonumber(link_out or link) or 1000

    local pct_in = scale_pct(mbps_in, cap_in, TP, key)
    local pct_out = scale_pct(mbps_out, cap_out, TP, key)
    if ema_in_rates[key] == nil then ema_in_rates[key] = pct_in end
    if ema_out_rates[key] == nil then ema_out_rates[key] = pct_out end
    ema_in_rates[key] = alpha * pct_in + (1 - alpha) * ema_in_rates[key]
    ema_out_rates[key] = alpha * pct_out + (1 - alpha) * ema_out_rates[key]
    downs[i] = string.format("%.1f", (ema_in_rates[key] or 0) * 100)
    ups[i] = string.format("%.1f", (ema_out_rates[key] or 0) * 100)
  end

  return { labels = order, down_values = downs, up_values = ups }
end

local function fmt_bytes_iec(bytes)
  local b = tonumber(bytes) or 0
  if b < 0 then b = 0 end
  local units = { "KiB", "MiB", "GiB", "TiB", "PiB" }
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

-- Safer text draw (guards missing cairo_* symbols)
local function draw_text_left(cr, x, y, text, font, size, r, g, b, a)
  if cairo_select_font_face then
    cairo_select_font_face(cr, font or "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  end
  if cairo_set_font_size then cairo_set_font_size(cr, size or 12) end
  if cairo_set_source_rgba then cairo_set_source_rgba(cr, r or 1, g or 1, b or 1, a or 1) end
  if cairo_move_to then cairo_move_to(cr, x, y) end
  if cairo_show_text then cairo_show_text(cr, tostring(text or "")) end
  if cairo_stroke then cairo_stroke(cr) end
end


local function draw_dbg(...) return end

--[[ -- Optional tiny debug line
local function draw_dbg(cr, x, y, TP, data, pi, po)
  if tget(TP, "pf.debug.text_block") ~= true then return end

  local font = tget(TP, "fonts.mono") or "DejaVu Sans Mono"
  if cairo_select_font_face then
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  end
  if cairo_set_font_size   then cairo_set_font_size(cr, 12) end
  if cairo_set_source_rgba then cairo_set_source_rgba(cr, 0.6, 0.9, 0.6, 1) end

  local wan_if = tget(TP, "ifaces.WAN") or "igc0"
  local linkMb = tget(TP, "link_mbps.WAN") or 1000
  local gw_on  = data and tget(data, "gateway.gateway_online") or "?"
  local ibytes = data and tget(data, ("interfaces.iface_%s_ibytes"):format(wan_if)) or "nil"
  local obytes = data and tget(data, ("interfaces.iface_%s_obytes"):format(wan_if)) or "nil" ]]

--[[ -- show the single-line DBG only if the theme flag is true
  local show_dbg = (TP and TP.pf and TP.pf.debug and TP.pf.debug.text_block) == true
  if show_dbg then
    local line = ("DBG wan_if=%s linkMb=%s gw=%s in%%=%s out%%=%s i/o=%s/%s")
    :format(
    tostring(wan_if),
    tostring(linkMb),
    tostring(gw_on),
    fmt_pct01(pct_in or 0),
    fmt_pct01(pct_out or 0),
    tostring(ibytes),
    tostring(obytes)
    )
    if cairo_move_to then cairo_move_to(cr, x, y) end
    if cairo_show_text then cairo_show_text(cr, line) end
    if cairo_stroke then cairo_stroke(cr) end
  end ]]



---------------------------------------------------------------------------
-- State for rate + smoothing
---------------------------------------------------------------------------
local prev_in_bytes, prev_out_bytes, prev_time = {}, {}, {}
local ema_in, ema_out = {}, {}
local ema_load, ema_mem = nil, nil

---------------------------------------------------------------------------
-- Main draw
---------------------------------------------------------------------------
function conky_pf_draw()
  if not conky_window then return end
  local ok = pcall(require, "cairo")
  if not ok or not (cairo_xlib_surface_create and cairo_create) then return end

  local cs         = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable, conky_window.visual,
    conky_window.width, conky_window.height
  )
  local cr         = cairo_create(cs)
  if cairo_set_operator then cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR) end
  if cairo_paint then cairo_paint(cr) end
  if cairo_set_operator then cairo_set_operator(cr, CAIRO_OPERATOR_OVER) end

  local TP         = pf_theme()
  local fonts      = tget(TP, "fonts") or {}
  local sizes      = tget(TP, "sizes") or {}
  local colors     = tget(TP, "colors") or {}

  local tr, tg, tb = 1, 1, 1
  if colors.text then tr, tg, tb = colors.text[1], colors.text[2], colors.text[3] end
  local okr, okg, okb = 0.2, 0.8, 0.4
  local badr, badg, badb = 0.95, 0.3, 0.25
  if colors.good then okr, okg, okb = colors.good[1], colors.good[2], colors.good[3] end
  if colors.bad then badr, badg, badb = colors.bad[1], colors.bad[2], colors.bad[3] end
  local font_mono               = fonts.mono or "DejaVu Sans Mono"
  local val_sz                  = sizes.value or 16

  -- text block
  local x                       = 20
  local y                       = 28
  local dy                      = 20

  -- fetch and compute percentages
  local data                    = maybe_fetch()
  local arc_order               = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
  local now                     = os.time()

  local mbps_in, mbps_out       = {}, {}
  local pct_in, pct_out         = {}, {}
  local cap_in_tbl, cap_out_tbl = {}, {}

  local function iface_val(ifn, suffix)
    if not ifn then return nil end
    local v = tget(data, ("interfaces.iface_%s_%s"):format(ifn, suffix))
    if v == nil and ifn:find("%.") then
      local ifn_u = ifn:gsub("%.", "_")
      v = tget(data, ("interfaces.iface_%s_%s"):format(ifn_u, suffix))
    end
    return v
  end

  for _, key in ipairs(arc_order) do
    local ifn = tget(TP, "ifaces." .. key)
    if data and ifn then
      local ibytes = safe_num(iface_val(ifn, "ibytes"))
      local obytes = safe_num(iface_val(ifn, "obytes"))

      local prev_in = prev_in_bytes[key]
      local prev_out = prev_out_bytes[key]
      local last = prev_time[key] or 0
      local dt = now - last

      local in_rate, out_rate = 0, 0
      if prev_in and dt > 0 and ibytes >= prev_in then
        in_rate = (ibytes - prev_in) / dt
      end
      if prev_out and dt > 0 and obytes >= prev_out then
        out_rate = (obytes - prev_out) / dt
      end

      prev_in_bytes[key] = ibytes
      prev_out_bytes[key] = obytes
      prev_time[key] = now

      mbps_in[key] = in_rate * 8 / 1e6
      mbps_out[key] = out_rate * 8 / 1e6
    else
      mbps_in[key] = 0
      mbps_out[key] = 0
    end

    local link_in = tget(TP, ("link_mbps_in.%s"):format(key))
    local link_out = tget(TP, ("link_mbps_out.%s"):format(key))
    local link = tget(TP, ("link_mbps.%s"):format(key)) or 1000

    local cap_in = tonumber(link_in or link) or 1000
    local cap_out = tonumber(link_out or link) or 1000
    cap_in_tbl[key] = cap_in
    cap_out_tbl[key] = cap_out

    pct_in[key] = scale_pct(mbps_in[key], cap_in, TP, key)
    pct_out[key] = scale_pct(mbps_out[key], cap_out, TP, key)
  end

  local wan_mbps_in = mbps_in.WAN or 0
  local wan_mbps_out = mbps_out.WAN or 0
  local wan_pct_in = pct_in.WAN or 0
  local wan_pct_out = pct_out.WAN or 0



  -- SHOW/HIDE the legacy 5-line reader text (only if pf.debug.text_block == true)
  if (tget(TP, "pf.debug.text_block") == true) and data then
    -- uptime / cpu
    local uptime   = tget(data, "system.uptime") or "?"
    local cpu_idle = tget(data, "system.cpu_idle") or "?"
    draw_text_left(cr, x, y, ("pfSense uptime: %s"):format(uptime), font_mono, val_sz, tr, tg, tb, 1); y = y + dy
    draw_text_left(cr, x, y, ("CPU idle: %s%%"):format(cpu_idle), font_mono, val_sz, tr, tg, tb, 1); y = y + dy

    -- gateway
    local gw_on = tget(data, "gateway.gateway_online") or "0"
    local gw_ip = tget(data, "gateway.gateway_ip") or "?"
    local gr, gg, gb = (gw_on == "1") and okr or badr, (gw_on == "1") and okg or badg, (gw_on == "1") and okb or badb
    draw_text_left(cr, x, y, ("Gateway: %s  (%s)"):format(gw_on == "1" and "ONLINE" or "OFFLINE", gw_ip), font_mono,
      val_sz, gr, gg, gb, 1); y = y + dy

    draw_text_left(cr, x, y, ("WAN in/out: %5.2f / %5.2f Mbps   (scaled %%: %s / %s)")
      :format(wan_mbps_in, wan_mbps_out, fmt_pct01(wan_pct_in), fmt_pct01(wan_pct_out)), font_mono, val_sz, tr, tg, tb, 1); y =
        y + dy

    draw_text_left(cr, x, y, ("Caps OUT: WAN %s HOME %s IOT %s GUEST %s INFRA %s CAM %s")
      :format(
        tostring(cap_out_tbl.WAN or "?"),
        tostring(cap_out_tbl.HOME or "?"),
        tostring(cap_out_tbl.IOT or "?"),
        tostring(cap_out_tbl.GUEST or "?"),
        tostring(cap_out_tbl.INFRA or "?"),
        tostring(cap_out_tbl.CAM or "?")
      ), font_mono, val_sz, tr, tg, tb, 1); y = y + dy

    draw_text_left(cr, x, y, ("Caps IN: WAN %s HOME %s IOT %s GUEST %s INFRA %s CAM %s")
      :format(
        tostring(cap_in_tbl.WAN or "?"),
        tostring(cap_in_tbl.HOME or "?"),
        tostring(cap_in_tbl.IOT or "?"),
        tostring(cap_in_tbl.GUEST or "?"),
        tostring(cap_in_tbl.INFRA or "?"),
        tostring(cap_in_tbl.CAM or "?")
      ), font_mono, val_sz, tr, tg, tb, 1); y = y + dy

    draw_text_left(cr, x, y, ("pct_out: WAN %s HOME %s IOT %s GUEST %s INFRA %s CAM %s")
      :format(
        fmt_pct01(pct_out.WAN or 0),
        fmt_pct01(pct_out.HOME or 0),
        fmt_pct01(pct_out.IOT or 0),
        fmt_pct01(pct_out.GUEST or 0),
        fmt_pct01(pct_out.INFRA or 0),
        fmt_pct01(pct_out.CAM or 0)
      ), font_mono, val_sz, tr, tg, tb, 1); y = y + dy

    draw_text_left(cr, x, y,
      ("Mbps: WAN %4.1f/%4.1f HOME %4.1f/%4.1f IOT %4.1f/%4.1f GUEST %4.1f/%4.1f INFRA %4.1f/%4.1f CAM %4.1f/%4.1f")
      :format(
        mbps_in.WAN or 0, mbps_out.WAN or 0,
        mbps_in.HOME or 0, mbps_out.HOME or 0,
        mbps_in.IOT or 0, mbps_out.IOT or 0,
        mbps_in.GUEST or 0, mbps_out.GUEST or 0,
        mbps_in.INFRA or 0, mbps_out.INFRA or 0,
        mbps_in.CAM or 0, mbps_out.CAM or 0
      ), font_mono, val_sz, tr, tg, tb, 1); y = y + dy

    -- pfBlockerNG totals
    local pfb_ip  = tget(data, "pfblockerng.pfb_ip_total") or "0"
    local pfb_dns = tget(data, "pfblockerng.pfb_dnsbl_total") or "0"
    draw_text_left(cr, x, y, ("pfBlockerNG: IP=%s  DNSBL=%s"):format(pfb_ip, pfb_dns), font_mono, val_sz, tr, tg, tb, 1); y =
        y + dy
  end

  -- debug line if enabled
  draw_dbg(cr, 20, y + 8, TP, data, wan_pct_in, wan_pct_out)

  ---------------------------------------------------------------------------
  -- ARC + moving markers + trails + labels + horizontal baseline
  ---------------------------------------------------------------------------
  do
    local arc     = tget(TP, "pf.arc") or {}
    local mk      = tget(TP, "pf.markers") or {}
    local trail   = tget(TP, "pf.trail") or {}
    local hline   = tget(TP, "pf.hline") or {}
    local hline_enabled = (hline.enabled == true) or (hline.enabled == nil and next(hline) ~= nil)

    local a_r     = tonumber(arc.r) or 160
    local a_w     = tonumber(arc.width) or 6
    local a_dx    = tonumber(arc.dx) or 0
    local a_dy    = tonumber(arc.dy) or 0
    local a_start = tonumber(arc.start) or 180
    local a_end   = tonumber(arc["end"]) or 0
    local a_col   = arc.color or { 0.65, 0.65, 0.65, 1.0 }

    local function deg2rad(d) return (math.pi / 180) * (tonumber(d) or 0) end
    local function clamp01(v)
      v = tonumber(v) or 0; if v < 0 then return 0 elseif v > 1 then return 1 else return v end
    end
    local function lerp(a, b, t) return a + (b - a) * clamp01(t) end

    local function polar(cx, cy, radius, angle)
      return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
    end

    local function set_rgba(col, alpha)
      local a = alpha or 1
      if type(col) == "table" and col[4] then a = col[4] * a end
      if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], a) end
    end

    local function draw_text_arc(cr, cx, cy, r, angle_mid, txt, font_face, font_size, col, alpha)
      if txt == nil or txt == "" or r <= 0 then return end
      set_rgba(col or { 1, 1, 1 }, alpha or 1)
      if cairo_select_font_face then cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL) end
      if cairo_set_font_size then cairo_set_font_size(cr, font_size) end

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
        local rot = a + (math.pi / 2)

        if cairo_save then cairo_save(cr) end
        if cairo_translate then cairo_translate(cr, x, y) end
        if cairo_rotate then cairo_rotate(cr, rot) end
        if cairo_move_to then cairo_move_to(cr, -(p.ext.width / 2 + p.ext.x_bearing), p.ext.height / 2) end
        if cairo_show_text then cairo_show_text(cr, p.ch) end
        if cairo_restore then cairo_restore(cr) end

        angle = angle + (p.adv / r)
      end
    end

    local W, H   = conky_window.width, conky_window.height
    local cx     = math.floor(W / 2) + a_dx
    local cy     = math.floor(H / 2) + a_dy

    local margin = 8
    local r_fit  = math.floor((math.min(W, H) - 2 * margin) / 2)
    local Rwan   = math.max(4, math.min(a_r, r_fit))
    local arcs   = {}

    local sr         = deg2rad(a_start)
    local er         = deg2rad(a_end)
    local split_mid  = deg2rad(tonumber(arc.split_angle_deg) or 90)
    local split_gap  = deg2rad(tonumber(arc.split_gap_deg) or 1.2)
    local EPS        = deg2rad(0.6) -- tiny gap to prevent visual overhang

    local function cw_span(s, e)
      if s >= e then return s - e end
      return (math.pi * 2) - (e - s)
    end

    local function ccw_span(s, e)
      if e >= s then return e - s end
      return (math.pi * 2) - (s - e)
    end

    local function cw_contains(s, e, mid)
      return cw_span(s, mid) <= cw_span(s, e)
    end

    local function normalize_arc(a1, a2)
      if cw_span(a1, a2) > math.pi then
        return a2, a1
      end
      return a1, a2
    end

    local function lerp_cw(a1, a2, t)
      local span = cw_span(a1, a2)
      return a1 - (span * clamp01(t))
    end

    local function lerp_ccw(a1, a2, t)
      local span = ccw_span(a1, a2)
      return a1 + (span * clamp01(t))
    end

    local function resolve_arc_angles(offsets)
      local o = offsets or {}
      local s_off = tonumber(o.start_offset) or 0
      local e_off = tonumber(o.end_offset) or 0
      local ls_off = tonumber(o.left_start_offset) or s_off
      local le_off = tonumber(o.left_end_offset) or e_off
      local rs_off = tonumber(o.right_start_offset)
      if rs_off == nil then rs_off = -s_off end
      local re_off = tonumber(o.right_end_offset)
      if re_off == nil then re_off = -e_off end

      local base_sr = sr
      local base_er = er
      local sr_local = sr + deg2rad(s_off)
      local er_local = er + deg2rad(e_off)

      local ls = arc.left_start
      local le = arc.left_end
      local rs = arc.right_start
      local re = arc.right_end
      local base_ls = ls
      local base_le = le
      local base_rs = rs
      local base_re = re
      if ls ~= nil then ls = ls + ls_off end
      if le ~= nil then le = le + le_off end
      if rs ~= nil then rs = rs + rs_off end
      if re ~= nil then re = re + re_off end

      local has_left = (ls ~= nil and le ~= nil)
      local has_right = (rs ~= nil and re ~= nil)
      local base_has_left = (base_ls ~= nil and base_le ~= nil)
      local base_has_right = (base_rs ~= nil and base_re ~= nil)
      local raw_left_start = has_left and deg2rad(ls) or nil
      local raw_left_end = has_left and deg2rad(le) or nil
      local raw_right_start = has_right and deg2rad(rs) or nil
      local raw_right_end = has_right and deg2rad(re) or nil
      local base_raw_left_start = base_has_left and deg2rad(base_ls) or nil
      local base_raw_left_end = base_has_left and deg2rad(base_le) or nil
      local base_raw_right_start = base_has_right and deg2rad(base_rs) or nil
      local base_raw_right_end = base_has_right and deg2rad(base_re) or nil

      local left_start_a, left_end_a, right_start_a, right_end_a = nil, nil, nil, nil
      local base_left_start_a, base_left_end_a, base_right_start_a, base_right_end_a = nil, nil, nil, nil
      if cw_contains(sr_local, er_local, split_mid) then
        left_start_a, left_end_a = sr_local, split_mid + (split_gap / 2)
        right_start_a, right_end_a = split_mid - (split_gap / 2), er_local
      else
        left_start_a, left_end_a = sr_local, er_local
        right_start_a, right_end_a = nil, nil
      end
      if cw_contains(base_sr, base_er, split_mid) then
        base_left_start_a, base_left_end_a = base_sr, split_mid + (split_gap / 2)
        base_right_start_a, base_right_end_a = split_mid - (split_gap / 2), base_er
      else
        base_left_start_a, base_left_end_a = base_sr, base_er
        base_right_start_a, base_right_end_a = nil, nil
      end

      if has_left then
        left_start_a, left_end_a = normalize_arc(raw_left_start, raw_left_end)
      end
      if has_right then
        right_start_a, right_end_a = normalize_arc(raw_right_start, raw_right_end)
      end
      if base_has_left then
        base_left_start_a, base_left_end_a = normalize_arc(base_raw_left_start, base_raw_left_end)
      end
      if base_has_right then
        base_right_start_a, base_right_end_a = normalize_arc(base_raw_right_start, base_raw_right_end)
      end

      return {
        left_start_a = left_start_a,
        left_end_a = left_end_a,
        right_start_a = right_start_a,
        right_end_a = right_end_a,
        raw_left_start = raw_left_start,
        raw_left_end = raw_left_end,
        raw_right_start = raw_right_start,
        raw_right_end = raw_right_end,
        base_left_start_a = base_left_start_a,
        base_left_end_a = base_left_end_a,
        base_right_start_a = base_right_start_a,
        base_right_end_a = base_right_end_a,
        base_raw_left_start = base_raw_left_start,
        base_raw_left_end = base_raw_left_end,
        base_raw_right_start = base_raw_right_start,
        base_raw_right_end = base_raw_right_end,
        delta_left_start = (base_left_start_a and left_start_a) and (left_start_a - base_left_start_a) or 0,
        delta_left_end = (base_left_end_a and left_end_a) and (left_end_a - base_left_end_a) or 0,
        delta_right_start = (base_right_start_a and right_start_a) and (right_start_a - base_right_start_a) or 0,
        delta_right_end = (base_right_end_a and right_end_a) and (right_end_a - base_right_end_a) or 0,
      }
    end

    local function draw_arc(xc, yc, R, col, w, angles)
      cairo_save(cr)
      cairo_translate(cr, xc, yc)
      cairo_scale(cr, 1, -1)
      local aw = w or a_w
      if cairo_set_line_width then cairo_set_line_width(cr, aw) end
      if cairo_set_line_cap then cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT) end
      local ac = col or a_col
      if cairo_set_source_rgba then cairo_set_source_rgba(cr, ac[1], ac[2], ac[3], ac[4] or 1) end
      local function draw_seg(a1, a2)
        local cw = cw_span(a1, a2)
        local ccw = ccw_span(a1, a2)
        if cairo_new_sub_path then cairo_new_sub_path(cr) end
        if cw <= ccw then
          if cairo_arc_negative then
            cairo_arc_negative(cr, 0, 0, R, a1, a2)
          else
            cairo_arc(cr, 0, 0, R, a2, a1) -- fallback
          end
        else
          if cairo_arc then
            cairo_arc(cr, 0, 0, R, a1, a2)
          elseif cairo_arc_negative then
            cairo_arc_negative(cr, 0, 0, R, a2, a1) -- fallback
          end
        end
      end
      local a = angles or {}
      if a.left_start_a and a.left_end_a then
        draw_seg(a.left_start_a, a.left_end_a)
      end
      if a.right_start_a and a.right_end_a then
        draw_seg(a.right_start_a, a.right_end_a)
      end
      if cairo_stroke then cairo_stroke(cr) end
      cairo_restore(cr)
    end
    local left_start_a, left_end_a, right_start_a, right_end_a = nil, nil, nil, nil
    local raw_left_start, raw_left_end, raw_right_start, raw_right_end = nil, nil, nil, nil

    local function store_arc(key, ang, x, y, r)
      arcs[key] = {
        cx = x,
        cy = y,
        R = r,
        left_start_a = ang.left_start_a,
        left_end_a = ang.left_end_a,
        right_start_a = ang.right_start_a,
        right_end_a = ang.right_end_a,
        raw_left_start = ang.raw_left_start,
        raw_left_end = ang.raw_left_end,
        raw_right_start = ang.raw_right_start,
        raw_right_end = ang.raw_right_end,
      }
    end

    -- Base dome arc (WAN)
    local Awan = tget(TP, "pf.arcs.WAN") or {}
    local wan_col = Awan.color or a_col
    local wan_w = Awan.width or a_w
    local ang_wan = resolve_arc_angles(Awan)
    draw_arc(cx, cy, Rwan, wan_col, wan_w, ang_wan)
    store_arc("WAN", ang_wan, cx, cy, Rwan)
    left_start_a, left_end_a = ang_wan.left_start_a, ang_wan.left_end_a
    right_start_a, right_end_a = ang_wan.right_start_a, ang_wan.right_end_a
    raw_left_start, raw_left_end = ang_wan.raw_left_start, ang_wan.raw_left_end
    raw_right_start, raw_right_end = ang_wan.raw_right_start, ang_wan.raw_right_end

    -- Inner HOME arc (same styling; spacing via deltaR)
    local deltaR = tonumber(tget(TP, "pf.deltaR")) or 24
    local k      = clamp01(tget(TP, "pf.anchor_strength"))

    local Rhome  = math.max(4, Rwan - deltaR)
    local delta  = Rwan - Rhome
    local cyhome = cy - k * delta
    local Ahome = tget(TP, "pf.arcs.HOME") or {}
    local home_col = Ahome.color or a_col
    local home_w = Ahome.width or a_w
    local ang_home = resolve_arc_angles(Ahome)
    draw_arc(cx, cyhome, Rhome, home_col, home_w, ang_home)
    store_arc("HOME", ang_home, cx, cyhome, Rhome)

    local Riot  = Rhome - deltaR
    local cyiot = nil
    if Riot >= 4 then
      local delta_iot = Rhome - Riot
      cyiot           = cyhome - k * delta_iot
      local A         = tget(TP, "pf.arcs.IOT") or {}
      local iot_col   = A.color or a_col
      local iot_w     = A.width or a_w
      local ang_iot   = resolve_arc_angles(A)
      draw_arc(cx, cyiot, Riot, iot_col, iot_w, ang_iot)
      store_arc("IOT", ang_iot, cx, cyiot, Riot)
    end

    local Rguest = Riot - deltaR
    local cyguest = nil
    if cyiot and Rguest >= 4 then
      local delta_guest = Riot - Rguest
      cyguest           = cyiot - k * delta_guest
      local A           = tget(TP, "pf.arcs.GUEST") or {}
      local guest_col   = A.color or a_col
      local guest_w     = A.width or a_w
      local ang_guest   = resolve_arc_angles(A)
      draw_arc(cx, cyguest, Rguest, guest_col, guest_w, ang_guest)
      store_arc("GUEST", ang_guest, cx, cyguest, Rguest)
    end

    local Rinfra = Rguest - deltaR
    local cyinfra = nil
    if cyguest and Rinfra >= 4 then
      local delta_infra = Rguest - Rinfra
      cyinfra           = cyguest - k * delta_infra
      local A           = tget(TP, "pf.arcs.INFRA") or {}
      local infra_col   = A.color or a_col
      local infra_w     = A.width or a_w
      local ang_infra   = resolve_arc_angles(A)
      draw_arc(cx, cyinfra, Rinfra, infra_col, infra_w, ang_infra)
      store_arc("INFRA", ang_infra, cx, cyinfra, Rinfra)
    end

    local Rcam = Rinfra - deltaR
    if cyinfra and Rcam >= 4 then
      local delta_cam = Rinfra - Rcam
      local cycam     = cyinfra - k * delta_cam
      local A         = tget(TP, "pf.arcs.CAM") or {}
      local cam_col   = A.color or a_col
      local cam_w     = A.width or a_w
      local ang_cam   = resolve_arc_angles(A)
      draw_arc(cx, cycam, Rcam, cam_col, cam_w, ang_cam)
      store_arc("CAM", ang_cam, cx, cycam, Rcam)
    end

    ----------------------------------------------------------------
    -- Static top label (e.g. "100%") from theme-pf.lua
    ----------------------------------------------------------------
    do
      local TL = tget(TP, "pf.top_label") or {}
      if TL.enabled then
        local txt       = TL.text or "100%"
        local dy        = tonumber(TL.dy or 10)
        local L         = tget(TP, "pf.labels") or {}
        local font      = L.font or "DejaVu Sans"
        local size      = tonumber(L.size) or 12
        local color     = L.color or { 0.85, 0.85, 0.85, 1.0 }

        -- position: arc apex (top of dome)
        local mid_angle = math.rad(90)
        local tx        = cx + Rwan * math.cos(mid_angle)
        local ty        = cy - Rwan * math.sin(mid_angle) + dy

        cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, size)
        cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4] or 1)

        local te = cairo_text_extents_t:create()
        cairo_text_extents(cr, txt, te)
        cairo_move_to(cr, tx - te.width / 2, ty)
        cairo_show_text(cr, txt)
        cairo_stroke(cr)
      end
    end
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Center meters: LOAD and MEM% (vertical bars under apex)
    ----------------------------------------------------------------
    do
      local CM = tget(TP, "pf.center_meters")
      if CM and CM.enabled ~= false then
        -- theme
        local dx          = tonumber(CM.dx or 0)
        local dy          = tonumber(CM.dy or 40)
        local H           = tonumber(CM.height or 150)
        local W           = tonumber(CM.width or 90)
        local GAP         = tonumber(CM.gap or 60)
        local RADIUS      = tonumber(CM.radius or 10)
        local STROKE      = tonumber(CM.stroke or 2)

        local col_frame   = CM.color_frame or { 0.85, 0.85, 0.90, 0.9 }
        local col_back    = CM.color_back or { 0.12, 0.12, 0.14, 1.0 }
        local col_fill    = CM.color_fill or { 1.00, 0.80, 0.10, 1.0 }

        local lbl_size    = tonumber(CM.label_size or 14)
        local lbl_color   = CM.label_color or { 0.95, 0.97, 0.99, 1.0 }
        local mem_lbl     = CM.mem_label or "MEM%"

        local SEP         = CM.separator or {}
        local sep_on      = (SEP.enabled ~= false)
        local sep_w       = tonumber(SEP.width or 2)
        local sep_dy      = tonumber(SEP.dy or 0)
        local sep_color   = SEP.color or { 0.50, 0.50, 0.55, 0.9 }

        -- position (group centered at arc center)
        local gx          = cx + dx
        local gy          = cy + dy
        local xL          = math.floor(gx - (GAP / 2) - W) -- left bar (LOAD)
        local xR          = math.floor(gx + (GAP / 2))     -- right bar (MEM)
        local yTop        = gy                             -- top of bars
        local yBot        = gy + H                         -- bottom of bars

        -- data: LOAD (normalized per-core) and MEM used %
        local load_cfg    = tget(TP, "pf.load") or {}
        local load_window = tonumber(load_cfg.window) or 5
        if load_window ~= 1 and load_window ~= 5 and load_window ~= 15 then load_window = 5 end

        local load_key   = "system.load_" .. tostring(load_window)
        local load_val   = tonumber(tget(data, load_key) or "")
        local cores_cfg  = tget(TP, "pf.load.cores")
        local cores      = nil
        local cores_star = ""

        if cores_cfg == nil or cores_cfg == "auto" then
          cores = tonumber(tget(data, "system.ncpu"))
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

        local load_norm = 0
        if load_val and cores > 0 then load_norm = load_val / cores end

        local load_val_str = load_val and string.format("%.2f", load_val) or "?"
        local load_lbl     = string.format("L%d %s / %dc%s", load_window, load_val_str, cores, cores_star)

        local mem_used_pct = nil
        do
          -- prefer explicit percent if fetcher provides it
          local raw = tget(data, "system.mem_used_pct") or tget(data, "memory.mem_used_pct")
          if raw then
            local raw_s = tostring(raw):gsub("%%", "")
            mem_used_pct = tonumber(raw_s)
          end
          -- try to parse from a line if needed (first % number)
          if not mem_used_pct then
            local ml = tget(data, "system.mem_line") or tget(data, "memory.mem_line")
            if type(ml) == "string" then
              local p = ml:match("(%d+%.?%d*)%s*%%")
              if p then mem_used_pct = tonumber(p) end
            end
          end
          if not mem_used_pct then mem_used_pct = 0 end
          mem_used_pct = math.max(0, math.min(100, mem_used_pct))
        end

        -- smoothing just for these meters (EMA)
        local alpha = tonumber(tget(TP, "pf.center_meters.smoothing.alpha") or 0.35)
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        if ema_load == nil then ema_load = load_norm end
        if ema_mem == nil then ema_mem = mem_used_pct / 100 end
        ema_load = alpha * load_norm + (1 - alpha) * ema_load
        ema_mem = alpha * (mem_used_pct / 100) + (1 - alpha) * ema_mem




        -- helpers
        local function clamp01(v)
          v = tonumber(v) or 0; if v < 0 then return 0 elseif v > 1 then return 1 else return v end
        end

        -- raw EMA → visual (% of bar) with gentle curve + tiny floor
        local CV       = CM.curve or {}
        local g        = tonumber(CV.gamma or 0.60)
        local minG     = tonumber(CV.min_pct or 0.06)
        local minC     = tonumber(CV.cpu_min_pct or minG)
        local minM     = tonumber(CV.mem_min_pct or minG)

        local pCPU_raw = clamp01(ema_load)
        local pMEM_raw = clamp01(ema_mem)

        local function curve_pct(p, gamma, floor_min)
          p = clamp01(p)
          gamma = tonumber(gamma) or 1
          floor_min = tonumber(floor_min or 0) or 0
          -- visual = floor + (1-floor) * (p^gamma)
          return clamp01(floor_min + (1 - floor_min) * (p ^ gamma))
        end

        local pCPU = curve_pct(pCPU_raw, g, minC)
        local pMEM = curve_pct(pMEM_raw, g, minM)

        local load_color = col_fill
        do
          local LT = tget(TP, "pf.load_thresholds") or {}
          if LT.enabled ~= false then
            local ok_t   = tonumber(LT.ok) or 0.50
            local warn_t = tonumber(LT.warn) or 1.00
            local crit_t = tonumber(LT.crit) or 1.50

            local good_c = colors.good or col_fill
            local warn_c = colors.warn or col_fill
            local bad_c  = colors.bad or col_fill

            local n      = load_norm or 0
            if n < ok_t then
              load_color = good_c
            elseif n < warn_t then
              load_color = warn_c
            elseif n < crit_t then
              load_color = warn_c
            else
              load_color = bad_c
            end
          end
        end





        -- helpers
        local function rr(x, y, w, h, r)
          -- rounded-rect path (guards for Cairo availability)
          if not (cairo_move_to and cairo_arc and cairo_line_to and cairo_close_path) then
            if cairo_rectangle then cairo_rectangle(cr, x, y, w, h) end
            return
          end
          local r2 = math.max(0, math.min(r or 0, math.min(w, h) / 2))
          cairo_move_to(cr, x + r2, y)
          cairo_line_to(cr, x + w - r2, y); cairo_arc(cr, x + w - r2, y + r2, r2, -math.pi / 2, 0)
          cairo_line_to(cr, x + w, y + h - r2); cairo_arc(cr, x + w - r2, y + h - r2, r2, 0, math.pi / 2)
          cairo_line_to(cr, x + r2, y + h); cairo_arc(cr, x + r2, y + h - r2, r2, math.pi / 2, math.pi)
          cairo_line_to(cr, x, y + r2); cairo_arc(cr, x + r2, y + r2, r2, math.pi, 3 * math.pi / 2)
          cairo_close_path(cr)
        end

        local function draw_bar(x)
          -- frame
          if cairo_save then cairo_save(cr) end
          rr(x, yTop, W, H, RADIUS)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col_back[1], col_back[2], col_back[3], col_back[4] or 1) end
          if cairo_fill_preserve then cairo_fill_preserve(cr) elseif cairo_fill then cairo_fill(cr) end
          if cairo_set_line_width then cairo_set_line_width(cr, STROKE) end
          if cairo_set_source_rgba then
            cairo_set_source_rgba(cr, col_frame[1], col_frame[2], col_frame[3],
              col_frame[4] or 1)
          end
          if cairo_stroke then cairo_stroke(cr) end
          if cairo_restore then cairo_restore(cr) end
        end

        local function draw_fill(x, pct, color)
          pct       = clamp01(pct)
          local pad = math.max(1, STROKE) -- inset so the frame stays visible
          local fh  = math.max(0, (H - 2 * pad) * pct)
          local fy  = yBot - pad - fh
          local fx  = x + pad
          local fw  = W - 2 * pad
          if cairo_rectangle then cairo_rectangle(cr, fx, fy, fw, fh) end
          local c = color or col_fill
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4] or 1) end
          if cairo_fill then cairo_fill(cr) end
        end

        local function draw_label(x, text, dx_override)
          local fnt  = tget(TP, "fonts.regular") or "DejaVu Sans"
          local txt  = tostring(text or "")
          local size = tonumber(lbl_size or 14) or 14
          local dx   = (dx_override ~= nil) and dx_override or (tonumber(CM.label_dx or 0) or 0)
          local tx   = x + W / 2 + dx
          local ty   = yBot + (size + 6)

          if cairo_select_font_face then
            cairo_select_font_face(cr, fnt, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
          end
          if cairo_set_font_size then cairo_set_font_size(cr, size) end
          if cairo_set_source_rgba then
            cairo_set_source_rgba(cr, lbl_color[1], lbl_color[2], lbl_color[3], lbl_color[4] or 1)
          end

          -- simple width estimate: ~0.6 * size per character
          local est_half = 0.5 * (size * 0.6 * #txt)

          if cairo_move_to then cairo_move_to(cr, tx - est_half, ty) end
          if cairo_show_text then cairo_show_text(cr, txt) end
          if cairo_stroke then cairo_stroke(cr) end
        end


        -- bars + fills + labels
        draw_bar(xL); draw_bar(xR)
        draw_fill(xL, pCPU, load_color); draw_fill(xR, pMEM, col_fill)
        draw_label(xL, load_lbl, tonumber(CM.label_dx_load))
        draw_label(xR, mem_lbl, tonumber(CM.label_dx_mem))

        -- separator
        if sep_on then
          local len = tonumber(SEP.length or 0)
          local y1, y2
          if len and len > 0 then
            local half = len / 2
            local midy = (yTop + yBot) / 2
            y1 = midy - half + sep_dy
            y2 = midy + half - sep_dy
          else
            -- default: match bar height
            y1 = yTop + sep_dy
            y2 = yBot - sep_dy
          end
          if cairo_set_source_rgba then
            cairo_set_source_rgba(cr, sep_color[1], sep_color[2], sep_color[3],
              sep_color[4] or 1)
          end
          if cairo_set_line_width then cairo_set_line_width(cr, sep_w) end
          if cairo_move_to then cairo_move_to(cr, gx, y1) end
          if cairo_line_to then cairo_line_to(cr, gx, y2) end
          if cairo_stroke then cairo_stroke(cr) end
        end
      end
    end
    ----------------------------------------------------------------

    -- Nameplate under center meters
    do
      local NP = tget(TP, "pf.nameplate") or {}
      if NP.enabled ~= false then
        local txt   = NP.text or ""
        local font  = NP.font or "DejaVu Sans"
        local size  = tonumber(NP.size) or 14
        local col   = NP.color or { 0.85, 0.85, 0.85, 1.0 }
        local dx    = tonumber(NP.dx) or 0
        local dy    = tonumber(NP.dy) or 0
        local align = NP.align or "center"

        if cairo_select_font_face then
          cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        end
        if cairo_set_font_size then cairo_set_font_size(cr, size) end
        if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end

        local tx = cx + dx
        local ty = cy + dy
        local offset = 0
        if align == "center" then
          if cairo_text_extents then
            local te = cairo_text_extents_t:create()
            cairo_text_extents(cr, txt, te)
            offset = te.width / 2
          else
            offset = 0.5 * (size * 0.6 * #tostring(txt))
          end
        elseif align == "right" then
          if cairo_text_extents then
            local te = cairo_text_extents_t:create()
            cairo_text_extents(cr, txt, te)
            offset = te.width
          else
            offset = (size * 0.6 * #tostring(txt))
          end
        end

        if cairo_move_to then cairo_move_to(cr, tx - offset, ty) end
        if cairo_show_text then cairo_show_text(cr, txt) end
        if cairo_stroke then cairo_stroke(cr) end
      end
    end

    -- EMA smoothing for nicer motion (theme knob)
    do
      local S     = tget(TP, "pf.smoothing") or {}
      local alpha = tonumber(S.alpha) or 0.35
      if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
      for _, key in ipairs(arc_order) do
        local pin = pct_in[key] or 0
        local pout = pct_out[key] or 0
        if ema_in[key] == nil then ema_in[key] = pin end
        if ema_out[key] == nil then ema_out[key] = pout end
        ema_in[key]  = alpha * pin + (1 - alpha) * ema_in[key]
        ema_out[key] = alpha * pout + (1 - alpha) * ema_out[key]
      end
    end

    -- marker angles (0% at arc start → 100% at arc end)
    local mid          = split_mid
    local ema_in_wan   = ema_in.WAN or 0
    local ema_out_wan  = ema_out.WAN or 0
    local has_right    = (raw_right_start ~= nil and raw_right_end ~= nil)
    local in_start     = raw_left_start or left_start_a or sr
    local in_end       = raw_left_end or left_end_a or mid
    local out_start    = (has_right and raw_right_start) or (right_start_a or er)
    local out_end      = (has_right and raw_right_end) or (right_end_a or mid)
    local mkp          = tget(TP, "pf.markers") or {}
    local pad_s        = deg2rad(tonumber(mkp.pad_start_deg) or 0)
    local pad_e        = deg2rad(tonumber(mkp.pad_end_deg) or 0)
    local pad_mode     = (mkp.pad_mode == "before") and "before" or "after"

    local function pad_arc(a1, a2, ccw)
      local span = (ccw and ccw_span(a1, a2)) or cw_span(a1, a2)
      if (pad_s + pad_e) >= span then return a1, a2 end
      if ccw then
        return a1 + pad_s, a2 - pad_e
      end
      return a1 - pad_s, a2 + pad_e
    end

    local function pad_with_mode(base_s, base_e, final_s, final_e, ccw, d_s, d_e)
      if pad_mode == "before" and base_s and base_e then
        local ps, pe = pad_arc(base_s, base_e, ccw)
        ps = ps + (d_s or 0)
        pe = pe + (d_e or 0)
        return ps, pe
      end
      return pad_arc(final_s, final_e, ccw)
    end

    local in_start_p, in_end_p = pad_with_mode(
      base_raw_left_start or raw_left_start or left_start_a or sr,
      base_raw_left_end or raw_left_end or left_end_a or mid,
      in_start, in_end, false,
      (base_raw_left_start and raw_left_start) and (raw_left_start - base_raw_left_start) or 0,
      (base_raw_left_end and raw_left_end) and (raw_left_end - base_raw_left_end) or 0
    )
    local out_start_p, out_end_p = pad_with_mode(
      base_raw_right_start or raw_right_start or right_start_a or er,
      base_raw_right_end or raw_right_end or right_end_a or mid,
      out_start, out_end, has_right,
      (base_raw_right_start and raw_right_start) and (raw_right_start - base_raw_right_start) or 0,
      (base_raw_right_end and raw_right_end) and (raw_right_end - base_raw_right_end) or 0
    )

    local ti           = lerp_cw(in_start_p, in_end_p, ema_in_wan)
    local to           = (has_right and lerp_ccw(out_start_p, out_end_p, ema_out_wan))
                    or lerp_cw(out_start_p, out_end_p, ema_out_wan)

    -- Progress trails (draw in the same local coords as the base arc)
    do
      local tw       = tonumber(trail.width) or a_w
      local cin      = trail["in"] or a_col
      local cout     = trail["out"] or a_col

      local ti_trail = ti
      local to_trail = to
      local out_dir_ccw = has_right

      if cairo_save then cairo_save(cr) end
      if cairo_translate then cairo_translate(cr, cx, cy) end
      if cairo_scale then cairo_scale(cr, 1, -1) end -- match base arc’s orientation
      if cairo_set_line_cap then cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT) end
      if cairo_set_line_width then cairo_set_line_width(cr, tw) end

      -- IN trail: left segment from arc start up to ti_trail
      if cw_span(in_start_p, ti_trail) > 1e-6 then
        if cairo_set_source_rgba then cairo_set_source_rgba(cr, cin[1], cin[2], cin[3], cin[4] or 1) end
        if cairo_arc_negative then
          cairo_arc_negative(cr, 0, 0, Rwan, in_start_p + EPS, ti_trail)
        else
          cairo_arc(cr, 0, 0, Rwan, ti_trail, in_start_p + EPS) -- fallback
        end
        if cairo_stroke then cairo_stroke(cr) end
      end

      -- OUT trail: right segment from arc start up to to_trail
      if (out_dir_ccw and ccw_span(out_start_p, to_trail) > 1e-6)
        or ((not out_dir_ccw) and cw_span(out_start_p, to_trail) > 1e-6) then
        if cairo_set_source_rgba then cairo_set_source_rgba(cr, cout[1], cout[2], cout[3], cout[4] or 1) end
        if out_dir_ccw then
          if cairo_arc then
            cairo_arc(cr, 0, 0, Rwan, out_start_p + EPS, to_trail)
          elseif cairo_arc_negative then
            cairo_arc_negative(cr, 0, 0, Rwan, to_trail, out_start_p + EPS) -- fallback
          end
        else
          if cairo_arc_negative then
            cairo_arc_negative(cr, 0, 0, Rwan, to_trail, out_start_p + EPS)
          else
            cairo_arc(cr, 0, 0, Rwan, out_start_p + EPS, to_trail) -- fallback
          end
        end
        if cairo_stroke then cairo_stroke(cr) end
      end

      if cairo_restore then cairo_restore(cr) end
    end


    -- Markers (filled IN / hollow OUT) per arc
    do
      local cfg_in   = mk.in_filled or {}
      local cfg_out  = mk.out_hollow or {}
      local base_in  = cfg_in.color or { 0.95, 0.26, 0.21, 1.0 }
      local base_out = cfg_out.color or { 0.95, 0.26, 0.21, 1.0 }
      local rr_in    = tonumber(cfg_in.radius) or 12
      local rr_out   = tonumber(cfg_out.radius) or 12
      local sw_out   = tonumber(cfg_out.stroke) or 3
      local mcols    = tget(TP, "pf.marker_colors") or {}
      local order    = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }

      local function pick_color(key, fallback)
        local c = mcols[key]
        if type(c) == "table" then return c end
        return fallback
      end

      for _, key in ipairs(order) do
        local arc = arcs[key]
        if arc then
          local lsa = arc.left_start_a or left_start_a or sr
          local lea = arc.left_end_a or left_end_a or mid
          local rsa = arc.right_start_a or right_start_a or er
          local rea = arc.right_end_a or right_end_a or mid
          local rls = arc.raw_left_start or raw_left_start
          local rle = arc.raw_left_end or raw_left_end
          local rrs = arc.raw_right_start or raw_right_start
          local rre = arc.raw_right_end or raw_right_end

          local in_s = rls or lsa
          local in_e = rle or lea
          local out_s = rrs or rsa
          local out_e = rre or rea
          local out_ccw = (rrs ~= nil and rre ~= nil)
          local in_s_base = arc.base_raw_left_start or arc.raw_left_start or arc.base_left_start_a or arc.left_start_a
          local in_e_base = arc.base_raw_left_end or arc.raw_left_end or arc.base_left_end_a or arc.left_end_a
          local out_s_base = arc.base_raw_right_start or arc.raw_right_start or arc.base_right_start_a or arc.right_start_a
          local out_e_base = arc.base_raw_right_end or arc.raw_right_end or arc.base_right_end_a or arc.right_end_a
          local dls = arc.raw_left_start and arc.base_raw_left_start and (arc.raw_left_start - arc.base_raw_left_start) or arc.delta_left_start or 0
          local dle = arc.raw_left_end and arc.base_raw_left_end and (arc.raw_left_end - arc.base_raw_left_end) or arc.delta_left_end or 0
          local drs = arc.raw_right_start and arc.base_raw_right_start and (arc.raw_right_start - arc.base_raw_right_start) or arc.delta_right_start or 0
          local dre = arc.raw_right_end and arc.base_raw_right_end and (arc.raw_right_end - arc.base_raw_right_end) or arc.delta_right_end or 0

          local in_s_p, in_e_p = pad_with_mode(in_s_base, in_e_base, in_s, in_e, false, dls, dle)
          local out_s_p, out_e_p = pad_with_mode(out_s_base, out_e_base, out_s, out_e, out_ccw, drs, dre)

          local ti_arc     = lerp_cw(in_s_p, in_e_p, ema_in[key] or 0)
          local to_arc     = (out_ccw and lerp_ccw(out_s_p, out_e_p, ema_out[key] or 0))
                          or lerp_cw(out_s_p, out_e_p, ema_out[key] or 0)
          local xin, yin   = arc.cx + arc.R * math.cos(ti_arc), arc.cy - arc.R * math.sin(ti_arc)
          local xout, yout = arc.cx + arc.R * math.cos(to_arc), arc.cy - arc.R * math.sin(to_arc)
          local cin        = pick_color(key, base_in)
          local cout       = pick_color(key, base_out)

          -- IN (filled)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, cin[1], cin[2], cin[3], cin[4] or 1) end
          if cairo_arc then cairo_arc(cr, xin, yin, rr_in, 0, 2 * math.pi) end
          if cairo_fill then cairo_fill(cr) end

          -- OUT (hollow)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, cout[1], cout[2], cout[3], cout[4] or 1) end
          if cairo_set_line_width then cairo_set_line_width(cr, sw_out) end
          if cairo_arc then cairo_arc(cr, xout, yout, rr_out, 0, 2 * math.pi) end
          if cairo_stroke then cairo_stroke(cr) end
        end
      end
    end

    -- Static end labels
    do
      local L = tget(TP, "pf.labels")
      if type(L) == "table" then
        local fnt  = L.font or "DejaVu Sans"
        local fsz  = tonumber(L.size) or 12
        local col  = L.color or { 0.85, 0.85, 0.85, 1.0 }
        local dxL  = tonumber(L.dx_left) or tonumber(L.dx_in) or -18
        local dyL  = tonumber(L.dy_left) or tonumber(L.dy_in) or -14
        local dxR  = tonumber(L.dx_right) or tonumber(L.dx_out) or 10
        local dyR  = tonumber(L.dy_right) or tonumber(L.dy_out) or -14
        local txtL = L.text_in or "IN"
        local txtR = L.text_out or "OUT"
        local xL   = cx + Rwan * math.cos(sr); local yL = cy - Rwan * math.sin(sr)
        local xR   = cx + Rwan * math.cos(er); local yR = cy - Rwan * math.sin(er)
        if cairo_select_font_face then cairo_select_font_face(cr, fnt, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD) end
        if cairo_set_font_size then cairo_set_font_size(cr, fsz) end
        if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
        if cairo_move_to then cairo_move_to(cr, xL + dxL, yL + dyL) end
        if cairo_show_text then cairo_show_text(cr, txtL) end
        if cairo_move_to then cairo_move_to(cr, xR + dxR, yR + dyR) end
        if cairo_show_text then cairo_show_text(cr, txtR) end
        if cairo_stroke then cairo_stroke(cr) end
      end
    end

    -- Arc name labels (on the left arc, following the curve)
    do
      local AN = tget(TP, "pf.arc_names") or {}
      if AN.enabled ~= false then
        local font = AN.font or (fonts and fonts.mono) or "DejaVu Sans Mono"
        local size = tonumber(AN.size) or 14
        local color = AN.color or { 0.85, 0.85, 0.85, 1.0 }
        local alpha = tonumber(AN.alpha)
        local dx = tonumber(AN.dx) or 0
        local dy = tonumber(AN.dy) or 0
        local dx_right = tonumber(AN.dx_right) or 0
        local dy_right = tonumber(AN.dy_right) or 0
        local pos = tonumber(AN.pos) or 0.5
        local pos_right = tonumber(AN.pos_right) or pos
        local r_offset_right = tonumber(AN.r_offset_right)
        local right_enabled = (AN.right_enabled ~= false)
        local per = AN.per_arc or {}

        local order = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
        for _, key in ipairs(order) do
          local arc = arcs[key]
          local cfg = per[key]
          if arc and cfg and cfg.text then
            local adx = tonumber(cfg.dx) or dx
            local ady = tonumber(cfg.dy) or dy
            local acol = cfg.color or color
            local aalpha = tonumber(cfg.alpha) or alpha or (acol[4] or 1)
            local asize = tonumber(cfg.size) or size
            local apos = tonumber(cfg.pos) or pos
            local r_off = tonumber(cfg.r_offset) or tonumber(AN.r_offset) or 0
            local lsa = arc.left_start_a or left_start_a or sr
            local lea = arc.left_end_a or left_end_a or split_mid
            local a_mid = lerp_cw(lsa, lea, apos)
            local r_txt = arc.R + r_off
            draw_text_arc(cr, arc.cx + adx, arc.cy + ady, r_txt, a_mid, cfg.text, font, asize, acol, aalpha)

            if right_enabled and (arc.right_start_a and arc.right_end_a or (arc.raw_right_start and arc.raw_right_end) or (right_start_a and right_end_a)) then
              local apos_r = tonumber(cfg.pos_right) or pos_right
              local r_off_r = tonumber(cfg.r_offset_right) or r_offset_right or r_off
              local r_start = arc.raw_right_start or raw_right_start or arc.right_start_a or right_start_a
              local r_end = arc.raw_right_end or raw_right_end or arc.right_end_a or right_end_a
              local a_mid_r = lerp_ccw(r_start, r_end, apos_r)
              local r_txt_r = arc.R + r_off_r
              draw_text_arc(cr, arc.cx + adx + dx_right, arc.cy + ady + dy_right,
                r_txt_r, a_mid_r, cfg.text, font, asize, acol, aalpha)
            end
          end
        end
      end
    end

    -- Horizontal baseline
    if hline_enabled then
      local Llen    = tonumber(hline.length) or (Rwan * 1.2)
      local Wd      = tonumber(hline.width) or a_w
      local col     = hline.color or { 0.85, 0.85, 0.90, 0.9 }
      local cx_line = tonumber(hline.x) or cx
      local cy_line = tonumber(hline.y) or (cy + (tonumber(hline.dy) or 30))
      local x1      = cx_line - Llen / 2
      local x2      = cx_line + Llen / 2
      if cairo_set_line_cap then cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT) end
      if cairo_set_line_width then cairo_set_line_width(cr, Wd) end
      if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
      if cairo_move_to then cairo_move_to(cr, x1, cy_line) end
      if cairo_line_to then cairo_line_to(cr, x2, cy_line) end
      if cairo_stroke then cairo_stroke(cr) end
    end

    -- Centered ONLINE/OFFLINE label above the baseline (theme: pf.gateway_label)
    do
      local gl = tget(TP, "pf.gateway_label") or {}
      if hline_enabled and gl.enabled ~= false then
        -- pull gateway status from fetch data
        local D        = data or {}
        local onlineV  = tget(D, "gateway.gateway_online")
        local online   = (onlineV == "1") or (onlineV == 1) or (onlineV == true)

        local gate_status = _trim(sh(string.format("%q status", GATE_SCRIPT)))
        local state_raw = sh(string.format("cat %q", CACHE_DIR .. "/pfsense/ssh_state"))
        local st_tripped = tonumber(state_raw:match("tripped=(%d+)")) or 0
        local st_until = tonumber(state_raw:match("until=(%d+)")) or 0
        local st_last_ok = tonumber(state_raw:match("last_ok_ts=(%d+)")) or 0
        local st_last_fail = tonumber(state_raw:match("last_fail_ts=(%d+)")) or 0
        local trip_reason = nil
        local trip_left = nil
        if gate_status:match("^TRIPPED") then
          trip_reason = gate_status:match("reason=([^|]+)") or "UNKNOWN"
          trip_left = tonumber(gate_status:match("left=(%d+)")) or 0
          online = true
        end
        if gate_status:match("^OK") and st_tripped == 1 and st_until > 0 then
          local now_ts = os.time()
          local grace_window = (tonumber(tget(TP, "poll.medium")) or 10) * 2
          if now_ts >= st_until and (now_ts - st_until) < grace_window and st_last_ok < st_last_fail then
            online = true
          end
        end
        local trip_suffix = nil
        if trip_reason then
          trip_suffix = string.format("  SSH PAUSED - %s - %ss", trip_reason, trip_left)
        end

        -- choose text
        local text_ok  = gl.text_ok or "ONLINE"
        local text_bad = gl.text_bad or "OFFLINE"
        local label    = online and text_ok or text_bad

        -- choose color (explicit overrides, else theme good/bad)
        local col_ok   = (type(gl.color_ok) == "table" and gl.color_ok)
            or tget(TP, "colors.good")
            or { 0.35, 0.85, 0.40, 1.0 }

        local col_bad  = (type(gl.color_bad) == "table" and gl.color_bad)
            or tget(TP, "colors.bad")
            or { 1.00, 0.20, 0.20, 1.0 }

        local col      = online and col_ok or col_bad

        -- font/size/weight
        local weight   = (gl.weight == "bold") and "bold" or "regular"
        local font     = tget(TP, "fonts." .. weight) or tget(TP, "fonts.regular") or "DejaVu Sans"
        local fsz      = tonumber(gl.size) or 16

        -- recompute the same baseline geometry used above
        local hline    = tget(TP, "pf.hline") or {}
        local Llen     = tonumber(hline.length) or (Rwan * 1.2)
        local cx_line  = tonumber(hline.x) or cx
        local cy_line  = tonumber(hline.y) or (cy + (tonumber(hline.dy) or 30))
        local xmid     = cx_line
        local y_text   = cy_line - (tonumber(gl.dy) or 16) -- above the line

        -- measure to center
        local ext      = cairo_text_extents_t:create()
        if cairo_select_font_face then
          cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL,
            (weight == "bold") and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        if cairo_set_font_size then cairo_set_font_size(cr, fsz) end
        if cairo_text_extents then cairo_text_extents(cr, label, ext) end
        local tx = xmid - (ext.width / 2 + ext.x_bearing)

        if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
        if cairo_move_to then cairo_move_to(cr, tx, y_text) end
        if cairo_show_text then cairo_show_text(cr, label) end

        if trip_suffix then
          local sx = tx + (ext.x_bearing or 0) + (ext.width or 0)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col_bad[1], col_bad[2], col_bad[3], col_bad[4] or 1) end
          if cairo_move_to then cairo_move_to(cr, sx, y_text) end
          if cairo_show_text then cairo_show_text(cr, trip_suffix) end
        end
        if cairo_stroke then cairo_stroke(cr) end
      end
    end



    -- --- Info Line (under the baseline; no extents, uses baseline for position) ---
    if hline_enabled then
      local IL = tget(TP, "pf.infoline") or {}
      if IL.enabled ~= false then
        -- Position: start from LEFT end of the baseline, plus optional dx/dy
        local Llen    = tonumber(hline.length) or (Rwan * 1.2)
        local cx_line = tonumber(hline.x) or cx
        local cy_line = tonumber(hline.y) or (cy + (tonumber(hline.dy) or 30))
        local x0      = (cx_line - Llen / 2) + (tonumber(IL.dx) or 0)
        local y0      = cy_line + (tonumber(IL.dy) or 24)

        local fnt     = (tget(TP, "fonts.regular") or "DejaVu Sans")
        local fsz     = tonumber(IL.size) or 14
        local col_lbl = IL.label_color or { 0.70, 0.74, 0.78, 1.0 } -- gray
        local col_val = IL.value_color or { 0.95, 0.97, 0.99, 1.0 } -- white
        local sep     = IL.sep or "  |  "

        -- Move pen to start
        if cairo_select_font_face then
          cairo_select_font_face(cr, fnt, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        end
        if cairo_set_font_size then cairo_set_font_size(cr, fsz) end
        if cairo_move_to then cairo_move_to(cr, x0, y0) end

        -- Small helper that relies on cairo_show_text naturally advancing the pen
        local function seg(lbl, val)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col_lbl[1], col_lbl[2], col_lbl[3], col_lbl[4] or 1) end
          if cairo_show_text then cairo_show_text(cr, lbl) end
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col_val[1], col_val[2], col_val[3], col_val[4] or 1) end
          if cairo_show_text then cairo_show_text(cr, val) end
        end
        local function write_sep()
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col_lbl[1], col_lbl[2], col_lbl[3], col_lbl[4] or 1) end
          if cairo_show_text then cairo_show_text(cr, sep) end
        end

        -- Pull data from our cached fetch
        local D       = data or {}
        local version = tget(D, "system.version") or tget(D, "system.pf_version")
        local model   = tget(D, "system.hw_model") or tget(D, "system.model") or "?"
        local bios    = tget(D, "system.bios_version") or tget(D, "system.bios")

        -- If missing from the fetch script, try SSH-ing the pfSense host (cached 60s)
        if (not version or version == "?") or (not bios or bios == "?") then
          local v2, b2 = _pf_remote_version_and_bios()
          if (not version or version == "?") and v2 then version = v2 end
          if (not bios or bios == "?") and b2 then bios = b2 end
        end

        -- Normalize fields for display
        -- 1) VERSION: keep just the number (drop "-RELEASE", etc.)
        version = tostring(version or "?"):gsub("%-RELEASE.*$", "")

        -- 2) BIOS: keep only the semantic version with leading 'v' (e.g., "v0.9.3")
        do
          local b = tostring(bios or "?")
          local v = b:match("v%d+%.%d+%.%d+") or b:match("v%d+%.%d+")
          if v then
            bios = v
          else
            -- fallback: plain number like "0.9.3" if no leading 'v'
            bios = b:match("%d+%.%d+%.%d+") or b:match("%d+%.%d+") or b
          end
        end


        local uptime = tget(D, "system.uptime") or "?"


        -- Format uptime as D:HH:MM:SS (tries seconds first, then parses common strings)
        local function fmt_uptime_D_HH_MM_SS(raw)
          -- Prefer a seconds field if present
          local secs = tonumber(tget(D, "system.uptime_seconds"))
          if secs and secs >= 0 and secs < 315360000 then
            local d = math.floor(secs / 86400); secs = secs % 86400
            local h = math.floor(secs / 3600); secs = secs % 3600
            local m = math.floor(secs / 60); local s = math.floor(secs % 60)
            return string.format("%d:%02d:%02d:%02d", d, h, m, s)
          end
          -- Parse: uptime output with leading clock time ("9:36AM  up 86 days, 36 mins, ...")
          local s = tostring(raw)
          local d, h, m = s:match("up%s+(%d+)%s+days?,%s*(%d+):(%d+)")
          if d and h and m then
            return string.format("%d:%02d:%02d:%02d", tonumber(d), tonumber(h), tonumber(m), 0)
          end
          d, h, m = s:match("up%s+(%d+)%s+days?,%s*(%d+)%s+hrs?,%s*(%d+)%s+mins?")
          if d and h and m then
            return string.format("%d:%02d:%02d:%02d", tonumber(d), tonumber(h), tonumber(m), 0)
          end
          d, m = s:match("up%s+(%d+)%s+days?,%s*(%d+)%s+mins?")
          if d and m then
            return string.format("%d:%02d:%02d:%02d", tonumber(d), 0, tonumber(m), 0)
          end
          h, m = s:match("up%s+(%d+):(%d+)")
          if h and m then
            return string.format("0:%02d:%02d:%02d", tonumber(h), tonumber(m), 0)
          end
          h, m = s:match("up%s+(%d+)%s+hrs?,%s*(%d+)%s+mins?")
          if h and m then
            return string.format("0:%02d:%02d:%02d", tonumber(h), tonumber(m), 0)
          end
          m = s:match("up%s+(%d+)%s+mins?")
          if m then
            return string.format("0:%02d:%02d:%02d", 0, tonumber(m), 0)
          end
          -- Parse: "47 days, 16:30" (no seconds given)
          local d, h, m = tostring(raw):match("(%d+)%s+days?,%s*(%d+):(%d+)")
          if d and h and m then
            return string.format("%d:%02d:%02d:%02d", tonumber(d), tonumber(h), tonumber(m), 0)
          end
          -- Parse: "16:30" (hours:minutes only)
          local hh, mm = tostring(raw):match("(%d+):(%d+)")
          if hh and mm then
            return string.format("0:%02d:%02d:%02d", tonumber(hh), tonumber(mm), 0)
          end
          -- Fallback: show raw
          return tostring(raw)
        end
        local uptime_fmt = fmt_uptime_D_HH_MM_SS(uptime)

        -- Try to shorten CPU like "N5105 @ 2.00GHz"
        local chip, ghz = tostring(model):match("(%u[%w%-]+)%s*@%s*([%d%.]+%s*GHz)")
        local cpu_short = chip and ghz and (chip .. " @ " .. ghz) or tostring(model)

        -- Compose: SYSTEM / VERSION / CPU / BIOS / UPTIME
        seg("SYSTEM: ", "PFSENSE"); write_sep()
        seg("VERSION: ", tostring(version)); write_sep()
        seg("CPU: ", cpu_short); write_sep()
        seg("BIOS: ", tostring(bios)); write_sep()
        seg("UPTIME: ", uptime_fmt)


        if cairo_stroke then cairo_stroke(cr) end
      end
    end

    -- Totals table under the info line
    do
      local TT = tget(TP, "pf.totals_table")
      if TT and TT.enabled ~= false then
        local font = TT.font or (fonts and fonts.mono) or "DejaVu Sans Mono"
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

        local total_w = label_w + (#headers) * data_w
        local x0 = cx + dx - total_w / 2
        local y0 = cy + dy

        local function text_extents(txt, size)
          if cairo_select_font_face then
            cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
          end
          if cairo_set_font_size then cairo_set_font_size(cr, size) end
          if cairo_text_extents then
            local te = cairo_text_extents_t:create()
            cairo_text_extents(cr, txt, te)
            return te
          end
          return { width = size * 0.6 * #tostring(txt) }
        end

        local function draw_center(txt, x, y, size, col)
          local te = text_extents(txt, size)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
          if cairo_move_to then cairo_move_to(cr, x - (te.width or 0) / 2, y) end
          if cairo_show_text then cairo_show_text(cr, txt) end
        end

        local function draw_right(txt, x, y, size, col)
          local te = text_extents(txt, size)
          if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
          if cairo_move_to then cairo_move_to(cr, x - (te.width or 0), y) end
          if cairo_show_text then cairo_show_text(cr, txt) end
        end

        -- Header row
        for i, h in ipairs(headers) do
          local cxh = x0 + label_w + (i - 0.5) * data_w
          local cyh = y0 + head_h
          draw_center(h, cxh, cyh, size_h, col_h)
        end

        -- Bytes In row
        do
          local cy_row = y0 + head_h + row_gap + row_h
          draw_right(row_labels["in"] or "Bytes In", x0 + label_w - 6, cy_row, size_b, col_l)
          for i, key in ipairs(order) do
            local ifn = tget(TP, "ifaces." .. key)
            local val = ifn and iface_val(ifn, "ibytes") or 0
            local cxv = x0 + label_w + (i - 0.5) * data_w
            draw_center(fmt_bytes_iec(val), cxv, cy_row, size_b, col_v)
          end
        end

        -- Bytes Out row
        do
          local cy_row = y0 + head_h + row_gap + row_h + row_gap + row_h
          draw_right(row_labels["out"] or "Bytes Out", x0 + label_w - 6, cy_row, size_b, col_l)
          for i, key in ipairs(order) do
            local ifn = tget(TP, "ifaces." .. key)
            local val = ifn and iface_val(ifn, "obytes") or 0
            local cxv = x0 + label_w + (i - 0.5) * data_w
            draw_center(fmt_bytes_iec(val), cxv, cy_row, size_b, col_v)
          end
        end

        if cairo_stroke then cairo_stroke(cr) end
      end
    end

    -- Status block (pfBlockerNG + Pi-hole)
    do
      local SB = tget(TP, "pf.status_block")
      if SB and SB.enabled ~= false then
        local font = SB.font or (fonts and fonts.regular) or "DejaVu Sans"
        local size = tonumber(SB.size) or 14
        local col_l = SB.label_color or { 0.85, 0.85, 0.85, 1.0 }
        local col_v = SB.value_color or { 0.95, 0.97, 0.99, 1.0 }
        local field_sep = SB.field_sep or " | "
        local dx = tonumber(SB.dx) or 0
        local dy = tonumber(SB.dy) or 0
        local line_gap = tonumber(SB.line_gap) or 18

        local D = data or {}
        local pfb_cfg = SB.pfb or {}
        local ph_cfg = SB.pihole or {}

        if cairo_select_font_face then
          cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        end
        if cairo_set_font_size then cairo_set_font_size(cr, size) end

        local function draw_segments(y, segments)
          local full = ""
          for _, seg in ipairs(segments) do full = full .. seg[1] end

          local te = cairo_text_extents_t:create()
          if cairo_text_extents then cairo_text_extents(cr, full, te) end
          local x0 = (cx + dx) - (te.width / 2 + te.x_bearing)
          if cairo_move_to then cairo_move_to(cr, x0, y) end

          for _, seg in ipairs(segments) do
            local txt, col = seg[1], seg[2]
            if cairo_set_source_rgba then cairo_set_source_rgba(cr, col[1], col[2], col[3], col[4] or 1) end
            if cairo_show_text then cairo_show_text(cr, txt) end
          end
          if cairo_stroke then cairo_stroke(cr) end
        end

        local y1 = cy + dy
        local y2 = y1 + line_gap

        if pfb_cfg.enabled ~= false then
          local pfb_ip = tonumber(tget(D, "pfblockerng.pfb_ip_total")) or 0
          local pfb_dns = tonumber(tget(D, "pfblockerng.pfb_dnsbl_total")) or 0
          local resolver_total = tonumber(tget(D, "pfblockerng.resolver_total")) or 0
          local pfb_total = (resolver_total > 0) and resolver_total or (pfb_ip + pfb_dns)
          local pfb_dns_pct = tonumber(tget(D, "pfblockerng.pfb_dnsbl_pct")) or 0
          local pfb_dns_pct_str = string.format("%.2f%%", pfb_dns_pct)

          local segments = {
            { pfb_cfg.prefix or "pfBlockerNG:", col_l },
            { " ",                              col_l },
            { "IP ",                            col_l }, { fmt_int_commas(pfb_ip), col_v },
            { field_sep, col_l },
            { "DNSBL ",  col_l }, { fmt_int_commas(pfb_dns), col_v },
            { field_sep, col_l },
            { "Hits: ",  col_l }, { pfb_dns_pct_str, col_v },
          }
          if pfb_cfg.show_total ~= false then
            segments[#segments + 1] = { field_sep, col_l }
            segments[#segments + 1] = { "Total Queries ", col_l }
            segments[#segments + 1] = { fmt_int_commas(pfb_total), col_v }
          end

          draw_segments(y1, segments)
        end

        if ph_cfg.enabled ~= false then
          local active = tget(D, "pihole.pihole_active") or "0"
          local status = (active == "1" or active == 1 or active == true) and "Active" or "Offline"

          local win = tonumber(ph_cfg.load_window) or 15
          if win ~= 1 and win ~= 5 and win ~= 15 then win = 15 end
          local load_key = "pihole.pihole_load" .. tostring(win)
          local load_val = tonumber(tget(D, load_key)) or 0
          local load_str = string.format("%.1f", load_val)

          local total = tonumber(tget(D, "pihole.pihole_total")) or 0
          local blocked = tonumber(tget(D, "pihole.pihole_blocked")) or 0
          local domains = tonumber(tget(D, "pihole.pihole_domains")) or 0
          local pct = 0
          if total > 0 then pct = (blocked / total) * 100 end
          local pct_dec = tonumber(ph_cfg.decimals_pct) or 2
          local pct_str = string.format("%." .. tostring(pct_dec) .. "f", pct)

          local segments = {
            { ph_cfg.prefix or "Pi-hole:", col_l },
            { " ",                         col_l },
            { status,                      col_v },
            { field_sep,                   col_l },
            { ("L%d: "):format(win),       col_l }, { load_str, col_v },
            { field_sep, col_l },
            { "Total: ", col_l }, { fmt_int_commas(total), col_v },
            { field_sep,   col_l },
            { "Blocked: ", col_l }, { fmt_int_commas(blocked), col_v },
            { field_sep,      col_l },
            { pct_str .. "%", col_v },
            { field_sep,      col_l },
            { "Domains: ",    col_l }, { fmt_int_commas(domains), col_v },
          }

          draw_segments(y2, segments)
        end
      end
    end
  end

  if cairo_destroy then cairo_destroy(cr) end
  if cairo_surface_destroy then cairo_surface_destroy(cs) end
end
