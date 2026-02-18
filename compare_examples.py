#!/usr/bin/env python3
"""
Compare old vs new Tatoeba example selections side by side.
Shows only words where the examples actually changed.

Usage:
    python3 compare_examples.py
"""

import json
import os

OLD_CACHE = os.path.join(os.path.dirname(__file__), "tatoeba_cache_old.json")
NEW_CACHE = os.path.join(os.path.dirname(__file__), "tatoeba_cache.json")
WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards", "Data", "en_es_words.json")


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    old_cache = load_json(OLD_CACHE)
    new_cache = load_json(NEW_CACHE)
    deck = load_json(WORDS_FILE)

    # Build word lookup: id -> {source, target}
    word_lookup = {}
    for w in deck["words"]:
        word_lookup[w["id"]] = {"source": w["source"], "target": w["target"]}

    # Find words that differ
    changed = []
    same = []
    for word_id in new_cache:
        if word_id not in old_cache:
            continue
        old_examples = old_cache[word_id]
        new_examples = new_cache[word_id]
        if old_examples != new_examples:
            changed.append(word_id)
        else:
            same.append(word_id)

    print(f"Re-fetched words where examples CHANGED: {len(changed)}")
    print(f"Re-fetched words where examples stayed SAME: {len(same)}")
    print(f"{'=' * 80}\n")

    for word_id in changed:
        info = word_lookup.get(word_id, {"source": "?", "target": "?"})
        old_ex = old_cache[word_id]
        new_ex = new_cache[word_id]

        print(f"--- {info['target']} ({info['source']}) ---")
        print()

        max_len = max(len(old_ex), len(new_ex))
        for i in range(max_len):
            old = old_ex[i] if i < len(old_ex) else None
            new = new_ex[i] if i < len(new_ex) else None

            if old and new and old == new:
                print(f"  [{i+1}] (unchanged)")
                print(f"       ES: {old['es']}")
                print(f"       EN: {old['en']}")
            else:
                if old:
                    print(f"  [{i+1}] OLD:")
                    print(f"       ES: {old['es']}")
                    print(f"       EN: {old['en']}")
                else:
                    print(f"  [{i+1}] OLD: (none)")

                if new:
                    print(f"      NEW:")
                    print(f"       ES: {new['es']}")
                    print(f"       EN: {new['en']}")
                else:
                    print(f"      NEW: (none)")
            print()

        print()


if __name__ == "__main__":
    main()
