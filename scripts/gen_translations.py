#!/usr/bin/env python3
"""Génère Sources/AmanCheck/Localization/AmanTranslations_<XX>.swift à partir de scripts/translations/<langue>.json.

Usage : scripts/gen_translations.py            (vérifie puis écrit les 16 tables)
        scripts/gen_translations.py --check    (vérifie seulement : clés inconnues, marqueurs {n} manquants)

Chaque JSON est un objet { "texte anglais": "traduction" }. Les marqueurs {0}, {1}… du texte anglais
doivent tous se retrouver dans la traduction (dans n'importe quel ordre).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_strings import all_strings, unique  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_DIR = os.path.join(ROOT, "scripts/translations")
OUT_DIR = os.path.join(ROOT, "Sources/AmanCheck/Localization")

# fichier JSON → (nom de la constante Swift, suffixe du fichier)
LANGUAGES = {
    "zh-Hans": ("zhHans", "ZH_HANS"),
    "zh-Hant": ("zhHant", "ZH_HANT"),
    "ko": ("korean", "KO"),
    "ar": ("arabic", "AR"),
    "pt-BR": ("portuguese", "PT"),
    "es": ("spanish", "ES"),
    "de": ("german", "DE"),
    "it": ("italian", "IT"),
    "ja": ("japanese", "JA"),
    "ru": ("russian", "RU"),
    "tr": ("turkish", "TR"),
    "nl": ("dutch", "NL"),
    "pl": ("polish", "PL"),
    "hi": ("hindi", "HI"),
    "vi": ("vietnamese", "VI"),
    "uk": ("ukrainian", "UK"),
}

# Textes choisis par une condition dans le code (`L(cond ? "a" : "b", …)`) : invisibles pour l'extracteur.
EXTRA_KEYS = ["problem", "problems", "left shift", "right shift", "left command", "right command",
              "left option", "right option"]

PLACEHOLDER = re.compile(r"\{(\d+)\}")


def swift_literal(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\0":
            out.append("\\0")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def check(lang, table, known):
    problems = []
    for en, tr in table.items():
        if en not in known:
            problems.append(f"clé inconnue : {en!r}")
        if not isinstance(tr, str) or not tr.strip():
            problems.append(f"traduction vide : {en!r}")
            continue
        want = set(PLACEHOLDER.findall(en))
        got = set(PLACEHOLDER.findall(tr))
        if got - want:
            problems.append(f"marqueurs inconnus {sorted(got - want)} : {en!r}")
        elif want - got and "--verbose" in sys.argv:
            # Toléré : un marqueur anglais peut être un suffixe de pluriel sans équivalent dans la langue.
            print(f"    note : marqueur {sorted(want - got)} omis dans {lang} : {en!r}")
    missing = [k for k in known if k not in table]
    return problems, missing


def main():
    known = {s["en"] for s in unique(all_strings())} | set(EXTRA_KEYS)
    check_only = "--check" in sys.argv
    status = 0
    for code, (const, suffix) in LANGUAGES.items():
        path = os.path.join(JSON_DIR, f"{code}.json")
        table = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        problems, missing = check(code, table, known)
        print(f"{code}: {len(table)} entrées, {len(missing)} manquantes, {len(problems)} problèmes")
        for p in problems:
            print("    " + p)
            status = 1
        if "--verbose" in sys.argv:
            for m in missing:
                print("    manque : " + json.dumps(m, ensure_ascii=False))
        if check_only:
            continue
        lines = ["import Foundation", "", "// GÉNÉRÉ par scripts/gen_translations.py depuis scripts/translations/%s.json — ne pas modifier." % code,
                 "extension AmanTranslations {", f"    static let {const}: [String: String] = ["]
        for en in sorted(table):
            lines.append(f"        {swift_literal(en)}: {swift_literal(table[en])},")
        if not table:
            lines.append("        :")
        lines += ["    ]", "}", ""]
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, f"AmanTranslations_{suffix}.swift"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    sys.exit(status)


if __name__ == "__main__":
    main()
