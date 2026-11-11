"""Simulation time. ``t`` is minutes since Day 1 00:00; one tick is one hour."""

from __future__ import annotations

DAY = 1440
TICK = 60
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def day_of(t: int) -> int:
    return t // DAY + 1


def hour_of(t: int) -> int:
    return (t % DAY) // 60


def weekday_of(t: int) -> int:
    return (day_of(t) - 1) % 7


def is_rest_day(t: int) -> bool:
    return weekday_of(t) == 6


def is_dark(t: int) -> bool:
    h = hour_of(t)
    return h >= 20 or h < 6


def at(day: int, hour: int, minute: int = 0) -> int:
    return (day - 1) * DAY + hour * 60 + minute


def fmt(t: int) -> str:
    return f"Day {day_of(t)} {(t % DAY) // 60:02d}:{t % 60:02d}"


def fmt_clock(t: int) -> str:
    return f"{(t % DAY) // 60:02d}:{t % 60:02d}"


def fmt_approx(t: int, rounding: int = 15) -> str:
    r = int(round(t / rounding)) * rounding
    return f"around {fmt_clock(r)} on Day {day_of(r)}"


def fmt_span(start: int, end: int, rounding: int = 15) -> str:
    a = int(round(start / rounding)) * rounding
    b = int(round(end / rounding)) * rounding
    if b <= a:
        return fmt_approx(start, rounding)
    if day_of(a) == day_of(b):
        return f"from about {fmt_clock(a)} to {fmt_clock(b)} on Day {day_of(a)}"
    return f"from about {fmt_clock(a)} on Day {day_of(a)} to {fmt_clock(b)} on Day {day_of(b)}"
