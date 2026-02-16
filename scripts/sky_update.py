#!/usr/bin/env python3
import math, os, subprocess, sys
import ephem

HOME = os.path.expanduser("~")
SUITE_DIR = os.environ.get("CONKY_SUITE_DIR") or os.path.join(HOME, ".config", "conky", "gtex62-tech-hud")
CACHE_DIR = os.environ.get("CONKY_CACHE_DIR") or os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "conky")
OUT  = os.path.join(CACHE_DIR, "sky.vars")

def run_station_latlon():
    """
    Try to reuse your suite's station_latlon.sh if it prints lat/lon.
    Accepts output like:
      "32.9 -96.8"
      "LAT=32.9 LON=-96.8"
      "32.9,-96.8"
    """
    sh = os.path.join(SUITE_DIR, "scripts", "station_latlon.sh")
    if not (os.path.exists(sh) and os.access(sh, os.X_OK)):
        return None

    try:
        out = subprocess.check_output([sh], text=True).strip()
    except Exception:
        return None

    # Extract first two floats from output
    parts = []
    for tok in out.replace(",", " ").replace("=", " ").split():
        try:
            parts.append(float(tok))
        except ValueError:
            pass
    if len(parts) >= 2:
        return parts[0], parts[1]
    return None

def deg(x): return float(x) * 180.0 / math.pi

def az_to_theta(az_deg):
    """
    Map azimuth degrees (0=N,90=E,180=S,270=W) to an "arc theta" where:
      E(90) -> 0,  S(180) -> 90,  W(270) -> 180
    This matches the common horizon-arc convention used in your owm.lua (it can accept *_AZ too).
    """
    t = az_deg - 90.0
    while t < 0: t += 360.0
    while t >= 360: t -= 360.0
    return t

def write_vars(lat, lon):
    obs = ephem.Observer()
    obs.lat = str(lat)
    obs.lon = str(lon)
    obs.elevation = 0
    obs.date = ephem.now()

    # Bodies
    bodies = {
        "MOON": ephem.Moon(),
        "VENUS": ephem.Venus(),
        "MARS": ephem.Mars(),
        "JUPITER": ephem.Jupiter(),
        "SATURN": ephem.Saturn(),
        "MERCURY": ephem.Mercury(),
    }

    lines = []
    lines.append(f"LAT={lat}")
    lines.append(f"LON={lon}")
    import time
    lines.append(f"TS={int(time.time())}")  # lightweight marker; not used by lua

    for name, body in bodies.items():
        body.compute(obs)
        az  = deg(body.az)
        alt = deg(body.alt)
        th  = az_to_theta(az)

        if name == "MOON":
            lines.append(f"MOON_AZ={az:.3f}")
            lines.append(f"MOON_ALT={alt:.3f}")
            lines.append(f"MOON_THETA={th:.3f}")

            # Moon rise/set epoch seconds (UTC), prefer the interval that brackets "now"
            try:
                from datetime import timezone
                now_ts = int(time.time())

                def ts(d):
                    return int(d.datetime().replace(tzinfo=timezone.utc).timestamp())

                def safe(fn):
                    try:
                        return fn(body)
                    except (ephem.AlwaysUpError, ephem.NeverUpError):
                        return None

                prev_rise = safe(obs.previous_rising)
                prev_set = safe(obs.previous_setting)
                next_rise = safe(obs.next_rising)
                next_set = safe(obs.next_setting)

                pr_ts = ts(prev_rise) if prev_rise else None
                ps_ts = ts(prev_set) if prev_set else None
                nr_ts = ts(next_rise) if next_rise else None
                ns_ts = ts(next_set) if next_set else None

                def span_ok(r_ts, s_ts, max_hours=18):
                    return (s_ts is not None and r_ts is not None
                            and 0 < (s_ts - r_ts) <= max_hours * 3600)

                rise_ts = set_ts = None

                # 1) If currently up, prefer [prev_rise, next_set]
                if pr_ts and ns_ts and pr_ts <= now_ts <= ns_ts and span_ok(pr_ts, ns_ts):
                    rise_ts, set_ts = pr_ts, ns_ts

                # 2) Otherwise, if the next interval is sane, use [next_rise, next_set]
                if rise_ts is None and nr_ts and ns_ts and nr_ts < ns_ts and span_ok(nr_ts, ns_ts):
                    rise_ts, set_ts = nr_ts, ns_ts

                # 3) Fallback: previous-day [prev_rise, prev_set] if it brackets now
                if rise_ts is None and pr_ts and ps_ts and pr_ts < ps_ts and pr_ts <= now_ts <= ps_ts and span_ok(pr_ts, ps_ts):
                    rise_ts, set_ts = pr_ts, ps_ts

                if rise_ts is not None and set_ts is not None:
                    lines.append(f"MOON_RISE_TS={rise_ts}")
                    lines.append(f"MOON_SET_TS={set_ts}")
                if ps_ts is not None:
                    lines.append(f"MOON_SET_PREV_TS={ps_ts}")
            except Exception:
                pass
        else:
            # owm.lua can read either *_THETA or *_AZ; we provide both for safety.
            lines.append(f"{name}_AZ={az:.3f}")
            lines.append(f"{name}_ALT={alt:.3f}")
            lines.append(f"{name}_THETA={th:.3f}")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, OUT)

def main():
    # 1) Try your existing station_latlon.sh
    ll = run_station_latlon()

    # 2) Fallback: use environment variables if set
    if ll is None:
        try:
            ll = (float(os.environ["LAT"]), float(os.environ["LON"]))
        except Exception:
            ll = None

    if ll is None:
        print("ERROR: Couldn't determine LAT/LON.")
        print("Fix: ensure scripts/station_latlon.sh outputs lat lon, or run with LAT=.. LON=..")
        sys.exit(2)

    lat, lon = ll
    write_vars(lat, lon)
    print(OUT)

if __name__ == "__main__":
    main()
