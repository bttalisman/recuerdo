#!/usr/bin/env python3
"""Filter DeepL crosscheck mismatches to surface likely real problems.

Filters out:
- Synonyms (shared root/stem of 4+ chars)
- Reflexive variants (e.g. "pasar" vs "pasarse")
- Infinitive prefixes (e.g. "ver" vs "véase", "to X" vs "X")
- Minor accent/spelling differences
- One translation contains the other

What remains: translations that are genuinely different and worth reviewing.
"""

import json
import unicodedata
import os

INPUT = os.path.join(os.path.dirname(__file__), "deepl_crosscheck.json")
OUTPUT = os.path.join(os.path.dirname(__file__), "mismatches_to_review.json")


def strip_accents(s):
    """Remove accent marks for comparison."""
    return "".join(
        c for c in unicodedata.normalize("NFD", s)
        if unicodedata.category(c) != "Mn"
    )


def clean(s):
    """Normalize for comparison."""
    s = s.lower().strip()
    # Strip leading "to " (English infinitive marker leaking into Spanish)
    if s.startswith("to "):
        s = s[3:]
    # Strip reflexive "(se)" and "se" suffixes
    s = s.replace("(se)", "").replace("(r)", "").strip()
    return s


def shared_prefix_len(a, b):
    n = 0
    for x, y in zip(a, b):
        if x == y:
            n += 1
        else:
            break
    return n


def is_trivial_mismatch(ours, theirs):
    """Return True if the mismatch is probably just a synonym/variant."""
    o = clean(ours)
    t = clean(theirs)
    o_plain = strip_accents(o)
    t_plain = strip_accents(t)

    # Identical after normalization
    if o_plain == t_plain:
        return True

    # One contains the other (e.g. "dentro de" vs "en dentro de")
    if o_plain in t_plain or t_plain in o_plain:
        return True

    # Shared stem of 4+ chars (covers conjugation variants, reflexives)
    if shared_prefix_len(o_plain, t_plain) >= 4:
        return True

    # Both are single words with same first 3 chars (likely conjugation)
    if " " not in o_plain and " " not in t_plain:
        if shared_prefix_len(o_plain, t_plain) >= 3 and abs(len(o_plain) - len(t_plain)) <= 3:
            return True

    # One is a reflexive form of the other
    for suffix in ["se", "rse", "arse", "erse", "irse"]:
        if o_plain + suffix == t_plain or t_plain + suffix == o_plain:
            return True
        if o_plain.rstrip("r") + suffix == t_plain or t_plain.rstrip("r") + suffix == o_plain:
            return True

    # Multi-word: check if any word in ours appears in theirs
    o_words = set(o_plain.split())
    t_words = set(t_plain.split())
    if o_words & t_words:
        return True

    return False


def main():
    with open(INPUT, "r", encoding="utf-8") as f:
        results = json.load(f)

    mismatches = [r for r in results if not r["match"]]
    print(f"Total mismatches: {len(mismatches)}")

    suspicious = []
    trivial = []
    for r in mismatches:
        if is_trivial_mismatch(r["our_target"], r["deepl_target"]):
            trivial.append(r)
        else:
            suspicious.append(r)

    print(f"Filtered out {len(trivial)} likely synonyms/variants")
    print(f"Remaining to review: {len(suspicious)}")

    # Sort by category for easier review
    suspicious.sort(key=lambda r: (r.get("category") or "", r["source"]))

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(suspicious, f, indent=2, ensure_ascii=False)

    print(f"\nSaved to: {OUTPUT}")
    print(f"\nSample of flagged mismatches:")
    for r in suspicious[:15]:
        print(f"  {r['source']:25s}  ours: {r['our_target']:20s}  deepl: {r['deepl_target']}")


if __name__ == "__main__":
    main()
