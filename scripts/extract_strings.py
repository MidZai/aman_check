#!/usr/bin/env python3
"""Inventaire des textes `L("English", "Français")` des sources d'Aman Check.

Usage :
    scripts/extract_strings.py                 # liste JSON de tous les textes (modèles)
    scripts/extract_strings.py --missing       # textes anglais absents d'au moins une langue
                                               # (compare avec scripts/translations/*.json)

Les interpolations `\\(expr)` sont remplacées par des marqueurs `{0}`, `{1}`… (numérotés dans
l'ordre d'apparition dans le texte anglais) : c'est le format attendu dans les tables de traduction
(voir AmanTranslations.swift, `templates`).
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["Sources/AmanCheck", "Sources/AmanCore", "Sources/AmanStorageKit"]
TABLE_DIR = os.path.join(ROOT, "scripts/translations")


def parse_string(src, i):
    """src[i] == '"'. Returns (template, exprs, next_index). Interpolations → {n}."""
    assert src[i] == '"'
    i += 1
    out = []
    exprs = []
    while i < len(src):
        c = src[i]
        if c == "\\":
            nxt = src[i + 1]
            if nxt == "(":
                depth = 1
                j = i + 2
                while depth:
                    ch = src[j]
                    if ch == '"':
                        # chaîne imbriquée dans l'interpolation
                        _, _, j = parse_string(src, j)
                        continue
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    j += 1
                exprs.append(src[i + 2:j - 1])
                out.append("{%d}" % (len(exprs) - 1))
                i = j
                continue
            escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}
            out.append(escapes.get(nxt, nxt))
            i += 2
            continue
        if c == '"':
            return "".join(out), exprs, i + 1
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def skip_ws(src, i):
    while i < len(src) and src[i] in " \t\r\n":
        i += 1
    return i


def extract(path):
    src = open(path, encoding="utf-8").read()
    results = []
    for m in re.finditer(r"(?<![A-Za-z0-9_.])L\(", src):
        line_start = src.rfind("\n", 0, m.start()) + 1
        if src[line_start:m.start()].lstrip().startswith("//"):
            continue  # commentaire
        i = skip_ws(src, m.end())
        if i >= len(src) or src[i] != '"':
            continue  # L(.key) ou L(variable)
        try:
            en, en_exprs, i = parse_string(src, i)
            i = skip_ws(src, i)
            if src[i] != ",":
                continue
            i = skip_ws(src, i + 1)
            # Le français peut être une expression (`cond ? "a" : "b"`) : on garde l'anglais seul.
            fr = parse_string(src, i)[0] if src[i] == '"' else None
        except (ValueError, IndexError):
            continue
        line = src.count("\n", 0, m.start()) + 1
        results.append({"en": en, "fr": fr, "exprs": en_exprs,
                        "file": os.path.relpath(path, ROOT), "line": line})
    # Catalogue des mesures : `m(MetricID.x, "English", "Français", …, help: ("English", "Français"))`.
    for m in re.finditer(r"(?:\bm\(MetricID\.\w+,|\bhelp:\s*\()\s*(?=\")", src):
        i = m.end()
        try:
            en, en_exprs, i = parse_string(src, i)
            i = skip_ws(src, i)
            if src[i] != ",":
                continue
            i = skip_ws(src, i + 1)
            fr = parse_string(src, i)[0] if src[i] == '"' else None
        except (ValueError, IndexError):
            continue
        line = src.count("\n", 0, m.start()) + 1
        results.append({"en": en, "fr": fr, "exprs": en_exprs,
                        "file": os.path.relpath(path, ROOT), "line": line})
    return results


def all_strings():
    found = []
    for d in SOURCE_DIRS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".swift"):
                    found.extend(extract(os.path.join(dirpath, f)))
    return found


def unique(found):
    seen = {}
    for s in found:
        seen.setdefault(s["en"], s)
    return list(seen.values())


def main():
    found = unique(all_strings())
    if "--missing" in sys.argv:
        status = 0
        tables = sorted(f for f in os.listdir(TABLE_DIR) if f.endswith(".json")) if os.path.isdir(TABLE_DIR) else []
        for t in tables:
            keys = set(json.load(open(os.path.join(TABLE_DIR, t), encoding="utf-8")))
            missing = [s for s in found if s["en"] not in keys]
            print(f"{t}: {len(keys)} entrées, {len(missing)} manquantes")
            for s in missing:
                print(f"    {s['file']}:{s['line']}  {json.dumps(s['en'], ensure_ascii=False)}")
                status = 1
        sys.exit(status)
    json.dump(found, sys.stdout, ensure_ascii=False, indent=1)
    print(file=sys.stderr)
    print(f"{len(found)} textes uniques, dont {sum(1 for s in found if s['exprs'])} avec valeurs insérées", file=sys.stderr)


if __name__ == "__main__":
    main()
