"""The player's notebook: only what the player has discovered, never the truth."""

from __future__ import annotations

MARKS = ("confirmed", "disputed", "uncertain", "inference")


class Notebook:
    def __init__(self, state: dict):
        self.state = state
        state.setdefault("entries", [])
        state.setdefault("counters", {})
        state.setdefault("by_ref", {})

    def _next(self, prefix: str) -> str:
        n = self.state["counters"].get(prefix, 0) + 1
        self.state["counters"][prefix] = n
        return f"{prefix}{n}"

    def record(self, prefix: str, ref: str | None, text: str, source: str, time: int | None = None,
               speaker: str | None = None) -> str:
        """Add an entry (or return the existing one for the same reference)."""
        if ref is not None and ref in self.state["by_ref"]:
            return self.state["by_ref"][ref]
        eid = self._next(prefix)
        self.state["entries"].append({"id": eid, "ref": ref, "text": text, "source": source, "time": time,
                                      "speaker": speaker, "mark": None})
        if ref is not None:
            self.state["by_ref"][ref] = eid
        return eid

    def get(self, eid: str) -> dict | None:
        for e in self.state["entries"]:
            if e["id"].lower() == eid.lower():
                return e
        return None

    def mark(self, eid: str, mark: str) -> bool:
        e = self.get(eid)
        if e is None or mark not in MARKS:
            return False
        e["mark"] = mark
        return True

    def entries(self) -> list[dict]:
        return list(self.state["entries"])
