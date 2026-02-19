#!/usr/bin/env python3
"""Cross-check word translations against DeepL API and save results."""

import json
import sys
import time
import urllib.request
import urllib.parse
import os

DEEPL_KEY = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DEEPL_KEY", "")
WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards/Data/en_es_words.json")
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "deepl_crosscheck.json")
BATCH_SIZE = 40  # DeepL allows up to 50 per request

def translate_batch(texts, auth_key):
    """Translate a batch of English texts to Spanish via DeepL."""
    url = "https://api-free.deepl.com/v2/translate"
    data = urllib.parse.urlencode(
        [("target_lang", "ES"), ("source_lang", "EN")]
        + [("text", t) for t in texts]
    ).encode("utf-8")

    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("Authorization", f"DeepL-Auth-Key {auth_key}")

    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read().decode("utf-8"))
    return [t["text"] for t in result["translations"]]

def normalize(text):
    """Lowercase and strip for comparison."""
    return text.lower().strip().rstrip(".").strip()

def main():
    if not DEEPL_KEY:
        print("Usage: python3 crosscheck_deepl.py <DEEPL_API_KEY>")
        sys.exit(1)

    # Load existing results to allow resuming
    results = []
    done_ids = set()
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            results = json.load(f)
            done_ids = {r["id"] for r in results}
        print(f"  Loaded {len(results)} already-checked words")

    with open(WORDS_FILE, "r", encoding="utf-8") as f:
        deck = json.load(f)

    words = deck["words"]
    remaining = [w for w in words if w["id"] not in done_ids]
    total = len(words)
    print(f"  {total} words total, {len(remaining)} to check")

    # Process in batches
    for i in range(0, len(remaining), BATCH_SIZE):
        batch = remaining[i:i + BATCH_SIZE]
        sources = [w["source"] for w in batch]

        try:
            translations = translate_batch(sources, DEEPL_KEY)
        except Exception as e:
            print(f"\n  ERROR at batch {i}: {e}")
            # Save progress and bail
            with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                json.dump(results, f, indent=2, ensure_ascii=False)
            print(f"  Saved {len(results)} results so far")
            sys.exit(1)

        for word, deepl_text in zip(batch, translations):
            ours = normalize(word["target"])
            theirs = normalize(deepl_text)
            match = ours == theirs

            results.append({
                "id": word["id"],
                "source": word["source"],
                "our_target": word["target"],
                "deepl_target": deepl_text,
                "match": match,
                "article": word.get("article"),
                "partOfSpeech": word.get("partOfSpeech"),
                "category": word.get("category"),
            })

        done_count = len(done_ids) + i + len(batch)
        mismatches = sum(1 for r in results if not r["match"])
        print(f"[{done_count}/{total}] ... {mismatches} mismatches so far")

        # Save after every batch (resume-safe)
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)

        time.sleep(0.1)  # gentle rate limiting

    # Final summary
    mismatches = [r for r in results if not r["match"]]
    print(f"\nDone! {len(results)} words checked.")
    print(f"  Matches: {len(results) - len(mismatches)}")
    print(f"  Mismatches: {len(mismatches)}")
    print(f"  Results saved to: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
