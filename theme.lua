--[[
  ${CONKY_SUITE_DIR}/theme.lua
  Centralized Conky theme configuration

  This table is required by all Conky widgets via:
      local theme = dofile(os.getenv("CONKY_SUITE_DIR") .. "/theme.lua")

  It provides:
    • Typography and base colors
    • Shared layout helpers

  Most widgets should only need to read values from here; layout tweaks
  happen in this file rather than in each individual .conky.conf.
]]

----------------------------------------------------------------
-- Shared Theme Core
----------------------------------------------------------------
local theme_core = dofile(os.getenv("CONKY_SUITE_DIR") .. "/lua/lib/theme-core.lua")
local palette = theme_core.palette
local fonts = theme_core.fonts
local font_profiles = theme_core.font_profiles
local pick_font = theme_core.pick_font

----------------------------------------------------------------
-- Main Section
----------------------------------------------------------------
-- Monitor Selection and Suite Scale
local t = {
  monitor_head = 0, -- 0 = primary, 1 = secondary
  scale = 1.00,     -- draw scale used by util.scale() for widget rendering (text/lines/shapes)

  -- Layout scale vs draw scale:
  -- - layout.scale drives layout_pos/layout_dim (window positions/sizes).
  -- - theme.scale drives util.scale() for drawn elements (text/lines/shapes).
  -- - When layout.tie_draw_scale=true, layout.scale sets theme.scale to keep both in sync.
  -- - Use scale_mode="auto" to compute layout.scale from CONKY_SCREEN_W/H; use "manual" for a fixed value.
  -- - If you want positions to change but drawing to stay fixed, set tie_draw_scale=false and adjust theme.scale separately.

  -- Layout (positions scale separately from draw scale)
  layout = {
    base_width = 3840,     -- design width for positions below
    base_height = 2160,    -- design height for positions below
    scale_mode = "manual", -- "manual" or "auto" (uses CONKY_SCREEN_W/H)
    scale = 1.00,          -- layout scale when mode="manual"
    tie_draw_scale = true, -- when true, sets theme.scale from layout scale
    positions = {
      time = { x = 0, y = 0 },
      pfsense = { x = 0, y = 0 },
      sitrep = { x = 10, y = 517 },
      system = { x = 810, y = 288 },
      station_model = { x = 810, y = 865 },
      network = { x = 1542, y = 288 },
      baro_gauge = { x = 1542, y = 865 },
      notes = { anchor = "clock_center", anchor_point = "top_right", anchor_scale = false, x = -1110, y = -700 },
      doctor = { x = 260, y = 420 },
      music = { anchor = "clock_center", anchor_point = "top_left", anchor_scale = false, x = 40, y = -700 },
      font_probe = { x = 30, y = 30 },
    },
    inverse_positions = {},
    position_fit = {},
    sizes = {
      time = { min_w = 1200, max_w = 1200, min_h = 1200 },
      pfsense = { min_w = 1200, max_w = 1200, min_h = 1200 },
      sitrep = { min_w = 460, max_w = 560, min_h = 800 },
      system = { min_w = 400, max_w = 400, min_h = 400 },
      station_model = { min_w = 400, max_w = 400, min_h = 400 },
      network = { min_w = 400, max_w = 400, min_h = 400 },
      baro_gauge = { min_w = 400, max_w = 400, min_h = 400 },
      notes = { min_w = 360, max_w = 360, min_h = 700 },
      doctor = { min_w = 520, max_w = 520, min_h = 600 },
      music = { min_w = 560, max_w = 560, min_h = 1100 },
      font_probe = { min_w = 2400, max_w = 2400, min_h = 1400 },
    },
  },

  -- Embedded corner widgets (draw inside time widget)
  embedded_corners = {
    enabled = true,
    margin = 0,
    system = { enabled = true, anchor = "top_left", x = -110, y = 0 },
    network = { enabled = true, anchor = "top_right", x = 110, y = 0 },
    station_model = { enabled = true, anchor = "bottom_left", x = -110, y = 0 },
    baro_gauge = { enabled = true, anchor = "bottom_right", x = 110, y = 0 },
  },

  -- Colors
  palette = palette,

  -- Fonts
  fonts = fonts,
  font_profiles = font_profiles,

  ----------------------------------------------------------------
  -- Clock
  ----------------------------------------------------------------

  -- Clock Size and Custom Functions
  clock_r_factor = 0.135,      -- size of the clock
  clock_show_numbers = true,   -- toggle clock face numbers
  clock_rotate_numbers = true, -- to look like a wall clock set to false

  -- Clock 24h bezel geometry + rotation
  clock_bezel_auto = true,      -- auto pulls data from OWM cache timezone_offset
  clock_bezel_utc_offset = -6,  -- manual fallback/override when auto=false or cache missing
  clock_bezel_r_offset = 60,    -- offset from clock radius to 24h bezel ring
  clock_bezel_seg_thick = 24.0, -- 24h bezel segment stroke thickness
  clock_bezel_seg_gap = -5,     -- 24h bezel segment gap (px along arc)

  -- Clock 24h bezel text + outer ring styling
  clock_bezel_font = "auto",                    -- "auto" = fonts.accent_black
  clock_bezel_font_size = 15,                   -- 24h bezel number font size
  clock_bezel_font_color = palette.black,       -- 24h bezel number color
  clock_bezel_font_alpha = 0.95,                -- 24h bezel number alpha
  clock_bezel_outer_ring_offset = 8,            -- outer ring offset beyond bezel
  clock_bezel_outer_ring_width = 6.0,           -- outer ring stroke width
  clock_bezel_outer_ring_alpha = 1.00,          -- outer ring alpha
  clock_bezel_outer_ring_color = palette.black, -- outer ring color
  clock_bezel_marker_color = palette.white,     -- 0/24 triangle marker color
  clock_bezel_marker_alpha = 0.65,              -- 0/24 triangle marker alpha

  -- Clock Digital Time
  clock_tz_label = "CST",                    -- manual label when auto=false
  clock_time_fixed_spacing = false,          -- use fixed digit spacing for time
  clock_local_time_size = 26,                -- local time font size
  clock_local_time_color = palette.gray.g20, -- local time color
  clock_local_time_alpha = 0.90,             -- local time alpha
  clock_local_time_y_factor = -0.55,         -- local time vertical factor
  clock_utc_time_size = 22,                  -- UTC time font size
  clock_utc_time_color = palette.gray.g70,   -- UTC time color
  clock_utc_time_alpha = 0.50,               -- UTC time alpha
  clock_utc_time_y_factor = 0.55,            -- UTC time vertical factor
  clock_tz_label_size = 17,                  -- timezone label font size
  clock_tz_label_color = palette.black,      -- timezone label color
  clock_tz_label_alpha = 0.50,               -- timezone label alpha
  clock_tz_label_y_offset = 24,              -- timezone label y offset

  -- Clock Face Numbers
  clock_numbers_font = fonts.value_c,  -- clock face numbers font
  clock_numbers_weight = "normal",     -- "normal" or "bold"
  clock_numbers_size = 24,             -- clock face numbers size
  clock_numbers_color = palette.white, -- clock face numbers color
  clock_numbers_alpha = 0.65,          -- clock face numbers alpha
  clock_numbers_r_factor = 0.86,       -- clock face numbers radius factor

  -- Clock Date Window
  clock_date_window_enabled = true,              -- toggle date window
  clock_date_window_box_size = 36,               -- date window box size
  clock_date_window_r_offset = -48,              -- date window radial offset from numbers
  clock_date_window_font = "auto",               -- "auto" = fonts.value
  clock_date_window_font_size = 16,              -- date window font size
  clock_date_window_bg_color = palette.gray.g70, -- date window background color
  clock_date_window_bg_alpha = .10,              -- date window background alpha
  clock_date_window_text_color = palette.white,  -- date window text color
  clock_date_window_text_alpha = .40,            -- date window text alpha

  -- Clock Ticks
  clock_minute_tick_len = 8,                  -- minute tick length
  clock_minute_tick_width = 4.0,              -- minute tick width
  clock_minute_tick_color = palette.gray.g20, -- minute tick color
  clock_minute_tick_alpha = 0.95,             -- minute tick alpha
  clock_hour_tick_len = 30,                   -- maroon hour tick length
  clock_hour_tick_width = 5.0,                -- maroon hour tick width
  clock_hour_tick_r_offset = 4,               -- maroon hour tick radial offset
  clock_struct_color = palette.gray.g10,      -- clock ring color
  clock_struct_alpha = 0.60,                  -- clock ring alpha

  -- Clock Hour Hand
  clock_hand_hour_len_factor = 0.72,        -- hour hand length factor
  clock_hand_hour_width = 9.5,              -- hour hand width
  clock_hand_hour_color = palette.gray.g10, -- hour hand color
  clock_hand_hour_alpha = 0.70,             -- hour hand alpha
  clock_hand_hour_arrow_len = 22,           -- hour hand arrow length
  clock_hand_hour_arrow_width = 24,         -- hour hand arrow width

  -- Clock Minute Hand
  clock_hand_minute_len_factor = 0.94,        -- minute hand length factor
  clock_hand_minute_width = 7.5,              -- minute hand width
  clock_hand_minute_color = palette.gray.g10, -- minute hand color
  clock_hand_minute_alpha = 0.75,             -- minute hand alpha
  clock_hand_minute_arrow_len = 22,           -- minute hand arrow length
  clock_hand_minute_arrow_width = 14,         -- minute hand arrow width

  -- Clock Second Hand
  clock_hand_second_len_factor = 0.93,     -- second hand length factor
  clock_hand_second_width = 2.5,           -- second hand width
  clock_hand_second_color = palette.white, -- second hand color
  clock_hand_second_alpha = 0.50,          -- second hand alpha
  clock_hand_second_arrow_len = 14,        -- second hand arrow length
  clock_hand_second_arrow_width = 12,      -- second hand arrow width

  -- Clock GMT Hand
  clock_hand_gmt_len_factor = 1.19,        -- GMT hand length factor
  clock_hand_gmt_width = 4.0,              -- GMT hand width
  clock_hand_gmt_color = palette.gray.g10, -- GMT hand color
  clock_hand_gmt_alpha = 1.00,             -- GMT hand alpha
  clock_hand_gmt_arrow_len = 16,           -- GMT hand arrow length
  clock_hand_gmt_arrow_width = 16,         -- GMT hand arrow width
  clock_hand_gmt_inner_offset = 233,       -- GMT hand start offset from center (px)

  ----------------------------------------------------------------
  -- Volvelle Ring (Celestial Glyph Ring)
  ----------------------------------------------------------------
  volvelle = {
    -- Ring geometry
    r_offset          = 110,  -- offset from clock radius
    stroke            = 42.0, -- ring stroke width
    gap_px            = 6,    -- gap size at 3 and 9 o'clock
    pad_deg           = 2,    -- minimum angular spacing between glyphs

    -- Debug/testing
    debug_mode        = false,        -- enable debug overrides
    debug_theta       = { ALL = 45 }, -- per-body override degrees when debug_mode=true (e.g. SUN=0)

    -- Ring styling
    color             = palette.black,                                      -- ring color (palette black)
    alpha             = 0.60,                                               -- ring alpha
    glyph_set         = "astronomicon",                                     -- "astronomicon" or "unicode"
    font              = "auto",                                             -- "auto" = font_* based on glyph_set
    font_astronomicon = pick_font({ "Astronomicon" }, "Astronomicon"),      -- glyph font family
    font_unicode      = pick_font({ "Symbola", "DejaVu Sans" }, "Symbola"), -- glyph font family (unicode)

    -- Glyph defaults
    glyph_pt          = 30,            -- default glyph point size
    glyph_color       = palette.white, -- default glyph color (palette white)
    glyph_alpha       = 0.99,          -- default glyph alpha

    -- Planet rendering
    planet_render     = "glyphs", -- "glyphs" or "circles" (planets only)

    -- Per-body glyph overrides
    glyphs            = {
      SUN = {
        pt      = 28,            -- glyph size override
        color   = palette.white, -- glyph color override (palette accent orange)
        alpha   = 0.95,          -- glyph alpha override
        dr      = 3,             -- radial offset from ring
        rot_deg = 0,             -- extra rotation (degrees)
      },
      MOON = {
        pt      = 26,               -- glyph size override
        color   = palette.gray.g90, -- glyph color override (palette gray g90)
        alpha   = 0.99,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
      MERCURY = {
        pt      = 24,               -- glyph size override
        color   = palette.gray.g60, -- glyph color override (palette gray g60)
        alpha   = 0.79,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
      VENUS = {
        pt      = 24,               -- glyph size override
        color   = palette.gray.g80, -- glyph color override (palette gray g80)
        alpha   = 0.59,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
      MARS = {
        pt      = 24,               -- glyph size override
        color   = palette.gray.g75, -- glyph color override (palette gray g75)
        alpha   = 0.60,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
      JUPITER = {
        pt      = 24,               -- glyph size override
        color   = palette.gray.g85, -- glyph color override (palette gray g85)
        alpha   = 0.49,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
      SATURN = {
        pt      = 24,               -- glyph size override
        color   = palette.gray.g78, -- glyph color override (palette gray g78)
        alpha   = 0.59,             -- glyph alpha override
        dr      = 0,                -- radial offset from ring
        rot_deg = 0,                -- extra rotation (degrees)
      },
    },

    -- Planet circles (used when planet_render="circles")
    planet_circles    = {
      VENUS   = { r = 12, color = palette.planet.venus },   -- cream-yellow, bright (palette planet venus)
      MARS    = { r = 15, color = palette.planet.mars },    -- orange (palette planet mars)
      JUPITER = { r = 13, color = palette.planet.jupiter }, -- pale tan (palette planet jupiter)
      SATURN  = { r = 12, color = palette.planet.saturn },  -- pale gold (palette planet saturn)
      MERCURY = { r = 9, color = palette.planet.mercury },  -- gray-silver (palette planet mercury)
    },
  },

  ----------------------------------------------------------------
  -- Calendar Rings
  ----------------------------------------------------------------
  calendar = {

    -- Seasons Ring
    enabled            = true,             -- seasons ring
    stroke             = 46.0,             -- seasons ring stroke width
    gap_px             = 12,               -- gap between season segments
    r_offset           = 0,                -- extra radius offset (+out/-in)
    color              = palette.gray.g30, -- base ring color (palette gray g30)
    alpha              = 0.65,             -- base ring alpha
    season_tint_enable = true,             -- subtle per-season tint
    season_tint_amount = 0.08,             -- tint blend amount (0.0-1.0)
    -- Season names text
    font               = fonts.value_c,    -- season names font
    title_size         = 25,               -- season names text size
    title_alpha        = 0.00,             -- season names text alpha
    title_x_offset     = 0,                -- season names text x offset
    title_y_offset     = -10,              -- season names text y offset
    text_color         = palette.gray.g70, -- season text color (palette gray g70)
    text_alpha         = 0.40,             -- season text alpha
    text_size          = 24,               -- season text size
    text_r_offset      = -3,               -- pull text toward center (+out/-in)

    -- Daylight Savings Time Ring
    dst                = {
      enabled  = true,          -- daylight savings time arc
      stroke   = 8.0,           -- DST arc stroke width
      r_offset = 0,             -- extra radius offset (+out/-in)
      color    = palette.white, -- DST arc color (palette white)
      alpha    = 0.40,          -- DST arc alpha
    },

    -- Months Ring
    months             = {
      enabled            = true,             -- months ring
      stroke             = 56.0,             -- months ring stroke width
      gap_px             = 10,               -- gap between month segments
      r_offset           = -4,               -- extra radius offset (+out/-in)
      color              = palette.gray.g20, -- use volvelle ring color when set (palette gray g20)
      alpha              = 0.90,             -- use volvelle ring alpha when set
      font               = "auto",           -- "auto" = fonts.title
      text_color         = palette.gray.g70, -- month text color (palette gray g70)
      text_alpha         = 0.70,             -- month text alpha
      current_text_color = palette.white,    -- current month text color
      current_text_alpha = 0.70,             -- current month text alpha
      text_size          = 18,               -- month text size
      text_r_offset      = -2,               -- month text radial offset
    },

    -- Days Ring
    days               = {
      enabled       = true,             -- days ring
      rotate        = false,            -- rotate days ring with seasons/months
      ring_stroke   = 25.0,             -- days ring stroke width
      ring_gap_px   = 6,                -- days ring gap size
      ring_r_offset = -4,               -- extra radius offset (+out/-in)
      ring_color    = palette.white,    -- days ring color (palette white)
      ring_alpha    = 0.60,             -- days ring alpha
      tick_len      = 10,               -- day tick length
      tick_width    = 5.9,              -- day tick width
      tick_color    = palette.gray.g30, -- day tick color (palette gray g30)
      tick_alpha    = 0.50,             -- day tick alpha
      tick_r_offset = 5,                -- day tick radial offset
    },

    ----------------------------------------------------------------
    -- Date Strip (Month / Day / Year boxes above days ring)
    ----------------------------------------------------------------
    date_strip         = {
      enabled         = true,             -- toggle date strip
      r_offset        = 16,               -- offset beyond days ring outer edge

      gap             = 2,                -- gap between boxes
      box_h           = 26,               -- box height
      month_w         = 46,               -- month box width
      day_w           = 32,               -- day box width
      year_w          = 54,               -- year box width

      dow_enabled     = true,             -- toggle weekday box
      dow_gap         = 2,                -- gap above date strip
      dow_box_h       = 26,               -- weekday box height
      dow_box_w       = 125,              -- weekday box width

      font            = "auto",           -- "auto" = fonts.value_c
      text_size       = 16,               -- text size
      dow_text_size   = 16,               -- weekday text size
      text_color      = palette.gray.g90, -- text color (palette gray g90)
      text_alpha      = 0.95,             -- text alpha

      dow_box_color   = palette.gray.g21, -- weekday box color (palette gray g21)
      box_color_month = palette.gray.g20, -- month box color (palette gray g20)
      box_color_day   = palette.gray.g22, -- day box color (palette gray g22)
      box_color_year  = palette.gray.g18, -- year box color (palette gray g18)
      box_alpha       = 0.35,             -- box fill alpha
    },
  },

  ----------------------------------------------------------------
  -- Calendar Marquee (top arc)
  ----------------------------------------------------------------
  calendar_marquee = {

    -- main arc and offsets
    r_offset           = 660, -- marquee arc radius from clock center
    center_x_offset    = 0,   -- shift marquee arc center left/right
    center_y_offset    = 100, -- shift marquee arc center up/down
    arc_center_deg     = 90,  -- center angle of the marquee arc (degrees)
    arc_span_deg       = 70,  -- total arc span (degrees)
    arc_width          = 1.0, -- arc stroke width
    arc_alpha          = 0.0, -- arc stroke alpha

    -- day ticks
    apex_index         = 16,   -- 1..31 tick index used as the apex (today) position
    tick_len           = 50,   -- tick length (weekday)
    tick_len_apex      = 50,   -- apex tick length (maroon)
    tick_width         = 7,    -- tick width (weekday)
    tick_width_apex    = 12,   -- apex tick width (maroon)
    tick_alpha         = 0.40, -- tick opacity (non-apex)

    -- weekday and day/date fonts
    dow_offset         = 12,            -- radial offset for weekday letters above the arc
    dom_offset         = 65,            -- radial offset for date numbers below the arc
    font_dow           = 18,            -- base font size for weekday letters
    font_dom           = 18,            -- base font size for date numbers
    font_dow_apex      = 22,            -- larger font size for the highlighted apex weekday
    font_dom_apex      = 22,            -- larger font size for the highlighted apex date
    font_title         = "auto",        -- "auto" = fonts.title
    font_text          = fonts.value_c, -- marquee days/dates font

    -- chevron and year
    chevron_w          = 40,   -- chevron width at apex
    chevron_h          = 40,   -- chevron height at apex
    chevron_offset     = 106,  -- chevron offset below the arc
    year               = 2026, -- year label text
    year_offset        = 50,   -- year offset below chevron
    font_year          = 26,   -- year font size

    -- calendar title
    title_y_offset     = 190,        -- title offset above the arc
    title_size         = 24,         -- title font size
    title_text         = "CALENDAR", -- title text
    title_alpha        = 0.75,       -- title opacity
    draw_title         = true,       -- toggle marquee title

    -- upper hud lines that bracket the marquee arc
    bracket_short      = 0,    -- short horizontal segment near CALENDAR baseline
    bracket_diag_dx    = 10,   -- diagonal x offset up to the long top line
    bracket_diag_dy    = 40,   -- diagonal y offset up to the long top line
    bracket_diag_scale = 1.5,  -- scale diagonal length without changing base offsets
    bracket_long_pad   = 129,  -- extra length beyond the arc span
    bracket_long_len   = 0,    -- fixed long-line length (0 = use arc clamp)
    bracket_vert       = 50,   -- vertical bracket rise after the long line
    bracket_width      = 3.0,  -- bracket stroke width
    bracket_alpha      = 0.30, -- bracket opacity
    bracket_y_offset   = 300,  -- vertical offset for the entire bracket group
    bracket_side_gap   = 34,   -- gap from title edge to bracket start

    -- sunrise and sunset text (below brackets)
    sun_text_size      = 16,   -- sunrise/sunset font size
    sun_text_alpha     = 0.85, -- sunrise/sunset alpha
    sun_text_y_offset  = -42,  -- sunrise/sunset y offset below bracket
    sun_text_x_offset  = 60,   -- sunrise/sunset x offset from diagonal start

    -- event system notes (above brackets)
    event_notes        = {
      enabled         = true,                  -- toggle event notes
      y_offset        = 12,                    -- y offset above bracket long line
      x_pad           = 24,                    -- horizontal padding from bracket ends
      line_gap        = 4,                     -- extra gap between lines
      font            = fonts.value_c,         -- notes font
      text_size       = 16,                    -- notes text size
      color           = palette.gray.g90,      -- notes text color (palette gray g90)
      alpha           = 0.85,                  -- notes text alpha
      bullet_radius   = 4,                     -- bullet dot radius
      bullet_gap      = 12,                    -- bullet gap from text edge
      bullet_color    = palette.accent.maroon, -- bullet color (palette accent maroon)
      bullet_alpha    = 0.90,                  -- bullet alpha
      window_days     = 7,                     -- show events within +/-N days
      switch_hour     = 12,                    -- hour-of-day to switch to left side
      max_lines_left  = 0,                     -- 0 = no limit
      max_lines_right = 0,                     -- 0 = no limit
      left_lines      = {},                    -- optional static fallback
      right_lines     = {},                    -- optional static fallback
    },

    -- marquee colors
    color_tick         = palette.white,         -- tick color (weekday) (palette white)
    color_text         = palette.gray.g90,      -- weekday/date text color (palette gray g90)
    color_weekend      = palette.black,         -- weekend tick/text color (palette black)
    color_year         = palette.gray.g20,      -- year label color (palette gray g20)
    color_bracket      = palette.white,         -- bracket line color (palette white)
    color_title        = palette.black,         -- marquee title color (palette black)
    color_chevron      = palette.gray.g80,      -- apex chevron color (palette white)
    color_sun_text     = palette.gray.g90,      -- sunrise/sunset text color (palette gray g90)
    color_apex_tick    = palette.accent.maroon, -- apex tick color (palette accent maroon)
    color_apex_day     = palette.black,         -- apex weekday text color (palette black)
    color_apex_date    = palette.white,         -- apex date text color (palette white)
    color_event_date   = palette.accent.maroon, -- event date text color (palette accent maroon)
  },

  ----------------------------------------------------------------
  -- Weather Widget (bottom HUD)
  ----------------------------------------------------------------
  weather_widget = {
    -- positioning
    center_x_offset    = 0,   -- horizontal offset from clock center
    center_y_offset    = 460, -- vertical offset from clock center

    -- widget title
    title_text         = "WEATHER", -- widget title text
    title_size         = 24,        -- widget title size
    title_alpha        = 0.75,      -- widget title alpha
    title_y_offset     = 90,        -- title offset from bracket baseline
    title_font         = "auto",    -- "auto" = fonts.title
    draw_title         = true,      -- toggle weather title

    -- mirrored bracket geometry (independent from marquee)
    bracket_short      = 0,    -- short horizontal segment near title baseline
    bracket_diag_dx    = 10,   -- diagonal x offset to long line
    bracket_diag_dy    = 40,   -- diagonal y offset to long line
    bracket_diag_scale = 1.5,  -- scale diagonal length without changing base offsets
    bracket_long_pad   = 260,  -- extra length beyond arc span
    bracket_long_len   = 0,    -- fixed long-line length (0 = use arc clamp)
    bracket_vert       = -50,  -- vertical bracket rise after the long line
    bracket_width      = 3.0,  -- bracket stroke width
    bracket_alpha      = 0.30, -- bracket opacity
    bracket_y_offset   = -58,  -- vertical offset for the entire bracket group
    bracket_side_gap   = 45,   -- gap from title edge to bracket start

    -- center city name
    city_offset_x      = 0,                 -- city label x offset from clock center
    city_offset_y      = 115,               -- city label y offset from clock center
    city_font          = "t.fonts.value_c", -- "auto" = fonts.label
    city_size          = 16,                -- city font size
    city_color         = palette.gray.g80,  -- city text color (palette gray g80)
    city_alpha         = 0.85,              -- city text alpha

    -- center weather icon
    icon_size          = 96,  -- current icon size
    icon_offset_x      = -66, -- icon x offset from clock center
    icon_offset_y      = 170, -- icon y offset from clock center

    -- center temperature
    temp_offset_x      = 60,               -- temperature x offset from clock center
    temp_offset_y      = 170,              -- temperature y offset from clock center
    temp_font          = "auto",           -- "auto" = fonts.value
    temp_size          = 32,               -- temperature font size
    temp_color         = palette.gray.g70, -- temperature text color (palette gray g70)
    temp_alpha         = 0.95,             -- temperature text alpha

    -- center humidity
    humidity_offset_x  = 54,                -- humidity x offset from clock center
    humidity_offset_y  = 195,               -- humidity y offset from clock center
    humidity_font      = "t.fonts.value_c", -- "auto" = fonts.label
    humidity_size      = 20,                -- humidity font size
    humidity_color     = palette.gray.g90,  -- humidity text color (palette gray g90)
    humidity_alpha     = 0.85,              -- humidity text alpha

  },

  ----------------------------------------------------------------
  -- Weather Vertical Line
  ----------------------------------------------------------------
  weather = {
    -- Weather block anchors to the clock center (use weather_widget offsets)
    icon_set       = "owm_maroon",            -- icon folder under icons/ (owm, owm_default, owm_color, owm_filled, owm_maroon) or absolute path
    icon_cache_dir = "icons/gtex62-tech-hud", -- cache dir under $CONKY_CACHE_DIR (absolute path ok)

    vline          = {
      length = 80,
      width  = 1.5,
      color  = palette.gray.g80, -- vertical line color (palette gray g80)
      alpha  = 1.00,             -- vertical line alpha
      dx     = 0,                -- x offset from clock center
      dy     = 130,              -- y start offset from clock center
    },

    ----------------------------------------------------------------
    -- Aviation Weather
    ----------------------------------------------------------------
    -- METAR block (aviation weather)
    metar          = {
      enabled   = true,   -- turn METAR on/off
      station   = "KMEM", -- default ICAO
      wrap_col  = 50,
      pad_cols  = 0,
      max_lines = 4,    -- cap METAR lines (ellipsis on last if truncated)
      x_offset  = -625, -- x offset from clock center
      y_offset  = 575,  -- y offset from clock center
    },

    -- TAF block (Terminal Aerodrome Forecast)
    taf            = {
      enabled     = true,   -- turn TAF on/off
      station     = "KMEM", -- ICAO (can be different than METAR)
      wrap_col    = 53,
      pad_cols    = 0,
      max_lines   = 6,
      indent_cols = 5,    -- extra spaces for every line after the first
      x_offset    = -625, -- x offset from clock center
      y_offset    = 640,  -- y offset from clock center
    },

    -- SIGMET / AIRMET advisories
    advisories     = {
      enabled   = false,  -- turn SIGMET/AIRMET on/off
      station   = "KMEM", -- center point (used by airsig_filter.sh)
      radius_nm = 300,    -- search radius in nautical miles
      wrap_col  = 42,     -- line width for wrapping
      pad_cols  = 16,     -- indent to match METAR/TAF
      max_lines = 3,      -- cap lines shown (ellipsis on last if truncated)
      x_offset  = -778,   -- x offset from clock center
      y_offset  = 740,    -- y offset from clock center
    },

    -- Aviation text style (shared)
    aviation_style = {
      font       = fonts.value_mono, -- "auto" = fonts.value_c
      size       = 17,               -- aviation font size
      color      = palette.white,    -- aviation text color (palette white)
      alpha      = 0.99,             -- aviation text alpha
      line_gap   = 0,                -- space between lines
      auto_stack = true,             -- stack TAF/advisories under METAR
      gap_lines  = 1,                -- blank lines between blocks
    },

    ----------------------------------------------------------------
    -- Forecast
    ----------------------------------------------------------------
    -- 6-day forecast layout (tile strip under the main widget)
    forecast       = {
      x_offset   = 390,                 -- horizontal offset from clock center
      y_offset   = 95,                  -- vertical offset from clock center
      font       = "auto",              -- "auto" = fonts.value_c
      font_size  = 18,                  -- weekday label text size
      dow_weight = "bold",              -- weekday label weight ("normal" or "bold")
      tiles      = 6,                   -- days to show (today..today+5)
      tile_w     = 64,                  -- width per tile (px)
      gap        = 16,                  -- horizontal gap between tiles
      tile       = { w = 64, h = 110 }, -- tile footprint for layout

      -- Date label near top of each tile
      date       = {
        pt    = 14,
        dy    = 4,
        color = palette.forecast.date, -- color (palette forecast date)
      },

      -- Forecast icon position/size within each tile
      icon       = {
        size = 36,
        dy   = 50,
      },

      -- High / low temps per tile
      temps      = {
        font     = "auto", -- "auto" = fonts.value_c
        weight   = "bold", -- temps font weight ("normal" or "bold")
        pt       = 18,
        dy       = 100,
        color_hi = palette.forecast.temp_hi, -- color hi (palette forecast temp_hi)
        color_lo = palette.forecast.temp_lo, -- color lo (palette forecast temp_lo)
      },

      -- Optional: per-strip opacity multiplier (0.0..1.0)
      alpha      = 1.0,
    },
  },

  ----------------------------------------------------------------
  -- System (Circle)
  ----------------------------------------------------------------
  system = {
    enabled         = true, -- toggle system widget
    center_x_offset = 0,    -- horizontal offset from widget center
    center_y_offset = 0,    -- vertical offset from widget center

    circle          = {
      enabled            = true,             -- show system circle
      radius             = 115,              -- circle radius
      offset_y           = 0,                -- circle y offset
      stroke_width       = 4.0,              -- circle stroke width
      fill_color         = palette.gray.g30, -- circle fill color (palette gray g30)
      fill_alpha         = 0.65,             -- circle fill alpha
      season_tint_enable = true,             -- blend fill color with current season tint
      season_tint_amount = 0.06,             -- tint blend amount (0.0-1.0)
      stroke_color       = palette.gray.g20, -- circle stroke color (palette gray g20)
      stroke_alpha       = 0.90,             -- circle stroke alpha
    },
    circle_outer    = {
      enabled       = true,          -- show outer circle
      radius        = nil,           -- override radius (nil = circle radius + offset)
      radius_offset = 10,            -- extra radius beyond circle
      stroke_width  = 8.0,           -- outer circle stroke width
      stroke_color  = palette.white, -- outer circle stroke color (palette white)
      stroke_alpha  = 0.30,          -- outer circle stroke alpha
    },
    ticks           = {
      enabled = true,                  -- toggle 12/3/6/9 ticks
      length  = 10,                    -- tick length (px)
      width   = 3,                     -- tick width
      offset  = -14,                   -- offset from circle radius (px, outward)
      color   = palette.accent.maroon, -- tick color (RGB) (palette accent maroon)
      alpha   = 0.95,                  -- tick alpha
    },
    meters          = {
      enabled         = true,                                                                                                                                                                                                                                               -- toggle quadrant meters
      radius_offset   = -6,                                                                                                                                                                                                                                                 -- offset from circle radius (px)
      stroke_width    = 6,                                                                                                                                                                                                                                                  -- meter stroke width
      alpha           = 0.90,                                                                                                                                                                                                                                               -- meter alpha

      cpu_color       = palette.gray.g90,                                                                                                                                                                                                                                   -- CPU meter color (RGB) (palette gray g90)
      ram_color       = palette.gray.g70,                                                                                                                                                                                                                                   -- RAM meter color (RGB) (palette gray g70)
      gpu_color       = palette.gray.g50,                                                                                                                                                                                                                                   -- GPU meter color (RGB) (palette gray g50)
      vrm_color       = palette.gray.g60,                                                                                                                                                                                                                                   -- VRM meter color (RGB) (palette gray g60)

      value_cpu       = "${cpu}",                                                                                                                                                                                                                                           -- 0..100 (Conky string allowed)
      value_ram       = "${memperc}",                                                                                                                                                                                                                                       -- 0..100 (Conky string allowed)
      value_gpu       =
      "${if_existing /proc/driver/nvidia/version}${execpi 10 nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1}${else}0${endif}",                                                                                                 -- 0..100 (GPU %)
      value_vrm       =
      "${if_existing /proc/driver/nvidia/version}${execpi 10 nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | awk -F',' '{u=$1+0;t=$2+0; if(t>0) printf \"%d\", int((u*100)/t+0.5); else print 0}'}${else}0${endif}", -- 0..100 (VRAM %)

      label_font      = "auto",                                                                                                                                                                                                                                             -- "auto" = fonts.title
      label_size      = 14,                                                                                                                                                                                                                                                 -- label size
      label_color     = palette.gray.g20,                                                                                                                                                                                                                                   -- label color (RGB) (palette gray g20)
      label_alpha     = 0.90,                                                                                                                                                                                                                                               -- label alpha
      label_offset    = -14,                                                                                                                                                                                                                                                -- offset from meter radius (px, negative = inward)
      labels          = { CPU = "CPU", RAM = "RAM", GPU = "GPU", VRM = "VRM" },
      swap_top_bottom = true,                                                                                                                                                                                                                                               -- swap top/bottom quadrants (meters + labels)
    },
    center_label    = {
      enabled  = true,          -- toggle center SYS label
      text     = "SYS",         -- label text
      font     = "auto",        -- "auto" = fonts.title
      size     = 18,            -- label size
      color    = palette.black, -- label color (RGB) (palette black)
      alpha    = 1.00,          -- label alpha
      offset_x = 0,             -- x offset from center
      offset_y = 0,             -- y offset from center
    },
    os_label        = {
      enabled  = true,          -- toggle OS label above SYS
      text     = "auto",        -- "auto" = LM <version> from mint_version.sh
      font     = "auto",        -- "auto" = center_label.font
      size     = 14,            -- label size
      color    = palette.white, -- label color (RGB) (palette white)
      alpha    = 0.50,          -- label alpha
      offset_x = 0,             -- x offset from center
      offset_y = -44,           -- y offset from center
    },
    kernel_label    = {
      enabled  = true,             -- toggle kernel label under OS label
      text     = "auto",           -- "auto" = shortened ${kernel}
      font     = fonts.value_mono, -- kernel label font
      size     = 14,               -- label size
      color    = palette.white,    -- label color (RGB) (palette white)
      alpha    = 0.70,             -- label alpha
      offset_x = 0,                -- x offset from center
      offset_y = -28,              -- y offset from center
    },
    os_age          = {
      enabled        = true,                  -- toggle OS age label
      value          = "auto",                -- "auto" = stat -c %W on root_path (or set ${root_birth})
      root_path      = "/",                   -- filesystem path for root birth time
      poll           = 3600,                  -- seconds between stat refresh
      fallback_mtime = true,                  -- fallback to stat -c %Y if birth unsupported
      pad_digits     = 4,                     -- zero-pad days (e.g. 0047d)
      format         = "%04d",                -- custom format (string.format with days)
      font           = fonts.value_mono,      -- label font
      size           = 16,                    -- label size
      color          = palette.accent.orange, -- label color (orange) (palette accent orange)
      alpha          = 0.90,                  -- label alpha
      offset_x       = 0,                     -- x offset from center
      offset_y       = 65,                    -- y offset from center
    },
    disk_label      = {
      enabled    = true,                                            -- toggle disk labels below SYS
      font       = "auto",                                          -- "auto" = center_label.font
      size       = 11,                                              -- label size
      color      = palette.white,                                   -- label color (RGB) (palette white)
      alpha      = 0.50,                                            -- label alpha
      offset_x   = 0,                                               -- x offset from center
      offset_y   = 20,                                              -- y offset from center (first line)
      line_h     = 16,                                              -- line spacing
      root_label = "/ROOT",                                         -- label for root disk
      root_path  = "/",                                             -- filesystem path for root
      wd_label   = "/WD_BLACK",                                     -- label for WD Black
      wd_path    = (os.getenv("WD_BLACK_PATH") or "/mnt/WD_Black"), -- filesystem path for WD Black
    },
  },

  ----------------------------------------------------------------
  -- Network (Circle)
  ----------------------------------------------------------------
  network = {
    enabled         = true,   -- toggle network widget
    center_x_offset = 0,      -- horizontal offset from widget center
    center_y_offset = 0,      -- vertical offset from widget center
    iface           = "eno1", -- interface for up/down meters

    circle          = {
      enabled            = true,             -- show network circle
      radius             = 115,              -- circle radius
      offset_y           = 0,                -- circle y offset
      stroke_width       = 4.0,              -- circle stroke width
      fill_color         = palette.gray.g30, -- circle fill color (palette gray g30)
      fill_alpha         = 0.65,             -- circle fill alpha
      season_tint_enable = true,             -- blend fill color with current season tint
      season_tint_amount = 0.06,             -- tint blend amount (0.0-1.0)
      stroke_color       = palette.gray.g20, -- circle stroke color (palette gray g20)
      stroke_alpha       = 0.90,             -- circle stroke alpha
    },
    circle_outer    = {
      enabled       = true,          -- show outer circle
      radius        = nil,           -- override radius (nil = circle radius + offset)
      radius_offset = 10,            -- extra radius beyond circle
      stroke_width  = 8.0,           -- outer circle stroke width
      stroke_color  = palette.white, -- outer circle stroke color (palette white)
      stroke_alpha  = 0.30,          -- outer circle stroke alpha
    },
    ticks           = {
      enabled = true,                  -- toggle 12/3/6/9 ticks
      length  = 10,                    -- tick length (px)
      width   = 3,                     -- tick width
      offset  = -14,                   -- offset from circle radius (px, outward)
      color   = palette.accent.maroon, -- tick color (RGB) (palette accent maroon)
      alpha   = 0.95,                  -- tick alpha
    },
    meters          = {
      enabled       = true,             -- toggle quadrant meters
      radius_offset = -6,               -- offset from circle radius (px)
      stroke_width  = 6,                -- meter stroke width
      alpha         = 0.90,             -- meter alpha

      up_color      = palette.gray.g65, -- UP meter color (RGB) (palette gray g65)
      down_color    = palette.gray.g80, -- DOWN meter color (RGB) (palette gray g80)
      ping1_color   = palette.gray.g50, -- 1.1.1.1 meter color (RGB) (palette gray g50)
      ping2_color   = palette.gray.g40, -- 8.8.8.8 meter color (RGB) (palette gray g40)

      max_up_mbps   = 1,                -- normalize UP (Mbps)
      max_down_mbps = 1,                -- normalize DOWN (Mbps)
      max_ping_ms   = 50,               -- normalize ping (ms)

      label_font    = "auto",           -- "auto" = fonts.title
      label_size    = 14,               -- label size
      label_color   = palette.gray.g20, -- label color (RGB) (palette gray g20)
      label_alpha   = 0.90,             -- label alpha
      label_offset  = -14,              -- offset from meter radius (px, negative = inward)
      labels        = { UP = "UP", DOWN = "DOWN", P1 = "1.1.1.1", P2 = "8.8.8.8" },
      swap_up_down  = true,             -- swap UP/DOWN meters + labels
      smoothing     = { alpha = 0.35 }, -- EMA smoothing (lower = slower)
      value_font    = fonts.value_mono, -- value font (no rotation)
      value_size    = 16,               -- value size
      value_color   = palette.white,    -- value color (RGB) (palette white)
      value_alpha   = 0.90,             -- value alpha
      value_offset  = -45,              -- offset from meter radius (px, negative = inward)
    },
    center_label    = {
      enabled  = true,          -- toggle center NET label
      text     = "NET",         -- label text
      font     = "auto",        -- "auto" = fonts.title
      size     = 18,            -- label size
      color    = palette.black, -- label color (RGB) (palette black)
      alpha    = 1.00,          -- label alpha
      offset_x = 0,             -- x offset from center
      offset_y = 0,             -- y offset from center
    },
    status_label    = {
      enabled  = true,          -- toggle status above NET
      font     = "auto",        -- "auto" = fonts.title
      size     = 12,            -- label size
      color    = palette.white, -- label color (RGB) (palette white)
      alpha    = 0.30,          -- label alpha
      offset_x = 0,             -- x offset from center
      offset_y = -22,           -- y offset from center
    },
    wan_label       = {
      enabled      = true,                  -- toggle WAN IP below NET
      font         = "auto",                -- "auto" = fonts.title
      size         = 12,                    -- label size
      color        = palette.white,         -- label color (RGB) (palette white)
      alpha        = 0.40,                  -- label alpha
      offset_x     = 0,                     -- x offset from center
      offset_y     = 17,                    -- y offset from center
      vpn_text     = "V",                   -- VPN marker text
      vpn_size     = 14,                    -- VPN marker size
      vpn_color    = palette.accent.orange, -- VPN marker color (RGB) (palette accent orange)
      vpn_alpha    = 0.40,                  -- VPN marker alpha
      vpn_offset_y = 22,                    -- VPN marker y offset from IP
    },
  },

  ----------------------------------------------------------------
  -- Notes (Panel)
  ----------------------------------------------------------------
  notes = {
    enabled    = true,                          -- toggle notes panel
    font       = fonts.value_mono .. ":size=8", -- notes font
    text_color = palette.white,                 -- notes text color (palette white)
    text_alpha = 1.00,                          -- notes text alpha
    wrap       = 39,                            -- chars per line for fold
    lines      = 90,                            -- how many lines to show
    line_px    = 14,                            -- approx px per line (mono font)
    text_x     = 22,                            -- text x offset (px from left)
    text_y     = 30,                            -- text y offset (px)
    panel      = {
      enabled            = false,               -- draw the background panel
      offset_x           = 30,                  -- x offset from window origin
      offset_y           = 30,                  -- y offset from window origin
      width              = 370,                 -- override panel width (nil = window width - padding)
      height             = nil,                 -- override panel height (nil = window height - padding)
      padding_x          = 10,                  -- padding from window edge (when width is nil)
      padding_y          = 8,                   -- padding from window edge (when height is nil)
      radius             = 12,                  -- corner radius (px)
      stroke_width       = 4.0,                 -- panel stroke width
      fill_color         = palette.gray.g30,    -- nil = system/network.circle.fill_color (palette gray g30)
      fill_alpha         = 0.45,                -- nil = system/network.circle.fill_alpha
      season_tint_enable = true,                -- blend fill color with current season tint
      season_tint_amount = 0.44,                -- tint blend amount (0.0-1.0)
      stroke_color       = palette.gray.g20,    -- nil = system/network.circle_outer.stroke_color (palette gray g20)
      stroke_alpha       = 0.90,                -- nil = system/network.circle_outer.stroke_alpha
      outer_stroke       = {
        enabled = true,                         -- draw outer stroke
        offset  = 10,                           -- px outside panel
        width   = 8.0,                          -- outer stroke width
        color   = palette.white,                -- nil = system/network.circle_outer.stroke_color (palette white)
        alpha   = 0.30,                         -- nil = system/network.circle_outer.stroke_alpha
      },
    },
    bracket    = {
      enabled    = true,          -- draw right-edge bracket
      flip_h     = true,          -- flip bracket horizontally
      flip_v     = true,          -- flip bracket vertically
      x          = 460,           -- x offset from panel origin
      y          = 372,           -- y offset from panel origin
      short      = 0,             -- short vertical segment length
      diag_dx    = 12,            -- diagonal x offset (positive = right)
      diag_dy    = 6,             -- diagonal y offset (positive = down)
      diag_scale = 1.7,           -- scale diagonal length
      diag_short = 50,            -- short horizontal run after diagonal
      long_len   = 370,           -- long vertical length (0 = auto to panel bottom)
      vert       = 36,            -- horizontal hook length (positive = right)
      width      = 3.0,           -- bracket stroke width
      alpha      = 0.30,          -- bracket opacity
      color      = palette.white, -- bracket color (palette white)
    },

    title      = {
      enabled = true,          -- draw NOTES title
      text    = "NOTES",       -- title text
      font    = "auto",        -- "auto" = fonts.title
      size    = 24,            -- title font size
      alpha   = 0.75,          -- title opacity
      color   = palette.black, -- title color (palette black)
      x       = 410,           -- x offset from panel origin
      y       = 515,           -- y offset from panel origin
      rot_deg = 90,            -- rotation degrees (90 CCW)
    },
  },

  ----------------------------------------------------------------
  -- Music + Lyrics (Panel)
  ----------------------------------------------------------------
  music = {
    enabled            = true,  -- toggle music panel
    hide_when_inactive = false, -- set false to keep panel visible
    idle_hide_after_s  = 10,    -- seconds to keep panel visible after stop
    inactive_message   = "Play music, feel better.",

    content_offset_x   = 100, -- content shift from panel origin
    content_offset_y   = 30,

    panel              = {
      enabled            = false,                -- draw the background panel
      offset_x           = 20,                   -- x offset from window origin
      offset_y           = 20,                   -- y offset from window origin
      width              = 700,                  -- override panel width (nil = window width - padding)
      height             = nil,                  -- override panel height (nil = window height - padding)
      padding_x          = 10,                   -- padding from window edge (when width is nil)
      padding_y          = 8,                    -- padding from window edge (when height is nil)
      radius             = 12,                   -- corner radius (px)
      stroke_width       = 4.0,                  -- panel stroke width
      fill_color         = { 0.30, 0.30, 0.30 }, -- panel fill color (RGB)
      fill_alpha         = 0.45,                 -- panel fill alpha
      season_tint_enable = false,                -- blend fill color with current season tint
      season_tint_amount = 0.44,                 -- tint blend amount (0.0-1.0)
      stroke_color       = { 0.20, 0.20, 0.20 }, -- panel stroke color (RGB)
      stroke_alpha       = 0.90,                 -- panel stroke alpha
      outer_stroke       = {
        enabled = true,                          -- draw outer stroke
        offset  = 10,                            -- px outside panel
        width   = 8.0,                           -- outer stroke width
        color   = { 1.00, 1.00, 1.00 },          -- outer stroke color (RGB)
        alpha   = 0.30,                          -- outer stroke alpha
      },
    },

    bracket            = {
      enabled    = true,          -- draw left-edge bracket
      flip_v     = true,          -- flip bracket vertically
      x          = 20,            -- x offset from panel origin
      y          = 410,           -- y offset from panel origin
      short      = 0,             -- short vertical segment length
      diag_dx    = 12,            -- diagonal x offset (positive = right)
      diag_dy    = 6,             -- diagonal y offset (positive = down)
      diag_scale = 1.7,           -- scale diagonal length
      diag_short = 50,            -- short horizontal run after diagonal
      long_len   = 370,           -- long vertical length (0 = auto to panel bottom)
      vert       = 36,            -- horizontal hook length (positive = right)
      width      = 3.0,           -- bracket stroke width
      alpha      = 0.30,          -- bracket opacity
      color      = palette.white, -- bracket color (palette white)
    },

    title              = {
      enabled = true,          -- draw MUSIC title
      text    = "MUSIC",       -- title text
      font    = "auto",        -- "auto" = fonts.title
      size    = 24,            -- title font size
      alpha   = 0.75,          -- title opacity
      color   = palette.black, -- title color (palette black)
      x       = 72,            -- x offset from panel origin
      y       = 552,           -- y offset from panel origin
      rot_deg = -90,           -- rotation degrees (90 CCW)
    },

    art                = {
      x        = 30, -- art left (px from panel origin)
      y        = 30, -- art top (px from panel origin)
      w        = 90, -- art width (px)
      h        = 90, -- art height (px)
      fallback = "icons/horn-of-odin.png",
    },

    header             = {
      gap_x    = 18,               -- distance from art to text block
      line_gap = 6,                -- gap between lines
      artist   = {
        font      = fonts.title,   -- title font
        size      = 16,
        color     = palette.white, -- artist color (palette white)
        alpha     = 0.60,
        uppercase = true,
        marquee   = {
          enabled    = true, -- marquee when text exceeds max_w
          max_w      = 285,  -- max text width before marquee (px)
          gap_px     = 40,   -- gap between repeated text (px)
          speed_px_u = 2,    -- scroll speed (px/update)
        },
      },
      album    = {
        font    = fonts.value,
        size    = 12,
        color   = palette.gray.g90, -- album color (palette gray g90)
        alpha   = 0.55,
        marquee = {
          enabled    = true, -- marquee when text exceeds max_w
          max_w      = 285,  -- max text width before marquee (px)
          gap_px     = 40,   -- gap between repeated text (px)
          speed_px_u = 2,    -- scroll speed (px/update)
        },
      },
      title    = {
        font    = fonts.value,
        size    = 14,
        color   = palette.white, -- title color (palette white)
        alpha   = 0.50,
        marquee = {
          enabled    = true, -- marquee when text exceeds max_w
          max_w      = 285,  -- max text width before marquee (px)
          gap_px     = 40,   -- gap between repeated text (px)
          speed_px_u = 2,    -- scroll speed (px/update)
        },
      },
    },

    progress           = {
      x      = 30,            -- progress line start (px from panel origin)
      y      = 140,           -- progress line y (px from panel origin)
      length = 400,           -- progress line length (px)
      stroke = 2.0,           -- progress line stroke width
      color  = palette.white, -- progress line color (palette gray g80)
      alpha  = 0.30,
      marker = {
        diameter = 10,
        color    = palette.accent.maroon, -- marker color (palette accent maroon)
        alpha    = 1.00,
      },
      time   = {
        font  = fonts.value,
        size  = 14,
        color = palette.white, -- time label color (palette gray g80)
        alpha = 0.30,
        dy    = 20,            -- label offset from the line
      },
    },

    lyrics             = {
      x                        = 30,   -- lyrics left (px from panel origin)
      y                        = 170,  -- lyrics top (px from panel origin)
      w                        = 700,  -- lyrics width (px)
      h                        = 1310, -- lyrics height (px)
      gap_y                    = 28,   -- gap from progress line when y is auto
      bottom_pad               = 0,

      font                     = fonts.value,
      size                     = 12,
      color                    = palette.white, -- lyrics color (palette white)
      alpha                    = 0.50,
      line_px                  = 16,
      wrap_enabled             = true, -- word-wrap lyrics to progress.length when true

      hide_when_inactive       = false,
      inactive_message         = "No music playing.",
      offline_message          = "Offline",
      not_found_message        = "Lyrics not found",
      instrumental_message     = "Instrumental",
      searching_message        = "Searching...",

      normalize_blank_lines    = true,
      max_blank_run            = 1,
      whitespace_only_is_blank = true,
      strip_lrc_timestamps     = true,

      more_marker              = "...more...",
      show_saved_path          = true,
      saved_prefix             = "Saved to: ",
    },
  },

  ----------------------------------------------------------------
  -- Station Model (METAR) (Circle)
  ----------------------------------------------------------------
  station_model = {
    enabled             = true,                  -- toggle station model
    station             = "KMEM",                -- ICAO
    wrap_col            = 240,                   -- wrap width for METAR fetch
    cache_ttl           = 60,                    -- seconds between fetches
    cache_path          = "",                    -- decoded cache path (optional, "%s" -> station)
    debug_metar         = "",                    -- override METAR string for testing
    debug               = false,                 -- print parsed fields to stdout

    center_x_offset     = 0,                     -- horizontal offset from widget center
    center_y_offset     = 0,                     -- vertical offset from widget center

    font_symbol         = "WX Symbols",          -- weather glyph font
    font_value          = "auto",                -- "auto" = fonts.value
    font_small          = "auto",                -- "auto" = fonts.label
    font_numbers        = fonts.value_mono,      -- "auto" = font_value
    center_text_y       = true,                  -- vertically center text/glyphs on y

    color_symbol        = palette.gray.g10,      -- glyph color (palette gray g10)
    color_cloud         = nil,                   -- cloud glyph color (overrides color_symbol)
    color_wx            = palette.accent.orange, -- wx glyph color (overrides color_symbol) (palette accent orange)
    color_tendency      = palette.gray.g90,      -- tendency glyph color (overrides color_symbol) (palette gray g90)
    color_text          = palette.gray.g90,      -- value color (palette gray g90)
    color_dim           = palette.gray.g90,      -- dim value color (palette gray g90)
    alpha_symbol        = 1.00,                  -- glyph alpha
    alpha_text          = 0.85,                  -- value alpha

    cloud_size          = 40,                    -- cloud cover glyph size
    wx_size             = 40,                    -- present weather glyph size
    value_size          = 22,                    -- temp/dew/SLP size
    vis_size            = 22,                    -- visibility size
    tendency_size       = 22,                    -- tendency glyph/value size
    vis_fraction_glyphs = true,                  -- render fractional vis with glyphs (set false for decimals)

    circle              = {
      enabled            = true,             -- show station circle
      radius             = 115,              -- circle radius
      offset_y           = 0,                -- circle y offset
      stroke_width       = 4.0,              -- circle stroke width
      fill_color         = palette.gray.g30, -- circle fill color (palette gray g30)
      fill_alpha         = 0.65,             -- circle fill alpha
      season_tint_enable = true,             -- blend fill color with current season tint
      season_tint_amount = 0.06,             -- tint blend amount (0.0-1.0)
      stroke_color       = palette.gray.g20, -- circle stroke color (palette gray g20)
      stroke_alpha       = 0.90,             -- circle stroke alpha
    },
    circle_outer        = {
      enabled       = true,          -- show outer circle
      radius        = nil,           -- override radius (nil = circle radius + offset)
      radius_offset = 10,            -- extra radius beyond circle
      stroke_width  = 8.0,           -- outer circle stroke width
      stroke_color  = palette.white, -- outer circle stroke color (palette white)
      stroke_alpha  = 0.30,          -- outer circle stroke alpha
    },
    compass             = {
      enabled      = true,                  -- show compass tick marks
      offset       = -10,                   -- offset from circle edge (outward)
      length_major = 12,                    -- N/E/S/W tick length
      length_mid   = 8,                     -- 30/60/120/150/210/240/300/330 tick length
      length_minor = 5,                     -- 10-degree tick length
      width_major  = 2.6,                   -- N/E/S/W tick width
      width_mid    = 2.0,                   -- 30/60/etc tick width
      width_minor  = 1.2,                   -- 10-degree tick width
      color_major  = palette.white,         -- N/E/S/W tick color (palette white)
      color_mid    = palette.gray.g85,      -- 30/60/etc tick color (palette gray g85)
      color_minor  = palette.gray.g70,      -- 10-degree tick color (palette gray g70)
      color_wind   = palette.accent.orange, -- wind direction tick color (orange) (palette accent orange)
      alpha        = 0.50,                  -- tick alpha
      wind_alpha   = 0.95,                  -- wind direction tick alpha
      n_label      = {
        enabled = true,                     -- show north label
        text    = "N",                      -- north label text
        offset  = 10,                       -- inward offset from tick base radius
        size    = 18,
        color   = palette.accent.maroon,
        alpha   = 0.70,
      },
    },

    cloud_offset_x      = 0,   -- cloud glyph x offset
    cloud_offset_y      = 0,   -- cloud glyph y offset

    wx_offset_x         = -44, -- present wx glyph x offset
    wx_offset_y         = 0,   -- present wx glyph y offset

    vis_offset_x        = -67,
    vis_offset_y        = 0,

    temp_offset_x       = -52,
    temp_offset_y       = -40,

    dew_offset_x        = -52,
    dew_offset_y        = 40,
    temp_dew_center_x   = -55, -- shared temp/dew center x offset

    slp_offset_x        = 35,
    slp_offset_y        = -40,

    tendency_offset_x   = 38,   -- tendency glyph x offset
    tendency_offset_y   = 0,
    tendency_value_dx   = 16,   -- tendency value x offset from glyph
    show_tendency       = true, -- show pressure tendency block

    precip_size         = 22,
    precip_offset_x     = 35,
    precip_offset_y     = 40,
    show_precip         = true, -- show 6h precip block

    station_label       = {
      enabled  = true,   -- show station ICAO
      y_offset = -34,    -- label y offset from bottom anchor
      font     = "auto", -- "auto" = fonts.title
      size     = 16,
      color    = palette.black,
      alpha    = 0.60,
    },

    wind                = {
      staff_len      = 72,   -- wind barb staff length
      staff_start    = 18,   -- offset from station center to start staff
      line_width     = 3.0,  -- staff/barb stroke width
      barb_len       = 30,   -- full barb length
      half_barb_len  = 15,   -- half barb length
      barb_spacing   = 10,   -- spacing between barbs along staff
      barb_angle_deg = 60,   -- barb angle from staff
      barb_side      = "cw", -- "cw" or "ccw" side of the staff
      pennant_len    = 18,   -- pennant length
      pennant_width  = 10,   -- pennant base width along staff

      calm_circle    = false,
      calm_radius    = 8,

      color          = palette.gray.g10, -- optional override for wind barb color (palette gray g10)
      alpha          = 0.95,             -- optional override for wind barb alpha

      vrb_label      = true,
      vrb_offset_x   = -10,
      vrb_offset_y   = -72,
      vrb_size       = 12,
      vrb_color      = palette.gray.g90,
      vrb_alpha      = 0.85,
    },
  },

  ----------------------------------------------------------------
  -- Barometer Gauge (Circle)
  ----------------------------------------------------------------
  baro_gauge = {
    enabled         = true, -- toggle baro gauge
    center_x_offset = 0,    -- horizontal offset from widget center
    center_y_offset = 0,    -- vertical offset from widget center

    circle          = {
      enabled            = true,             -- show baro circle
      radius             = 115,              -- circle radius
      offset_y           = 0,                -- circle y offset
      stroke_width       = 4.0,              -- circle stroke width
      fill_color         = palette.gray.g30, -- circle fill color (palette gray g30)
      fill_alpha         = 0.65,             -- circle fill alpha
      season_tint_enable = true,             -- blend fill color with current season tint
      season_tint_amount = 0.06,             -- tint blend amount (0.0-1.0)
      stroke_color       = palette.gray.g20, -- circle stroke color (palette gray g20)
      stroke_alpha       = 0.90,             -- circle stroke alpha
    },
    circle_outer    = {
      enabled       = true,          -- show outer circle
      radius        = nil,           -- override radius (nil = circle radius + offset)
      radius_offset = 10,            -- extra radius beyond circle
      stroke_width  = 8.0,           -- outer circle stroke width
      stroke_color  = palette.white, -- outer circle stroke color (palette white)
      stroke_alpha  = 0.30,          -- outer circle stroke alpha
    },
    text            = {
      enabled         = true,          -- show pressure text
      y_offset        = 10,            -- text y offset from center
      separator       = " | ",         -- separator between inHg and hPa
      inhg_source     = "slp",         -- "slp" or "altimeter" for inHg
      font            = "auto",        -- "auto" = station_model.font_numbers
      size            = 18,            -- 0 = station_model.value_size
      color           = nil,           -- nil = station_model.color_text
      alpha           = 1.00,          -- nil = station_model.alpha_text
      show_source     = true,          -- show SLP/ALT indicator
      source_y_offset = 70,            -- SLP/ALT label y offset from top anchor
      source_font     = "auto",        -- "auto" = fonts.title
      source_size     = 20,            -- 0 = text.size * 0.6
      source_color    = palette.black, -- nil = text.color (palette black)
      source_alpha    = 0.60,          -- nil = text.alpha
    },
    arc             = {
      enabled      = true,          -- show pressure arcs
      radius_inset = 18,            -- arc inset from outer ring
      stroke_width = 6.0,           -- arc stroke width
      color_left   = palette.white, -- left arc color (inHg) (palette white)
      color_right  = palette.white, -- right arc color (hPa) (palette white)
      alpha_left   = 0.20,          -- left arc alpha
      alpha_right  = 0.20,          -- right arc alpha
    },
    ticks           = {
      enabled    = true,                  -- show arc ticks
      length     = 10,                    -- tick length
      width      = 3.0,                   -- tick width
      alpha      = 0.95,                  -- tick alpha
      color_low  = palette.white,         -- low tick color (palette white)
      color_std  = palette.accent.maroon, -- standard tick color (palette accent maroon)
      color_high = palette.white,         -- high tick color (palette white)
    },
    record_labels   = {
      hi_y_offset = 10,  -- record high label y offset
      lo_y_offset = -10, -- record low label y offset
    },
    range           = {
      use_inhg_range = false,  -- derive hPa min/max from inHg min/max
      hpa_min        = 950.0,  -- record low (870 hPa)
      hpa_max        = 1050.0, -- record high (1084.8 hPa)
      hpa_std        = 1013.2, -- standard (hPa)
      inhg_min       = nil,    -- override inHg min (nil = convert hPa)
      inhg_max       = nil,    -- override inHg max (nil = convert hPa)
      inhg_std       = 29.92,  -- standard (inHg)
    },
  },
}

----------------------------------------------------------------
-- Layout Helpers
----------------------------------------------------------------
local function layout_scale_value()
  local L = t.layout or {}
  local mode = L.scale_mode or "manual"
  if mode == "auto" then
    local w = tonumber(os.getenv("CONKY_SCREEN_W"))
    local h = tonumber(os.getenv("CONKY_SCREEN_H"))
    local bw = tonumber(L.base_width)
    local bh = tonumber(L.base_height)
    if w and h and bw and bh and bw > 0 and bh > 0 then
      local sw = w / bw
      local sh = h / bh
      return math.min(sw, sh)
    end
  end
  return tonumber(L.scale) or 1.0
end

local function layout_scale()
  local s = layout_scale_value()
  if (t.layout or {}).tie_draw_scale then
    t.scale = s
  end
  return s
end

function t.layout_pos(key)
  local L = t.layout or {}
  local p = (L.positions or {})[key] or { x = 0, y = 0 }
  local s = layout_scale()
  local fit = (L.position_fit or {})[key]

  local function interp_points(axis)
    local points = fit and fit.points
    if type(points) ~= "table" or #points < 2 then
      return nil
    end
    local first = points[1]
    local last = points[#points]
    if not first or not last then
      return nil
    end
    local function get_val(pt)
      return pt and pt[axis] and tonumber(pt[axis]) or nil
    end
    if s >= (first.scale or 0) then
      local a = first
      local b = points[2]
      if not b then return get_val(a) end
      local denom = (a.scale or s) - (b.scale or s)
      if denom == 0 then return get_val(a) end
      local t = (s - (b.scale or s)) / denom
      local av = get_val(a)
      local bv = get_val(b)
      if av == nil or bv == nil then return nil end
      return bv + t * (av - bv)
    end
    if s <= (last.scale or s) then
      local a = points[#points - 1]
      local b = last
      if not a then return get_val(b) end
      local denom = (a.scale or s) - (b.scale or s)
      if denom == 0 then return get_val(b) end
      local t = (s - (b.scale or s)) / denom
      local av = get_val(a)
      local bv = get_val(b)
      if av == nil or bv == nil then return nil end
      return bv + t * (av - bv)
    end
    for i = 1, #points - 1 do
      local a = points[i]
      local b = points[i + 1]
      local sa = a and a.scale
      local sb = b and b.scale
      if sa and sb and s <= sa and s >= sb then
        local denom = sa - sb
        if denom == 0 then return get_val(a) end
        local t = (s - sb) / denom
        local av = get_val(a)
        local bv = get_val(b)
        if av == nil or bv == nil then return nil end
        return bv + t * (av - bv)
      end
    end
    return nil
  end

  local inv = (L.inverse_positions or {})[key]
  local sx = s
  local sy = s
  if inv then
    if s ~= 0 then
      if type(inv) == "table" then
        if inv.x then sx = 1 / s end
        if inv.y then sy = 1 / s end
      else
        sx = 1 / s
        sy = 1 / s
      end
    end
  end
  local function fit_axis(base_val, ref_val, axis_scale, axis)
    local curve_val = interp_points(axis)
    if curve_val ~= nil then
      return math.floor(curve_val + 0.5)
    end
    if not fit or ref_val == nil then
      return math.floor((tonumber(base_val) or 0) * axis_scale + 0.5)
    end
    local base = tonumber(base_val) or 0
    local ref = tonumber(ref_val)
    local ref_scale = tonumber(fit.ref_scale) or 1.0
    if base <= 0 or not ref or ref <= 0 or ref_scale <= 0 or s <= 0 then
      return math.floor(base * axis_scale + 0.5)
    end
    local k = math.log(ref / base) / math.log(ref_scale)
    return math.floor(base * (s ^ k) + 0.5)
  end
  local ref = fit and (fit.ref or {}) or {}
  local anchor_scale = (p.anchor_scale ~= false)
  local off_x = anchor_scale and fit_axis(p.x, fit and (fit.x or ref.x) or nil, sx, "x")
      or math.floor((tonumber(p.x) or 0) + 0.5)
  local off_y = anchor_scale and fit_axis(p.y, fit and (fit.y or ref.y) or nil, sy, "y")
      or math.floor((tonumber(p.y) or 0) + 0.5)

  if p.anchor == "clock_center" then
    local base_w = tonumber(L.base_width) or 0
    local base_h = tonumber(L.base_height) or 0
    local center_scale = (tostring(L.scale_mode) == "auto") and s or 1.0
    local cx = (base_w / 2) * center_scale
    local cy = (base_h / 2) * center_scale
    local tp = (L.positions or {}).time or {}
    local tx = math.floor(((tonumber(tp.x) or 0) * s) + 0.5)
    local ty = math.floor(((tonumber(tp.y) or 0) * s) + 0.5)
    local ax = math.floor(cx + tx + 0.5)
    local ay = math.floor(cy + ty + 0.5)
    local size = (L.sizes or {})[key] or {}
    local sw = size.min_w or size.max_w
    local sh = size.min_h or size.max_h
    local w = sw and math.floor(((tonumber(sw) or 0) * s) + 0.5) or 0
    local h = sh and math.floor(((tonumber(sh) or 0) * s) + 0.5) or 0
    local anchor_point = p.anchor_point or "top_left"
    local x = ax + off_x
    local y = ay + off_y
    if anchor_point == "top_right" then
      x = x - w
    elseif anchor_point == "bottom_left" then
      y = y - h
    elseif anchor_point == "bottom_right" then
      x = x - w
      y = y - h
    elseif anchor_point == "center" then
      x = x - (w / 2)
      y = y - (h / 2)
    end
    return { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
  end

  return { x = off_x, y = off_y }
end

function t.layout_dim(key, field, fallback)
  local L = t.layout or {}
  local size = (L.sizes or {})[key] or {}
  local v = size[field]
  if v == nil then v = fallback end
  if v == nil then return nil end
  local s = layout_scale()
  return math.floor((tonumber(v) or 0) * s + 0.5)
end

layout_scale()

return t
