--[[
  ${CONKY_SUITE_DIR}/theme-sitrep.lua
  SITREP widget theme configuration

  This table is read by lua/widgets/sitrep.lua via SITREP_THEME.

  It provides:
    • Typography and base colors
    • SITREP layout and content configuration
    • Optional pfSense/infra metadata for the SITREP widget
]]

----------------------------------------------------------------
-- Shared Theme Core
----------------------------------------------------------------
local theme_core = dofile(os.getenv("CONKY_SUITE_DIR") .. "/lua/lib/theme-core.lua")
local palette = theme_core.palette
local fonts = theme_core.fonts

local T = {}

----------------------------------------------------------------
-- Colors
----------------------------------------------------------------
T.palette = palette

----------------------------------------------------------------
-- Fonts
----------------------------------------------------------------
T.fonts = fonts

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
-- SITREP Status Panel
----------------------------------------------------------------
T.sitrep = {
  width            = 460,                  -- panel width
  line_h           = 20,                   -- line spacing
  content_offset_x = 25,                   -- x offset for content (excludes panel)
  content_offset_y = 0,                    -- y offset for content (excludes panel)

  title_size       = 24,                   -- title font size
  title_text       = "SITREP",             -- title text
  title_alpha      = 1.00,                 -- title alpha
  title_x          = 10,                   -- title x position (rotated)
  title_y          = 50,                   -- title y position (rotated)

  title_font       = fonts.value_mono,     -- sitrep title font
  text_font        = fonts.value_mono,     -- sitrep text font
  text_size        = 18,                   -- body font size

  color_title      = { 0.00, 0.00, 0.00 }, -- title color (RGB)
  label_color      = { 0.00, 0.00, 0.00 }, -- label color (RGB)
  label_alpha      = 1.00,                 -- label alpha
  color_text       = { 1.00, 1.00, 1.00 }, -- fallback text color (RGB)
  value_color      = { 1.00, 1.00, 1.00 }, -- value color (RGB)
  value_alpha      = 1.00,                 -- value alpha

  panel            = {
    enabled            = true,                 -- draw the background panel
    offset_x           = 20,                   -- x offset from window origin
    offset_y           = 20,                   -- y offset from window origin
    width              = 560,                  -- override panel width (nil = window width - padding)
    height             = 700,                  -- override panel height (nil = window height - padding)
    padding_x          = 10,                   -- padding from window edge (when width is nil)
    padding_y          = 8,                    -- padding from window edge (when height is nil)
    radius             = 12,                   -- corner radius (px)
    stroke_width       = 4.0,                  -- panel stroke width
    fill_color         = { 0.30, 0.30, 0.30 }, -- panel fill color (RGB)
    fill_alpha         = 0.45,                 -- panel fill alpha
    season_tint_enable = true,                 -- blend fill color with current season tint
    season_tint_amount = 0.44,                 -- tint blend amount (0.0-1.0)
    stroke_color       = { 0.20, 0.20, 0.20 }, -- panel stroke color (RGB)
    stroke_alpha       = 0.90,                 -- panel stroke alpha
    outer_stroke       = {
      enabled = true,                          -- draw outer stroke
      offset  = 10,                            -- px outside panel
      width   = 8.0,                           -- outer stroke width
      color   = { 1.00, 1.00, 1.00 },          -- nil = stroke_color
      alpha   = 0.30,                          -- nil = stroke_alpha
    },
  },

  ap               = {
    enabled         = true,                 -- toggle AP block (disables polling when false)
    font            = fonts.value_mono,     -- device title font
    size            = 20,                   -- AP font size
    color           = { 1.00, 1.00, 1.00 }, -- AP color (RGB)
    alpha           = 1.00,                 -- AP alpha
    name_color      = { 0.00, 0.00, 0.00 }, -- AP name color (RGB)
    name_alpha      = 1.00,                 -- AP name alpha
    value_x         = 540,                  -- right edge for CPU/CONN/UNKWN (px)
    device_font     = fonts.value_mono,     -- device label font
    device_size     = 15,                   -- device font size
    device_color    = { 1.00, 1.00, 1.00 }, -- device color (RGB)
    device_alpha    = 1.00,                 -- device alpha
    device_line_h   = 17,                   -- device line height (px)
    unk_value_color = { 1.00, 0.62, 0.00 }, -- UNKWN value color (RGB)
    unk_value_alpha = 1.00,                 -- UNKWN value alpha
    unk_ip_color    = { 1.00, 0.62, 0.00 }, -- unknown IP color (RGB)
    unk_ip_alpha    = 1.00,                 -- unknown IP alpha
    device_max_w    = 512,                  -- max width for device line (px)
    device_center_x = 280,                  -- device center x (px)
    device_align    = "left",               -- "center" or "left"
    device_left_x   = 30,                   -- left x (nil = padding)
  },

  pfsense          = {
    enabled              = true,    -- toggle pfSense block (disables polling when false)
    version              = "--",    -- pfSense version text
    cpu                  = "N5105", -- pfSense CPU model text
    bios                 = "0.9.3", -- pfSense BIOS version text
    follow_flow          = false,   -- keep pfSense text pinned to text_y
    text_y               = 410,     -- fixed y for pfSense text when follow_flow=false
    text_center_x        = 274,     -- center x for top pfSense lines
    text_center_offset_x = 0,       -- x offset for centered lines
  },


  hr = {
    length              = 530,                  -- HR length
    stroke              = 1.0,                  -- HR stroke width
    color               = { 1.00, 1.00, 1.00 }, -- HR color (RGB)
    alpha               = 1.00,                 -- HR alpha
    header_line_y       = 60,                   -- HR y position (header)
    ap_line_y           = 475,                  -- HR y position (AP block)
    pfsense_line_y      = 700,                  -- HR y position (pfSense block, fixed)
    pfsense_line_follow = false,                -- follow pfSense text flow
    pfsense_line_offset = 0,                    -- extra y offset when follow is enabled
  },
}


----------------------------------------------------------------
-- pfSense arc + marker theme (geometry + appearance)
----------------------------------------------------------------
T.pf = T.pf or {}

----------------------------------------------------------------
-- pfSense load (window/cores)
----------------------------------------------------------------
T.pf.load = {
  window = 5,      -- 1 | 5 | 15
  cores  = "auto", -- "auto" or number
}


----------------------------------------------------------------
-- Gateway status label (ONLINE / OFFLINE) – centered above baseline
----------------------------------------------------------------
T.pf.gateway_label = {
  enabled   = true,      -- master toggle
  size      = 16,        -- font size (px)
  dy        = 0,         -- pixels ABOVE the baseline (increase to move up)
  weight    = "regular", -- "regular" | "bold"
  dx        = 0,         -- horizontal offset from right edge (px)

  -- Text for states
  text_ok   = "ONLINE",
  text_bad  = "OFFLINE",

  -- Optional explicit colors. If nil, widget falls back to T.colors.good/bad.
  -- Example to force gray for ONLINE:
  color_ok  = { 1.00, 1.00, 1.00, 1.00 },
  -- color_ok  = nil,
  color_bad = { 0.40, 0.08, 0.12 },
}


----------------------------------------------------------------
-- Totals table (cumulative bytes per interface)
----------------------------------------------------------------
T.pf.totals_table = {
  enabled      = true,
  dx           = -44,
  dy           = 0,
  font         = fonts.value_mono,
  size_header  = 15,
  size_body    = 14,
  color_header = { 0.00, 0.00, 0.00, 1.0 }, -- darkgray
  color_label  = { 0.00, 0.00, 0.00, 1.0 }, -- gray49
  color_value  = { 0.95, 0.97, 0.99, 1.0 }, -- AliceBlue (White)

  label_col_w  = 120,
  data_col_w   = 85,
  header_h     = 20,
  row_h        = 18,
  row_gap      = 4,

  headers      = { "WAN", "HOME", "IoT", "GUEST", "INFRA", "CAM" },
  row_labels   = { ["in"] = "DN", ["out"] = "UP" },
}

----------------------------------------------------------------
-- Status block (pfBlockerNG + Pi-hole)
----------------------------------------------------------------
T.pf.status_block = {
  enabled     = true,
  dx          = 0,
  dy          = 100,
  line_gap    = 20,
  font        = fonts.value_mono,
  size        = 17,
  label_color = { 0.00, 0.00, 0.00, 1.0 }, -- gray49
  value_color = { 0.95, 0.97, 0.99, 1.0 }, -- AliceBlue (White)
  field_sep   = " | ",

  pfb         = {
    enabled    = true,
    prefix     = "pfBlockerNG:",
    show_total = true,
  },

  pihole      = {
    enabled      = true,
    prefix       = "Pi-hole:",
    host         = "pi5",
    load_window  = 15,
    decimals_pct = 2,
  },
}

----------------------------------------------------------------
-- Debug & development options
----------------------------------------------------------------
T.pf.debug = {
  show_center = false, -- draw a tiny cross at the arc center
  text_block  = false, -- show old five-line reader text + DBG line (off by default)
}

----------------------------------------------------------------
-- Return table consumed by pf_widget.lua
----------------------------------------------------------------
return T
