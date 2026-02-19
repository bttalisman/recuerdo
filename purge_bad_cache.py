#!/usr/bin/env python3
"""Purge cache entries that have bad examples (target word missing from sentence)
and entries for the 79 switched translations."""

import json
import re
import os

WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards/Data/en_es_words.json")
CACHE_FILE = os.path.join(os.path.dirname(__file__), "tatoeba_cache.json")
RECS_FILE = os.path.join(os.path.dirname(__file__), "final_recommendations.json")

def word_in_sentence(target, sentence):
    """Check if the target word (or any meaningful part) appears in the sentence."""
    target_clean = target.lower().split(",")[0].split("(")[0].strip()
    sentence_lower = sentence.lower()
    for part in target_clean.split():
        if len(part) >= 3 and part in sentence_lower:
            return True
    return False

def main():
    deck = json.load(open(WORDS_FILE, "r", encoding="utf-8"))
    cache = json.load(open(CACHE_FILE, "r", encoding="utf-8"))
    recs = json.load(open(RECS_FILE, "r", encoding="utf-8"))

    # Build map of current targets by word id
    target_by_id = {w["id"]: w["target"] for w in deck["words"]}

    # IDs of switched words — always re-fetch
    switched_ids = {s["id"] for s in recs["switches"]}

    purged = 0
    cleaned = 0

    for word_id in list(cache.keys()):
        target = target_by_id.get(word_id, "")

        # Always purge switched words
        if word_id in switched_ids:
            del cache[word_id]
            purged += 1
            continue

        # Filter out bad examples from cache
        examples = cache[word_id]
        if not examples:
            continue

        good = [ex for ex in examples if word_in_sentence(target, ex["es"])]
        if len(good) < len(examples):
            cleaned += len(examples) - len(good)
            if good:
                cache[word_id] = good
            else:
                # No good examples left — purge so it gets re-fetched
                del cache[word_id]
                purged += 1

    json.dump(cache, open(CACHE_FILE, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

    remaining = len([w for w in deck["words"] if w["id"] not in cache])
    print(f"Purged {purged} cache entries entirely (switched + no good examples)")
    print(f"Removed {cleaned} bad individual examples from remaining entries")
    print(f"{remaining} words now need re-fetching")

if __name__ == "__main__":
    main()
