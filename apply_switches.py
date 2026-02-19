#!/usr/bin/env python3
"""Apply recommended translation switches to en_es_words.json."""

import json
import os

WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards/Data/en_es_words.json")
RECS_FILE = os.path.join(os.path.dirname(__file__), "final_recommendations.json")

def main():
    with open(RECS_FILE, "r", encoding="utf-8") as f:
        recs = json.load(f)

    switches = {s["id"]: s["recommended"] for s in recs["switches"]}
    print(f"Loaded {len(switches)} switches to apply")

    with open(WORDS_FILE, "r", encoding="utf-8") as f:
        deck = json.load(f)

    applied = 0
    for word in deck["words"]:
        if word["id"] in switches:
            old = word["target"]
            new = switches[word["id"]]
            word["target"] = new
            print(f"  {word['id']}  {word['source']:30s}  {old:20s} -> {new}")
            applied += 1

    # Bump version
    deck["version"] = deck.get("version", 10) + 1

    with open(WORDS_FILE, "w", encoding="utf-8") as f:
        json.dump(deck, f, indent=2, ensure_ascii=False)

    print(f"\nApplied {applied} switches. Version bumped to {deck['version']}.")

if __name__ == "__main__":
    main()
