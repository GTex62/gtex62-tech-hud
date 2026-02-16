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
EXTRA_DEFAULT = os.path.join(SUITE_DIR, "config", "events_extra.txt")
os.environ.setdefault("CONKY_SUITE_DIR", SUITE_DIR)
os.environ.setdefault("CONKY_CACHE_DIR", CACHE_DIR)


def read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def expand_vars(value):
    if value is None:
        return value
    return os.path.expanduser(os.path.expandvars(value))


def parse_vars_file(path):
    out = {}
    s = read_file(path)
    if not s:
        return out
    for line in s.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = expand_vars(v.strip())
    return out


def event_cache_path(vars_map):
    cache = vars_map.get("EVENT_CACHE") or vars_map.get("EVENTS_CACHE")
    if cache:
        return cache
    return os.path.join(CACHE_DIR, "events_cache.txt")


def event_extra_path(vars_map):
    extra = vars_map.get("EVENT_EXTRA")
    if extra:
        return extra
    return EXTRA_DEFAULT


def event_ttl(vars_map):
    try:
        return int(vars_map.get("EVENT_TTL", "86400"))
    except ValueError:
        return 86400


def is_fresh(path, ttl):
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        return False
    return (time.time() - mtime) < ttl


def to_local_date(ephem_date, tz):
    dt_utc = ephem.Date(ephem_date).datetime().replace(tzinfo=timezone.utc)
    dt_local = dt_utc.astimezone(tz)
    return dt_local.date().isoformat()


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


def add_event(store, date_str, name, etype):
    if not date_str or not name:
        return
    key = (date_str, name, etype or "")
    store[key] = True


def seasonal_events(year, tz, store):
    start = ephem.Date(f"{year}/1/1")
    spring = ephem.next_equinox(start)
    summer = ephem.next_solstice(spring)
    autumn = ephem.next_equinox(summer)
    winter = ephem.next_solstice(autumn)
    add_event(store, to_local_date(spring, tz), "Vernal Equinox", "Equinox")
    add_event(store, to_local_date(summer, tz), "Summer Solstice", "Solstice")
    add_event(store, to_local_date(autumn, tz), "Autumnal Equinox", "Equinox")
    add_event(store, to_local_date(winter, tz), "Winter Solstice", "Solstice")


def moon_phase_events(year, tz, store):
    phases = [
        ("New Moon", ephem.next_new_moon),
        ("First Quarter", ephem.next_first_quarter_moon),
        ("Full Moon", ephem.next_full_moon),
        ("Last Quarter", ephem.next_last_quarter_moon),
    ]
    start = ephem.Date(f"{year}/1/1")
    end = ephem.Date(f"{year + 1}/1/1")
    for name, fn in phases:
        cur = start
        while True:
            nxt = fn(cur)
            if nxt >= end:
                break
            add_event(store, to_local_date(nxt, tz), name, "Moon Phase")
            cur = ephem.Date(nxt + (1.0 / 1440.0))


def dst_events(year, tz, store):
    dst_start, dst_end = dst_dates(year, tz)
    if dst_start:
        add_event(store, dst_start.isoformat(), "DST Start", "DST")
    if dst_end:
        add_event(store, dst_end.isoformat(), "DST End", "DST")


def extra_events(path, store):
    s = read_file(path)
    if not s:
        return
    for line in s.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 2:
            continue
        date_str = parts[0]
        name = parts[1]
        etype = parts[2] if len(parts) > 2 else ""
        if len(date_str) != 10 or date_str[4] != "-" or date_str[7] != "-":
            continue
        add_event(store, date_str, name, etype)


def main():
    force = "--force" in sys.argv or "-f" in sys.argv
    vars_map = parse_vars_file(VARS_PATH)
    cache_path = event_cache_path(vars_map)
    ttl = event_ttl(vars_map)
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

    now = datetime.now(tz)
    years = [now.year - 1, now.year, now.year + 1]

    store = {}
    for y in years:
        seasonal_events(y, tz, store)
        moon_phase_events(y, tz, store)
        dst_events(y, tz, store)

    extra_path = event_extra_path(vars_map)
    extra_events(extra_path, store)

    events = sorted(store.keys(), key=lambda k: (k[0], k[1], k[2]))

    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    tmp = cache_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for date_str, name, etype in events:
            if etype:
                f.write(f"{date_str}|{name}|{etype}\n")
            else:
                f.write(f"{date_str}|{name}\n")
    os.replace(tmp, cache_path)
    print(cache_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
