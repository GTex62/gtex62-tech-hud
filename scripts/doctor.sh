#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"

HOME_DIR="${HOME:-}"
SUITE_DIR="${CONKY_SUITE_DIR:-$HOME_DIR/.config/conky/gtex62-tech-hud}"
CACHE_DIR="${CONKY_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME_DIR/.cache}/conky}"
CONFIG_DIR="$SUITE_DIR/config"

DOCTOR_SSH_TTL="${DOCTOR_SSH_TTL:-300}"
SSH_LAST_FILE="$CACHE_DIR/pfsense/doctor_ssh_last"

COLOR_OK="00C853"
COLOR_WARN="FFD600"
COLOR_FAIL="FF5252"

ACTIONS=()
THEME_NOTES=1
THEME_MUSIC=1
THEME_STATION=1
THEME_BARO=1
THEME_NETWORK=1
THEME_SYSTEM=1
THEME_METAR=1
THEME_TAF=1
THEME_ADVISORIES=0
SITREP_AP=1
SITREP_PFSENSE=1

extract_action() {
  local msg="$1"
  printf '%s' "$msg" | sed -nE 's/.*\(([^()]*)\)[[:space:]]*$/\1/p'
}

add_action() {
  local action="$1"
  action="$(printf '%s' "$action" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -z "$action" ]] && return 0
  local a
  for a in "${ACTIONS[@]}"; do
    [[ "$a" == "$action" ]] && return 0
  done
  ACTIONS+=("$action")
}

say() {
  local level="$1"
  local msg="$2"
  local action="${3:-}"
  local color="$COLOR_OK"
  case "$level" in
    WARN) color="$COLOR_WARN" ;;
    FAIL) color="$COLOR_FAIL" ;;
  esac
  printf '${color %s}●${color} %-4s %s\n' "$color" "$level" "$msg"
  if [[ "$level" == "WARN" || "$level" == "FAIL" ]]; then
    if [[ -z "$action" ]]; then
      action="$(extract_action "$msg")"
    fi
    add_action "$action"
  fi
}

section() {
  local title="$1"
  printf '\n== %s ==\n' "$title"
}

read_kv() {
  local file="$1" key="$2" line val
  [[ -f "$file" ]] || return 1
  line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 || true)"
  if [[ -z "$line" ]]; then
    printf '%s' ""
    return 0
  fi
  val="${line#*=}"
  val="${val%%#*}"
  val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$val"
}

is_float() {
  [[ "${1:-}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

check_cmds() {
  local label="$1" hint="$2"
  shift 2
  local missing=()
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    say "WARN" "$label missing: ${missing[*]} ($hint)"
    return 1
  fi
  say "OK" "$label found: $*"
  return 0
}

check_file() {
  local path="$1" label="$2" hint="$3" level_missing="$4"
  if [[ -f "$path" ]]; then
    if [[ -s "$path" ]]; then
      say "OK" "$label"
    else
      say "WARN" "$label is empty ($hint)"
    fi
  else
    say "$level_missing" "$label missing ($hint)"
  fi
}

check_dir() {
  local path="$1" label="$2" action="${3:-}"
  if [[ -d "$path" ]]; then
    say "OK" "$label"
  else
    say "WARN" "$label missing" "$action"
  fi
}

list_missing_files() {
  local base="$1"
  shift
  local missing=()
  local empty=()
  local f path
  for f in "$@"; do
    path="$base/$f"
    if [[ ! -f "$path" ]]; then
      missing+=("$f")
    elif [[ ! -s "$path" ]]; then
      empty+=("$f")
    fi
  done
  if (( ${#missing[@]} == 0 && ${#empty[@]} == 0 )); then
    printf '%s' ""
    return 0
  fi
  local msg=""
  if (( ${#missing[@]} > 0 )); then
    msg+="missing: ${missing[*]}"
  fi
  if (( ${#empty[@]} > 0 )); then
    if [[ -n "$msg" ]]; then msg+="; " ; fi
    msg+="empty: ${empty[*]}"
  fi
  printf '%s' "$msg"
}

get_conky_args() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -af conky 2>/dev/null | sed -E 's/^[0-9]+[[:space:]]+//'
  else
    ps -C conky -o args= 2>/dev/null || true
  fi
}

widget_loaded() {
  local conf="$1"
  local base
  base="$(basename "$conf")"
  if [[ -z "${CONKY_ARGS:-}" ]]; then
    return 1
  fi
  grep -q "$conf" <<< "$CONKY_ARGS" && return 0
  grep -q "$base" <<< "$CONKY_ARGS" && return 0
  return 1
}

load_theme_flags() {
  if ! command -v lua >/dev/null 2>&1; then
    return 0
  fi
  local out
  out="$(CONKY_SUITE_DIR="$SUITE_DIR" lua -e '
    local t = dofile(os.getenv("CONKY_SUITE_DIR") .. "/theme.lua")
    local function get(path, default)
      local v = t
      for seg in string.gmatch(path, "[^%.]+") do
        if type(v) ~= "table" then v = nil break end
        v = v[seg]
      end
      if v == nil then v = default end
      if v == false then return "0" else return "1" end
    end
    print("notes=" .. get("notes.enabled", true))
    print("music=" .. get("music.enabled", true))
    print("station=" .. get("station_model.enabled", true))
    print("baro=" .. get("baro_gauge.enabled", true))
    print("network=" .. get("network.enabled", true))
    print("system=" .. get("system.enabled", true))
    print("metar=" .. get("weather.metar.enabled", true))
    print("taf=" .. get("weather.taf.enabled", true))
    print("advisories=" .. get("weather.advisories.enabled", false))
  ' 2>/dev/null || true)"
  while IFS='=' read -r k v; do
    case "$k" in
      notes) THEME_NOTES="$v" ;;
      music) THEME_MUSIC="$v" ;;
      station) THEME_STATION="$v" ;;
      baro) THEME_BARO="$v" ;;
      network) THEME_NETWORK="$v" ;;
      system) THEME_SYSTEM="$v" ;;
      metar) THEME_METAR="$v" ;;
      taf) THEME_TAF="$v" ;;
      advisories) THEME_ADVISORIES="$v" ;;
    esac
  done <<< "$out"
}

load_sitrep_flags() {
  if ! command -v lua >/dev/null 2>&1; then
    return 0
  fi
  local out
  out="$(CONKY_SUITE_DIR="$SUITE_DIR" lua -e '
    local t = dofile(os.getenv("CONKY_SUITE_DIR") .. "/theme-sitrep.lua")
    local s = t.sitrep or {}
    local function get(tbl, key, default)
      local v = tbl and tbl[key] or nil
      if v == nil then v = default end
      if v == false then return "0" else return "1" end
    end
    print("ap=" .. get(s.ap, "enabled", true))
    print("pfsense=" .. get(s.pfsense, "enabled", true))
  ' 2>/dev/null || true)"
  while IFS='=' read -r k v; do
    case "$k" in
      ap) SITREP_AP="$v" ;;
      pfsense) SITREP_PFSENSE="$v" ;;
    esac
  done <<< "$out"
}

skip_widget() {
  local label="$1" enabled="$2" loaded="$3" theme_file="$4"
  if [[ "$enabled" -eq 0 ]]; then
    say "OK" "$label disabled in $theme_file"
    return 0
  fi
  if [[ "$loaded" -eq 0 ]]; then
    say "OK" "$label widget not loaded"
    return 0
  fi
  return 1
}

printf 'TECH HUD DOCTOR  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

load_theme_flags
load_sitrep_flags
CONKY_ARGS="$(get_conky_args)"
loaded_time=0
loaded_sitrep=0
loaded_pfsense=0
loaded_music=0
loaded_notes=0
loaded_station=0
loaded_baro=0
loaded_network=0
loaded_system=0
widget_loaded "$SUITE_DIR/widgets/time.conky.conf" && loaded_time=1
widget_loaded "$SUITE_DIR/widgets/sitrep.conky.conf" && loaded_sitrep=1
widget_loaded "$SUITE_DIR/widgets/pfsense-conky.conf" && loaded_pfsense=1
widget_loaded "$SUITE_DIR/widgets/music.conky.conf" && loaded_music=1
widget_loaded "$SUITE_DIR/widgets/notes.conky.conf" && loaded_notes=1
widget_loaded "$SUITE_DIR/widgets/station-model.conky.conf" && loaded_station=1
widget_loaded "$SUITE_DIR/widgets/baro-gauge.conky.conf" && loaded_baro=1
widget_loaded "$SUITE_DIR/widgets/network.conky.conf" && loaded_network=1
widget_loaded "$SUITE_DIR/widgets/system.conky.conf" && loaded_system=1

section "Basic"
if [[ -d "$SUITE_DIR" ]]; then
  say "OK" "Suite dir: $SUITE_DIR"
else
  say "FAIL" "Suite dir missing (set CONKY_SUITE_DIR in scripts/conky-env.sh)"
fi
if [[ -d "$CONFIG_DIR" ]]; then
  say "OK" "Config dir: $CONFIG_DIR"
else
  say "FAIL" "Config dir missing ($CONFIG_DIR)" "set CONKY_SUITE_DIR so config/ exists"
fi
if [[ -d "$CACHE_DIR" ]]; then
  say "OK" "Cache dir: $CACHE_DIR"
else
  say "WARN" "Cache dir missing ($CACHE_DIR)" "set CONKY_CACHE_DIR or create the directory"
fi

section "Config"
OWM_ENV="$CONFIG_DIR/owm.env"
OWM_VARS="$CONFIG_DIR/owm.vars"
LYRICS_VARS="$CONFIG_DIR/lyrics.vars"
AP_IPMAP="$CONFIG_DIR/ap_ipmap.csv"

if [[ -f "$OWM_ENV" ]]; then
  owm_key="$(read_kv "$OWM_ENV" "OWM_API_KEY" || true)"
  if [[ -z "$owm_key" || "$owm_key" == "YOUR_OPENWEATHER_API_KEY" ]]; then
    say "FAIL" "config/owm.env OWM_API_KEY missing (copy from config/owm.env.example)"
  else
    say "OK" "config/owm.env"
  fi
else
  say "FAIL" "config/owm.env missing (copy from config/owm.env.example)"
fi

if [[ -f "$OWM_VARS" ]]; then
  lat="$(read_kv "$OWM_VARS" "LAT" || true)"
  lon="$(read_kv "$OWM_VARS" "LON" || true)"
  if [[ -z "$lat" || "$lat" == "YOUR_LAT" ]]; then
    say "FAIL" "config/owm.vars LAT missing/invalid (copy from config/owm.vars.example)"
  elif ! is_float "$lat"; then
    say "FAIL" "config/owm.vars LAT missing/invalid (copy from config/owm.vars.example)"
  else
    say "OK" "config/owm.vars LAT=$lat"
  fi
  if [[ -z "$lon" || "$lon" == "YOUR_LON" ]]; then
    say "FAIL" "config/owm.vars LON missing/invalid (copy from config/owm.vars.example)"
  elif ! is_float "$lon"; then
    say "FAIL" "config/owm.vars LON missing/invalid (copy from config/owm.vars.example)"
  else
    say "OK" "config/owm.vars LON=$lon"
  fi
else
  say "FAIL" "config/owm.vars missing (copy from config/owm.vars.example)"
fi

if [[ -f "$LYRICS_VARS" ]]; then
  say "OK" "config/lyrics.vars"
else
  say "WARN" "config/lyrics.vars missing (copy from config/lyrics.vars.example)"
fi

if [[ -f "$AP_IPMAP" ]]; then
  say "OK" "config/ap_ipmap.csv"
else
  say "WARN" "config/ap_ipmap.csv missing (copy from config/ap_ipmap.csv.example)"
fi

section "Weather"
check_cmds "Weather deps" "install curl/jq" curl jq || true

weather_ok=1
if [[ ! -f "$OWM_ENV" || ! -f "$OWM_VARS" ]]; then
  weather_ok=0
else
  owm_key="$(read_kv "$OWM_ENV" "OWM_API_KEY" || true)"
  lat="$(read_kv "$OWM_VARS" "LAT" || true)"
  lon="$(read_kv "$OWM_VARS" "LON" || true)"
  if [[ -z "$owm_key" || "$owm_key" == "YOUR_OPENWEATHER_API_KEY" ]]; then
    weather_ok=0
  fi
  if [[ -z "$lat" || "$lat" == "YOUR_LAT" ]]; then
    weather_ok=0
  elif ! is_float "$lat"; then
    weather_ok=0
  fi
  if [[ -z "$lon" || "$lon" == "YOUR_LON" ]]; then
    weather_ok=0
  elif ! is_float "$lon"; then
    weather_ok=0
  fi
fi

if [[ "$weather_ok" -eq 1 ]]; then
  missing_msg="$(list_missing_files "$CACHE_DIR" \
    owm_current.json owm_forecast.json owm_days.vars owm_day0_peak.vars owm_fetch.log)"
  if [[ -z "$missing_msg" ]]; then
    say "OK" "Weather cache files present"
  else
    say "WARN" "Weather cache $missing_msg (run scripts/owm_fetch.sh)"
  fi
  if [[ -d "$CACHE_DIR/icons" ]]; then
    say "OK" "Weather icon cache: $CACHE_DIR/icons"
  else
    say "WARN" "Weather icon cache missing ($CACHE_DIR/icons) (run scripts/owm_fc_icons.sh)"
  fi
else
  say "WARN" "Weather config incomplete (see Config section)"
fi

section "Cache"
missing_msg="$(list_missing_files "$CACHE_DIR" events_cache.txt)"
if [[ -z "$missing_msg" ]]; then
  say "OK" "events_cache.txt"
else
  say "WARN" "events_cache.txt $missing_msg (run scripts/event_update.py)"
fi

SEASONAL_CACHE_PATH="$CACHE_DIR/seasonal.vars"
SEASONAL_DEFAULT_PATH="$SEASONAL_CACHE_PATH"
if [[ -f "$OWM_VARS" ]]; then
  seasonal_override="$(read_kv "$OWM_VARS" "SEASONAL_CACHE" || true)"
  if [[ -n "$seasonal_override" ]]; then
    SEASONAL_CACHE_PATH="$seasonal_override"
  fi
fi
if [[ -f "$SEASONAL_CACHE_PATH" ]]; then
  if [[ -s "$SEASONAL_CACHE_PATH" ]]; then
    say "OK" "seasonal cache: $SEASONAL_CACHE_PATH"
  else
    say "WARN" "seasonal cache empty ($SEASONAL_CACHE_PATH) (run scripts/seasonal_update.py)"
  fi
else
  if [[ "$SEASONAL_CACHE_PATH" != "$SEASONAL_DEFAULT_PATH" && -f "$SEASONAL_DEFAULT_PATH" ]]; then
    say "OK" "seasonal cache: $SEASONAL_DEFAULT_PATH"
  else
    say "WARN" "seasonal cache missing ($SEASONAL_CACHE_PATH) (run scripts/seasonal_update.py; check SEASONAL_CACHE in config/owm.vars)"
  fi
fi

check_file "$CACHE_DIR/sky.vars" "sky.vars" "run scripts/sky_update.py" "WARN"

shopt -s nullglob
metar_files=("$CACHE_DIR"/metar_*)
shopt -u nullglob
metar_required=0
if [[ "$THEME_STATION" -eq 1 && "$loaded_station" -eq 1 ]]; then
  metar_required=1
fi
if [[ "$THEME_BARO" -eq 1 && "$loaded_baro" -eq 1 ]]; then
  metar_required=1
fi
if [[ "$THEME_METAR" -eq 1 && "$loaded_time" -eq 1 ]]; then
  metar_required=1
fi

if [[ "$metar_required" -eq 1 ]]; then
  if (( ${#metar_files[@]} > 0 )); then
    say "OK" "METAR cache present"
  else
    metar_action="run scripts/metar_ob.sh"
    if [[ "$THEME_METAR" -eq 0 && "$loaded_station" -eq 0 && "$loaded_baro" -eq 1 ]]; then
      metar_action="set weather.metar.enabled=true in theme.lua or load widgets/station-model.conky.conf; baro gauge needs METAR cache"
    elif [[ "$THEME_METAR" -eq 0 && "$loaded_station" -eq 0 ]]; then
      metar_action="set weather.metar.enabled=true in theme.lua or load widgets/station-model.conky.conf"
    fi
    say "WARN" "METAR cache missing ($metar_action)"
  fi
else
  if [[ "$THEME_METAR" -eq 0 && "$THEME_STATION" -eq 0 && "$THEME_BARO" -eq 0 ]]; then
    say "OK" "METAR disabled in theme.lua"
  else
    say "OK" "METAR widget not loaded"
  fi
fi

if ! skip_widget "Network" "$THEME_NETWORK" "$loaded_network" "theme.lua"; then
  check_file "$CACHE_DIR/wan_ip" "wan_ip" "run scripts/wan_ip.sh" "WARN"
  check_file "$CACHE_DIR/vpn_state" "vpn_state" "run scripts/wan_ip.sh" "WARN"
fi

if ! skip_widget "SITREP AP" "$SITREP_AP" "$loaded_sitrep" "theme-sitrep.lua"; then
  check_dir "$CACHE_DIR/ap" "ap cache dir" "run scripts/ap_status_all_clients.sh or enable SITREP AP"
fi

pfsense_active=0
if [[ "$loaded_pfsense" -eq 1 ]]; then
  pfsense_active=1
fi
if [[ "$loaded_sitrep" -eq 1 && "$SITREP_PFSENSE" -eq 1 ]]; then
  pfsense_active=1
fi
if [[ "$pfsense_active" -eq 0 ]]; then
  if [[ "$loaded_sitrep" -eq 1 && "$SITREP_PFSENSE" -eq 0 ]]; then
    say "OK" "pfSense disabled in theme-sitrep.lua"
  else
    say "OK" "pfSense widget not loaded"
  fi
else
  check_dir "$CACHE_DIR/pfsense" "pfsense cache dir" "run scripts/pf-fetch-basic.sh full or enable pfSense widget"
fi

section "Fonts"
if ! command -v fc-list >/dev/null 2>&1; then
  say "FAIL" "fc-list missing (install fontconfig)"
else
  fc_families="$(fc-list : family 2>/dev/null || true)"
  base_fonts=("Orbitron" "Rajdhani" "Exo 2" "Nimbus Mono PS")
  missing=()
  for f in "${base_fonts[@]}"; do
    if ! grep -qi "$f" <<< "$fc_families"; then
      missing+=("$f")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    say "WARN" "Base fonts missing: ${missing[*]} (run scripts/install-fonts.sh)"
  else
    say "OK" "Base fonts installed"
  fi

  pro_fonts=("Eurostile LT Std Ext Two" "Eurostile LT Std" "Berthold City Light" "Berthold City")
  missing=()
  for f in "${pro_fonts[@]}"; do
    if ! grep -qi "$f" <<< "$fc_families"; then
      missing+=("$f")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    say "WARN" "Commercial fonts missing (optional): ${missing[*]}" "install commercial fonts if you have them"
  else
    say "OK" "Commercial fonts installed"
  fi
fi

section "SSH"
ssh_needed=0
if [[ "$pfsense_active" -eq 1 || ( "$loaded_sitrep" -eq 1 && "$SITREP_AP" -eq 1 ) ]]; then
  ssh_needed=1
fi
if [[ "$ssh_needed" -eq 0 ]]; then
  say "OK" "SSH checks skipped (pfSense/AP disabled or widget not loaded)"
else
  if ! command -v ssh >/dev/null 2>&1; then
    say "FAIL" "ssh missing (install openssh-client)"
  else
    say "OK" "ssh found"
  fi

  GATE="$SCRIPT_DIR/pf-ssh-gate.sh"
  if [[ -x "$GATE" ]]; then
    gate_status="$($GATE status 2>/dev/null || echo "UNKNOWN")"
    if [[ "$gate_status" == OK* ]]; then
      say "OK" "pf-ssh-gate: OK"
    else
      say "WARN" "pf-ssh-gate: $gate_status"
    fi
  else
    say "WARN" "pf-ssh-gate.sh missing" "restore scripts/pf-ssh-gate.sh"
  fi

  SSH_CONFIG="$HOME_DIR/.ssh/config"
  host_pf=0
  pf_hostname=""
  if command -v ssh >/dev/null 2>&1; then
    pf_hostname="$(ssh -G pf 2>/dev/null | awk '$1=="hostname"{print $2; exit}')"
    if [[ -n "$pf_hostname" && "$pf_hostname" != "pf" ]]; then
      host_pf=1
    fi
  fi
  if [[ "$host_pf" -eq 0 ]] && [[ -f "$SSH_CONFIG" ]] \
    && grep -qiE '^[[:space:]]*Host[[:space:]].*([[:space:]]|^)pf([[:space:]]|$)' "$SSH_CONFIG"; then
    host_pf=1
  fi

  if [[ "$host_pf" -eq 1 ]]; then
    say "OK" "SSH host alias 'pf' found"
  else
    say "WARN" "SSH host alias 'pf' not found (~/.ssh/config or Include)" "add Host pf to ~/.ssh/config or an included file"
  fi

  if [[ -x "$GATE" ]] && [[ "$host_pf" -eq 1 ]] && command -v ssh >/dev/null 2>&1; then
    if "$GATE" allow; then
      now="$(date +%s)"
      last=0
      if [[ -f "$SSH_LAST_FILE" ]]; then
        last="$(cat "$SSH_LAST_FILE" 2>/dev/null || echo 0)"
      fi
      if [[ $((now - last)) -ge "$DOCTOR_SSH_TTL" ]]; then
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
          -o ServerAliveInterval=5 -o ServerAliveCountMax=1 -o LogLevel=ERROR pf "true" \
          >/dev/null 2>&1; then
          say "OK" "pfSense SSH probe OK"
        else
          say "WARN" "pfSense SSH probe failed" "verify ssh access to Host pf"
        fi
        mkdir -p "$(dirname "$SSH_LAST_FILE")"
        printf '%s\n' "$now" > "$SSH_LAST_FILE"
      else
        say "OK" "pfSense SSH probe skipped (recent)"
      fi
    else
      say "WARN" "pfSense SSH probe skipped (gate tripped)" "wait or run scripts/pf-ssh-gate.sh reset"
    fi
  else
    say "WARN" "pfSense SSH probe skipped (missing gate or host alias)" "ensure scripts/pf-ssh-gate.sh and Host pf exist"
  fi
fi

section "Music"
if ! skip_widget "Music" "$THEME_MUSIC" "$loaded_music" "theme.lua"; then
  check_cmds "Music deps" "install playerctl pulseaudio-utils" playerctl pactl || true
  if [[ -f "$LYRICS_VARS" ]]; then
    say "OK" "lyrics.vars present"
  else
    say "WARN" "lyrics.vars missing (copy from config/lyrics.vars.example)"
  fi
  check_dir "$CACHE_DIR/cover_dyn" "cover_dyn dir" "start the music widget to populate cover cache"
fi

if (( ${#ACTIONS[@]} > 0 )); then
  section "Actions"
  for a in "${ACTIONS[@]}"; do
    printf ' - %s\n' "$a"
  done
fi
