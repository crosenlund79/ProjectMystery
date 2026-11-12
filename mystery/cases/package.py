"""Versioned, self-contained case packages for the Godot game (and any other front end).

A package is one JSON file (extension ``.mcase``) holding:

* ``investigation`` – the player-safe view, exactly as exported for the Python game;
* ``sealed_truth``  – the developer truth, sealed so that it cannot be read by accident;
* ``summary``/``generator`` – spoiler-free metadata and the seed/versions needed to
  regenerate the case from the simulation.

The seal (``sha256-ctr-xor/1``) XORs the truth JSON with a SHA-256 counter-mode keystream
derived from a published salt and the case id, then base64-encodes it. It is NOT secret
cryptography: anyone with the source can open it. Its job is to keep the truth out of sight
(menus, logs, casual file browsing) until the player has concluded the case, and its
checksums make tampering or corruption detectable. See docs/case-format.md.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re

from mystery.diagnostics.integrity import check_spoiler_boundary
from mystery.investigate.dialogue import BASE_TOPICS

FORMAT = "project-mystery-case"
FORMAT_VERSION = 1
SUPPORTED_VERSIONS = (1,)
SEAL_SCHEME = "sha256-ctr-xor/1"
SEAL_SALT = "project-mystery case seal v1"
EXTENSION = ".mcase"

DIFFICULTY = {"obvious": "gentle", "playable": "standard", "ambiguous": "hard", "unsolvable": "very hard"}
SEASONS = {"normal": "An ordinary season", "scarcity": "A lean season", "crisis": "Hard times",
           "tension": "A troubled season"}
STYLES = ("nervous", "smooth")
SOURCES = ("self", "saw", "heard", "told", "inferred")


# ----------------------------------------------------------------------------- seal
def _keystream(case_id: str, n: int) -> bytes:
    out = bytearray()
    counter = 0
    while len(out) < n:
        out += hashlib.sha256(f"{SEAL_SALT}|{case_id}|{counter}".encode("utf-8")).digest()
        counter += 1
    return bytes(out[:n])


def canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def seal(truth: dict, case_id: str) -> dict:
    plain = canonical(truth)
    cipher = bytes(a ^ b for a, b in zip(plain, _keystream(case_id, len(plain))))
    data = base64.b64encode(cipher).decode("ascii")
    return {"scheme": SEAL_SCHEME, "length": len(plain), "plain_sha256": hashlib.sha256(plain).hexdigest(),
            "data_sha256": hashlib.sha256(data.encode("ascii")).hexdigest(), "data": data}


def unseal(sealed: dict, case_id: str) -> dict:
    if sealed.get("scheme") != SEAL_SCHEME:
        raise ValueError(f"unknown seal scheme {sealed.get('scheme')!r}")
    if hashlib.sha256(sealed["data"].encode("ascii")).hexdigest() != sealed["data_sha256"]:
        raise ValueError("sealed truth is corrupted (data checksum mismatch)")
    cipher = base64.b64decode(sealed["data"])
    plain = bytes(a ^ b for a, b in zip(cipher, _keystream(case_id, len(cipher))))
    if len(plain) != sealed["length"] or hashlib.sha256(plain).hexdigest() != sealed["plain_sha256"]:
        raise ValueError("sealed truth does not match its checksum")
    return json.loads(plain.decode("ascii"))


# ----------------------------------------------------------------------------- per-item relevance seals
# Hobby Detective checks open one item's verdict at a time, without opening the truth. Each verdict is
# sealed on its own: "<verdict>|<reason>" padded to a fixed length, XORed with SHA-256 of the case id
# and the item's id. Same spirit as the truth seal: a spoiler guard, not security.
REL_SCHEME = "sha256-xor-item/1"
REL_SALT = "project-mystery relevance v1"
REL_WIDTH = 24
REL_VALUES = ("connected|web", "unrelated|outside", "uncertain|where_when", "uncertain|untraced")


def _item_key(case_id: str, ref: str) -> bytes:
    return hashlib.sha256(f"{REL_SALT}|{case_id}|{ref}".encode("utf-8")).digest()[:REL_WIDTH]


def seal_item(value: str, case_id: str, ref: str) -> str:
    plain = value.ljust(REL_WIDTH).encode("ascii")
    return base64.b64encode(bytes(a ^ b for a, b in zip(plain, _item_key(case_id, ref)))).decode("ascii")


def unseal_item(data: str, case_id: str, ref: str) -> str:
    cipher = base64.b64decode(data)
    return bytes(a ^ b for a, b in zip(cipher, _item_key(case_id, ref))).decode("ascii", "replace").rstrip()


def seal_relevance(relevance: dict, case_id: str) -> dict:
    return {"scheme": REL_SCHEME,
            "items": {ref: seal_item(f"{v['verdict']}|{v['reason']}", case_id, ref)
                      for ref, v in sorted(relevance.items())}}


# ----------------------------------------------------------------------------- build
def build_package(case: dict) -> dict:
    inv, truth = case["investigation"], case["truth"]
    cfg = truth["config"]
    return {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "case_id": inv["case_id"],
        "generator": {
            "tool": "mystery (Python)", "sim_version": cfg["sim_version"], "config_version": cfg["config_version"],
            "seed": cfg["seed"], "profile": cfg["profile"], "days": cfg["days"], "residents": cfg["residents"],
            "incident": truth["incident"]["id"], "event_log_digest": truth["event_log_digest"],
        },
        "summary": {
            "title": inv["hook"]["title"], "town": inv["town"], "start_label": inv["start_label"],
            "season": SEASONS.get(cfg["profile"], cfg["profile"]),
            "difficulty": DIFFICULTY[case["suitability"]["verdict"]],
        },
        "investigation": inv,
        "sealed_truth": seal(truth, inv["case_id"]),
        "relevance": seal_relevance(truth.get("relevance", {}), inv["case_id"]),
    }


def write_package(pkg: dict, out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, pkg["case_id"] + EXTENSION)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(pkg, sort_keys=True, indent=1, ensure_ascii=True))
        f.write("\n")
    return path


def read_package(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def unpack_to_case_dir(pkg: dict, out_dir: str) -> str:
    """Write investigation.json + truth.json so the Python game and tools can open the package."""
    path = os.path.join(out_dir, pkg["case_id"])
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "investigation.json"), "w", encoding="utf-8") as f:
        json.dump(pkg["investigation"], f, indent=1, sort_keys=True)
    with open(os.path.join(path, "truth.json"), "w", encoding="utf-8") as f:
        json.dump(unseal(pkg["sealed_truth"], pkg["case_id"]), f, indent=1, sort_keys=True)
    return path


# ----------------------------------------------------------------------------- validation
def _is_int(x) -> bool:
    return isinstance(x, int) and not isinstance(x, bool)


def validate_package(pkg) -> list[str]:
    """Every rule here is mirrored by the Godot loader (godot/scripts/core/case_format.gd)."""
    p: list[str] = []

    def need(obj, key, kind, where):
        if not isinstance(obj, dict) or key not in obj:
            p.append(f"{where}: missing '{key}'")
            return None
        v = obj[key]
        ok = {"str": isinstance(v, str), "int": _is_int(v), "bool": isinstance(v, bool),
              "list": isinstance(v, list), "dict": isinstance(v, dict),
              "int?": v is None or _is_int(v), "str?": v is None or isinstance(v, str)}[kind]
        if not ok:
            p.append(f"{where}: '{key}' should be {kind}")
            return None
        return v

    if not isinstance(pkg, dict):
        return ["package is not a JSON object"]
    if pkg.get("format") != FORMAT:
        return [f"not a Project Mystery case (format {pkg.get('format')!r})"]
    version = pkg.get("format_version")
    if version not in SUPPORTED_VERSIONS:
        return [f"unsupported case format version {version!r} (this build reads {SUPPORTED_VERSIONS})"]
    case_id = need(pkg, "case_id", "str", "package")
    for k in ("title", "town", "start_label", "season", "difficulty"):
        need(pkg.get("summary"), k, "str", "summary")
    for k in ("sim_version", "config_version", "profile"):
        need(pkg.get("generator"), k, "str", "generator")
    for k in ("seed", "days", "residents"):
        need(pkg.get("generator"), k, "int", "generator")
    sealed = need(pkg, "sealed_truth", "dict", "package")
    if sealed is not None:
        if sealed.get("scheme") != SEAL_SCHEME:
            p.append(f"sealed_truth: unknown scheme {sealed.get('scheme')!r}")
        for k in ("data", "data_sha256", "plain_sha256"):
            need(sealed, k, "str", "sealed_truth")
        need(sealed, "length", "int", "sealed_truth")
        if isinstance(sealed.get("data"), str) and \
                hashlib.sha256(sealed["data"].encode("ascii")).hexdigest() != sealed.get("data_sha256"):
            p.append("sealed_truth: data checksum mismatch (corrupted or edited)")
    rel = pkg.get("relevance")
    if rel is not None:
        # optional: per-item sealed verdicts for Hobby Detective checks
        if not isinstance(rel, dict) or rel.get("scheme") != REL_SCHEME or not isinstance(rel.get("items"), dict):
            p.append("relevance: unknown scheme or malformed")
        elif isinstance(case_id, str):
            for ref, data in rel["items"].items():
                try:
                    ok = unseal_item(data, case_id, ref) in REL_VALUES
                except (ValueError, TypeError):
                    ok = False
                if not ok:
                    p.append(f"relevance: item {ref!r} does not open")
                    break
    inv = need(pkg, "investigation", "dict", "package")
    if inv is None:
        return p
    p += [f"spoiler boundary: {x}" for x in check_spoiler_boundary(inv)]
    if inv.get("case_id") != case_id:
        p.append("investigation.case_id does not match the package case_id")
    for k in ("schema", "case_id", "town", "start_label", "player_role"):
        need(inv, k, "str", "investigation")
    need(inv, "start_time", "int", "investigation")
    need(inv, "hint_credits", "int", "investigation")
    hook = need(inv, "hook", "dict", "investigation")
    if hook is not None:
        for k in ("title", "text", "kind", "place", "window_label", "discovered_by"):
            need(hook, k, "str", "hook")
        w = need(hook, "window", "list", "hook")
        if w is not None and (len(w) != 2 or not all(_is_int(x) for x in w)):
            p.append("hook: window must be two integer times")
    residents = need(inv, "residents", "list", "investigation") or []
    rids = set()
    for i, r in enumerate(residents):
        for k in ("id", "name", "first", "occupation", "age_group", "household", "home", "condition"):
            need(r, k, "str", f"residents[{i}]")
        if isinstance(r, dict) and isinstance(r.get("id"), str):
            rids.add(r["id"])
    places = need(inv, "places", "list", "investigation") or []
    pids = set()
    for i, pl in enumerate(places):
        for k in ("id", "name", "kind", "reply"):
            need(pl, k, "str", f"places[{i}]")
        need(pl, "allowed", "bool", f"places[{i}]")
        for o in need(pl, "owners", "list", f"places[{i}]") or []:
            if o not in rids:
                p.append(f"places[{i}]: unknown owner {o!r}")
        for j, tr in enumerate(need(pl, "traces", "list", f"places[{i}]") or []):
            need(tr, "id", "str", f"places[{i}].traces[{j}]")
            need(tr, "description", "str", f"places[{i}].traces[{j}]")
        if isinstance(pl, dict) and isinstance(pl.get("id"), str):
            pids.add(pl["id"])
    if hook is not None and hook.get("place") not in pids:
        p.append("hook: place is not a known place")
    for i, r in enumerate(residents):
        # optional (schema 0.2): where the resident can be found during the investigation
        if isinstance(r, dict) and r.get("now_at") is not None and r.get("now_at") not in pids:
            p.append(f"residents[{i}]: now_at is not a known place")
    for i, v in enumerate(need(inv, "vehicles", "list", "investigation") or []):
        for k in ("id", "name", "kind", "household", "location", "reply"):
            need(v, k, "str", f"vehicles[{i}]")
        need(v, "allowed", "bool", f"vehicles[{i}]")
        need(v, "traces", "list", f"vehicles[{i}]")
        if isinstance(v, dict) and v.get("location") not in pids:
            p.append(f"vehicles[{i}]: parked at an unknown place")
    for key, b in (need(inv, "records", "dict", "investigation") or {}).items():
        for k in ("title", "place", "reply"):
            need(b, k, "str", f"records.{key}")
        need(b, "allowed", "bool", f"records.{key}")
        for j, e in enumerate(need(b, "entries", "list", f"records.{key}") or []):
            need(e, "id", "str", f"records.{key}[{j}]")
            need(e, "time", "int", f"records.{key}[{j}]")
            need(e, "text", "str", f"records.{key}[{j}]")
        if isinstance(b, dict) and b.get("place") not in pids:
            p.append(f"records.{key}: kept at an unknown place")
    valid_topics = {t for t, _ in BASE_TOPICS} | {f"person:{r}" for r in rids} | {"other"}
    keys = set()
    for rid, t in (need(inv, "testimony", "dict", "investigation") or {}).items():
        where = f"testimony.{rid}"
        if rid not in rids:
            p.append(f"{where}: not a resident")
        need(t, "goodwill", "int", where)
        if isinstance(t, dict) and t.get("style") not in STYLES:
            p.append(f"{where}: style must be one of {STYLES}")
        for tp in need(t, "evasive_topics", "list", where) or []:
            if tp not in valid_topics:
                p.append(f"{where}: unknown evasive topic {tp!r}")
        for j, it in enumerate(need(t, "items", "list", where) or []):
            w = f"{where}.items[{j}]"
            k = need(it, "key", "str", w)
            if k in keys:
                p.append(f"{w}: duplicate key {k}")
            keys.add(k)
            need(it, "text", "str", w)
            need(it, "guarded", "bool", w)
            need(it, "time", "int?", w)
            need(it, "place", "str?", w)
            if isinstance(it, dict) and it.get("source") not in SOURCES:
                p.append(f"{w}: unknown source {it.get('source')!r}")
            for tp in need(it, "topics", "list", w) or []:
                if tp not in valid_topics:
                    p.append(f"{w}: unknown topic {tp!r}")
            for a in need(it, "about", "list", w) or []:
                if a not in rids:
                    p.append(f"{w}: about unknown resident {a!r}")
            for f in need(it, "facts", "list", w) or []:
                if not isinstance(f, dict) or f.get("who") not in rids or f.get("place") not in pids \
                        or not _is_int(f.get("from")) or not _is_int(f.get("to")) or f["from"] > f["to"]:
                    p.append(f"{w}: malformed fact {f!r}")
            if isinstance(it, dict) and "group" in it:
                g = it["group"]
                if not isinstance(g, dict) or "{names}" not in str(g.get("template")) or not g.get("id"):
                    p.append(f"{w}: malformed group")
    opts = need(inv, "theory_options", "dict", "investigation") or {}
    for kind in ("mechanisms", "motives"):
        for j, m in enumerate(need(opts, kind, "list", "theory_options") or []):
            need(m, "id", "str", f"theory_options.{kind}[{j}]")
            need(m, "label", "str", f"theory_options.{kind}[{j}]")
    for j, h in enumerate(need(inv, "hints", "list", "investigation") or []):
        need(h, "tier", "int", f"hints[{j}]")
        need(h, "cost", "int", f"hints[{j}]")
        need(h, "text", "str", f"hints[{j}]")
    if not p and re.search(r"\bE\d{6}\b|\bB\d{6}\b", json.dumps(pkg["summary"])):
        p.append("summary: contains internal ids")
    return p


def library_index(entries: list[dict]) -> dict:
    return {"format": "project-mystery-library", "format_version": 1, "cases": entries}
