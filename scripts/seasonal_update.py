#!/usr/bin/env python3
import os
import sys
import time
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo

import ephem

HOME = os.path.expanduser("~")
SUITE_DIR = os.environ.get("CONKY_SUITE_DIR") or os.path.join(HOME, ".config", "conky", "gtex62-tech-hud")
CACHE_DIR = os.environ.get("CONKY_CACHE_DIR") or os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "conky")
VARS_PATH = os.path.join(SUITE_DIR, "config", "owm.vars")
os.environ.setdefault("CONKY_SUITE_DIR", SUITE_DIR)
os.environ.setdefault("CONKY_CACHE_DIR", CACHE_DIR)


def read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def expand_vars(value):
    return os.path.expanduser(os.path.expandvars(value))


def parse_vars_file(path):
    out = {}
    s = read_file(path)
    if not s:
        return out
    for line in s.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = expand_vars(v.strip())
    return out


def seasonal_cache_path(vars_map):
    cache = vars_map.get("SEASONAL_CACHE")
    if cache:
        return cache
    return os.path.join(CACHE_DIR, "seasonal.vars")


def seasonal_ttl(vars_map):
    try:
        return int(vars_map.get("SEASONAL_TTL", "31536000"))
    except ValueError:
        return 31536000


def is_fresh(path, ttl):
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        return False
    return (time.time() - mtime) < ttl


def to_local_date(ephem_date, tz):
  dt_utc = ephem.Date(ephem_date).datetime().replace(tzinfo=timezone.utc)
  ts = int(dt_utc.timestamp())
  dt_local = datetime.fromtimestamp(ts, tz)
  return dt_local.date().isoformat(), ts


def seasonal_events(year):
    start = ephem.Date(f"{year}/1/1")
    spring = ephem.next_equinox(start)
    summer = ephem.next_solstice(spring)
    autumn = ephem.next_equinox(summer)
    winter = ephem.next_solstice(autumn)
    return {
        "SPRING_EQ": spring,
        "SUMMER_SOL": summer,
        "AUTUMN_EQ": autumn,
        "WINTER_SOL": winter,
    }


def dst_dates(year, tz):
    dst_start = None
    dst_end = None
    prev = None
    for day in range(0, 367):
        dt = datetime(year, 1, 1, 12, tzinfo=tz) + timedelta(days=day)
        if dt.year != year:
            break
        cur = bool(dt.dst() and dt.dst().total_seconds() != 0)
        if prev is None:
            prev = cur
            continue
        if not prev and cur and dst_start is None:
            dst_start = dt.date()
        if prev and not cur and dst_end is None:
            dst_end = dt.date()
        prev = cur
    return dst_start, dst_end


def write_vars(cache_path, year, tz):
    events = seasonal_events(year)
    lines = [f"YEAR={year}"]
    for key, value in events.items():
        date_str, ts = to_local_date(value, tz)
        lines.append(f"{key}_DATE={date_str}")
        lines.append(f"{key}_TS={ts}")
    dst_start, dst_end = dst_dates(year, tz)
    if dst_start:
        dt = datetime(dst_start.year, dst_start.month, dst_start.day, 12, tzinfo=tz)
        lines.append(f"DST_START_DATE={dst_start.isoformat()}")
        lines.append(f"DST_START_TS={int(dt.timestamp())}")
    if dst_end:
        dt = datetime(dst_end.year, dst_end.month, dst_end.day, 12, tzinfo=tz)
        lines.append(f"DST_END_DATE={dst_end.isoformat()}")
        lines.append(f"DST_END_TS={int(dt.timestamp())}")
    lines.append(f"UPDATED_TS={int(time.time())}")

    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    tmp = cache_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, cache_path)


def main():
    force = "--force" in sys.argv or "-f" in sys.argv
    vars_map = parse_vars_file(VARS_PATH)
    cache_path = seasonal_cache_path(vars_map)
    ttl = seasonal_ttl(vars_map)
    tz_name = vars_map.get("TZ")
    if tz_name:
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            tz = datetime.now().astimezone().tzinfo
    else:
        tz = datetime.now().astimezone().tzinfo

    if not force and is_fresh(cache_path, ttl):
        print(cache_path)
        return 0

    year = datetime.now().year
    write_vars(cache_path, year, tz)
    print(cache_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
