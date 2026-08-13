#!/usr/bin/env python3
"""Merge the MIT Kushy strain CSV into Sesh's bundled factual catalog."""

from __future__ import annotations

import csv
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE = "https://raw.githubusercontent.com/kushyapp/cannabis-dataset/master/Dataset/Strains/strains-kushy_api.2017-11-14.csv"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "The SESH." / "strains.json"


def clean(value: str | None) -> str:
    value = (value or "").strip()
    return "" if value.lower() in {"null", "unknown", "unknown breeder", "n/a"} else value


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")


def canonical(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.casefold())


def traits(raw: str | None) -> list[dict[str, str]]:
    seen: set[str] = set()
    values = []
    for part in re.split(r"[,;/|]", clean(raw)):
        name = re.sub(r"\s+", " ", part).strip().title()
        key = name.casefold()
        if name and key not in seen:
            seen.add(key)
            values.append({"name": name})
    return values


def potency(raw: str | None, maximum: float) -> float | None:
    try:
        value = float(clean(raw))
    except ValueError:
        return None
    return round(value, 2) if 0 < value <= maximum else None


def prefer(existing: dict, incoming: dict) -> dict:
    result = dict(existing)
    for key in ("type", "thc", "cbd", "breeder", "lineage", "floweringTime", "openthcID"):
        if not result.get(key) and incoming.get(key):
            result[key] = incoming[key]
    for key in ("effects", "flavors", "terpenes", "aka", "sources"):
        combined = list(result.get(key) or [])
        keys = {json.dumps(item, sort_keys=True).casefold() for item in combined}
        for item in incoming.get(key) or []:
            marker = json.dumps(item, sort_keys=True).casefold()
            if marker not in keys:
                combined.append(item)
                keys.add(marker)
        result[key] = combined
    return result


def main() -> int:
    current = json.loads(OUTPUT.read_text())
    catalog = {canonical(row["name"]): row for row in current if row.get("name")}
    with urllib.request.urlopen(SOURCE, timeout=30) as response:
        rows = csv.DictReader(io.StringIO(response.read().decode("utf-8-sig")))
        for row in rows:
            name = clean(row.get("name"))
            if not name or clean(row.get("status")) == "0":
                continue
            kind = clean(row.get("type")).title()
            if kind not in {"Indica", "Sativa", "Hybrid"}:
                kind = "Unknown"
            incoming = {
                "id": slug(name), "name": name, "type": kind,
                "effects": traits(row.get("effects")),
                "flavors": traits(row.get("flavor")),
                "terpenes": traits(row.get("terpenes")),
                "sources": ["Kushy cannabis-dataset (MIT)"],
            }
            if value := potency(row.get("thc"), 45): incoming["thc"] = value
            if value := potency(row.get("cbd"), 35): incoming["cbd"] = value
            if value := clean(row.get("breeder")): incoming["breeder"] = value
            key = canonical(name)
            catalog[key] = prefer(catalog[key], incoming) if key in catalog else incoming

    output = sorted(catalog.values(), key=lambda row: row["name"].casefold())
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Wrote {len(output):,} normalized strains to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
