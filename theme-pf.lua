local T = {}

----------------------------------------------------------------
-- Shared Theme Core
----------------------------------------------------------------
local theme_core = dofile(os.getenv("CONKY_SUITE_DIR") .. "/lua/lib/theme-core.lua")
local palette = theme_core.palette
local fonts = theme_core.fonts

----------------------------------------------------------------
-- Typography & basic colors
----------------------------------------------------------------
T.fonts = {
  regular = fonts.value_c,
  mono    = fonts.value_mono,
  bold    = fonts.title_b,
}

T.sizes = {
  title     = 20,
  label     = 14,
  value     = 16,
  arc_thick = 6,
}

T.colors = {
  bg      = palette.pfsense.bg,      -- gray7 (palette pfsense bg)
  text    = palette.pfsense.text,    -- lavender (palette pfsense text)
  accent  = palette.pfsense.accent,  -- headers/markers red (palette pfsense accent)
  good    = palette.pfsense.good,    -- online/ok MediumSeaGreen (palette pfsense good)
  warn    = palette.pfsense.warn,    -- caution goldenrod1 (palette pfsense warn)
  bad     = palette.pfsense.bad,     -- offline/error tomato2 (palette pfsense bad)
  arc_in  = palette.pfsense.arc_in,  -- inbound arcs SteelBlue1 (palette pfsense arc_in)
  arc_out = palette.pfsense.arc_out, -- outbound arcs sienna1 (palette pfsense arc_out)
}

----------------------------------------------------------------
-- Refresh cadence
----------------------------------------------------------------
T.poll = {
  fast   = 1,  -- CPU/MEM, interface rates
  medium = 60, -- bytes totals, gateway
  slow   = 90, -- pfBlockerNG counts
}

----------------------------------------------------------------
-- pfSense host & interface map
----------------------------------------------------------------
T.host = os.getenv("PFSENSE_HOST") or "192.168.1.1"

T.ifaces = {
  CAM   = "igc1.50",
  INFRA = "igc1.40",
  HOME  = "igc1.10",
  IOT   = "igc1.20",
  GUEST = "igc1.30",
  WAN   = "igc0",
}

----------------------------------------------------------------
-- Link speeds (Mbps) for normalization
----------------------------------------------------------------
T.link_mbps = {
  CAM   = 700,
  INFRA = 700,
  HOME  = 700,
  IOT   = 700,
  GUEST = 700,
  WAN   = 700,
}

----------------------------------------------------------------
-- Optional: separate link caps for normalization (IN vs OUT)
-- If present, the widget will prefer these over T.link_mbps.*
----------------------------------------------------------------
T.link_mbps_in = {
  WAN   = 500, -- Per tests (~589 Mbps down), make 100% ≈ 700 Mbps headroom
  CAM   = 100,
  INFRA = 100,
  HOME  = 100,
  IOT   = 100,
  GUEST = 50,
}

T.link_mbps_out = {
  WAN   = 50, -- ~50 Mbps is a sensible cap
  CAM   = 100,
  INFRA = 100,
  HOME  = 100,
  IOT   = 100,
  GUEST = 100,
}


----------------------------------------------------------------
-- Scaling & floors (visual response curve)
-- mode: "linear" | "log" | "sqrt"
----------------------------------------------------------------
T.scale = {
  mode = "sqrt",

  log = {
    base     = 4.0,
    min_norm = 0.0008,
  },

  sqrt = {
    gamma = 0.35, --0.25-0.4:very sensitive, 0.45-0.6:balanced, 0.7-0.8:conservative
  },

  -- Per-interface floors (Mbps) to avoid tiny idle wiggles
  floors_mbps = {
    CAM   = 0,
    INFRA = 0,
    HOME  = 0,
    IOT   = 0,
    GUEST = 0,
    WAN   = 0,
  },

  -- Clamp after scaling (0..1)
  clamp_pct = { min = 0.0, max = 1.0 },
}

----------------------------------------------------------------
-- pfSense arc + marker theme (geometry + appearance)
----------------------------------------------------------------
T.pf = {
  arc = {
    dx              = 0,                          -- offset from chosen center (code uses cx+dx, cy+dy)
    dy              = 0,
    r               = 710,                        -- radius (px)
    start           = 180,                        -- left end (deg)
    ["end"]         = 0,                          -- right end (deg)
    split_angle_deg = 90,                         -- split angle (deg) when using start/end
    split_gap_deg   = 0,                          -- gap at split (deg)
    left_start      = 210,                        -- optional override (deg): left arc start
    left_end        = 150,                        -- optional override (deg): left arc end
    right_start     = 330,                        -- optional override (deg): right arc start
    right_end       = 30,                         -- optional override (deg): right arc end
    color           = { 0.80, 0.80, 0.80, 0.20 }, -- base arc stroke   gray6
    width           = 2,                          -- arc stroke width
  },

  -- Concentric arc spacing (centerline to centerline)
  deltaR = 30,

  -- 0.0 = concentric, 1.0 = apex-anchored
  anchor_strength = 0,

  -- Per-arc overrides (degrees)
  arcs = {
    WAN   = { start_offset = -1, end_offset = 1.2 },
    HOME  = { start_offset = -3, end_offset = 2.4 },
    IOT   = { start_offset = -3.2, end_offset = 3.2 },
    GUEST = { start_offset = -3, end_offset = 3 },
    INFRA = { start_offset = -2, end_offset = 2.2 },
    CAM   = { start_offset = -1, end_offset = .2 },
  },

  -- Markers (left IN = filled; right OUT = hollow)
  markers = {
    in_filled     = {
      color  = { 0.40, 0.08, 0.12 }, -- maroon fill
      radius = 8,
    },
    out_hollow    = {
      color  = { 0.40, 0.08, 0.12 }, -- maroon outline
      radius = 8,
      stroke = 3,
    },
    pad_start_deg = 1,       -- degrees of padding at arc start (marker/trail)
    pad_end_deg   = 1,       -- degrees of padding at arc end (marker/trail)
    pad_mode      = "after", -- "after" (default) or "before" arc offsets
  },

  -- Per-arc marker colors (WAN inherits markers.* by default)
  marker_colors = {
    HOME  = { 0.60, 0.60, 0.60, 1.0 }, -- #999999
    IOT   = { 0.45, 0.45, 0.45, 1.0 }, -- #666666
    GUEST = { 0.25, 0.25, 0.25, 1.0 }, -- #404040
    INFRA = { 0.80, 0.80, 0.80, 1.0 }, -- #FFFFFF
    CAM   = { 0.65, 0.65, 0.65, 1.0 }, -- #BFBFBF
  },
}

----------------------------------------------------------------
-- Arc layout (centered clock, left/right arcs)
----------------------------------------------------------------
T.pf_alt = {
  enabled         = false,
  radius          = 370, -- base radius (px) for WAN arc
  stroke          = 10,  -- arc stroke width
  gap             = 8,   -- gap between arc bands
  left_start_deg  = 225, -- 7:30 (bottom)
  left_end_deg    = 135, -- 10:30 (top)
  right_start_deg = 315, -- 4:30 (bottom)
  right_end_deg   = 45,  -- 1:30 (top)

  arc_alpha       = 0.90,
  in_color        = (T.colors and T.colors.arc_in) or { 0.35, 0.75, 1.00, 1.0 },
  out_color       = (T.colors and T.colors.arc_out) or { 1.00, 0.55, 0.25, 1.0 },

  marker_radius   = 6,
  marker_stroke   = 2,

  label_font      = (T.fonts and T.fonts.bold) or "Inter Bold",
  label_size      = 12,
  label_color     = (T.colors and T.colors.text) or { 0.10, 0.10, 0.10 },
  label_alpha     = 0.75,
  label_offset    = -20, -- offset from arc radius (px, inward)
}

----------------------------------------------------------------
-- Arc name labels (dash leader + name at left endpoints)
----------------------------------------------------------------
T.pf.arc_names = {
  enabled        = true,
  right_enabled  = true,
  dx             = 0,
  dy             = 0,
  dx_right       = 0,
  dy_right       = 0,
  font           = "Eurostile LT Std Ext Two",
  size           = 14,
  color          = { 0.20, 0.20, 0.20 },
  alpha          = 1.00,
  pos_right      = 0.5,
  r_offset_right = 0,

  per_arc        = {
    WAN   = { text = "WAN" },
    HOME  = { text = "HOME" },
    IOT   = { text = "IoT" },
    GUEST = { text = "GUEST" },
    INFRA = { text = "INFRA" },
    CAM   = { text = "CAM" },
  },
}

----------------------------------------------------------------
-- Smoothing (EMA) for rates
----------------------------------------------------------------
T.pf.smoothing = {
  alpha = 0.35, -- higher = snappier, lower = smoother (0.15–0.45 is a nice range)
}

----------------------------------------------------------------
-- Return table consumed by pf_widget.lua
----------------------------------------------------------------
return T
