#!/usr/bin/env python3
"""
Fetch example sentences from Tatoeba.org for each word in en_es_words.json.
Results are cached incrementally so the script can be resumed if interrupted.

Usage:
    python3 fetch_tatoeba_examples.py

Requires no external dependencies (uses urllib).
"""

import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error

WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards", "Data", "en_es_words.json")
CACHE_FILE = os.path.join(os.path.dirname(__file__), "tatoeba_cache.json")
API_BASE = "https://tatoeba.org/api_v0/search"
RATE_LIMIT_SECONDS = 3
MAX_EXAMPLES = 3
MAX_API_RESULTS = 20  # request up to 20 sentences per word


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_cache():
    if os.path.exists(CACHE_FILE):
        return load_json(CACHE_FILE)
    return {}


def save_cache(cache):
    save_json(CACHE_FILE, cache)


def fetch_tatoeba(word, retries=3):
    """Query Tatoeba API for Spanish sentences containing `word` with English translations."""
    params = urllib.parse.urlencode({
        "from": "spa",
        "to": "eng",
        "query": word,
        "limit": MAX_API_RESULTS,
        "sort": "relevance",
    })
    url = f"{API_BASE}?{params}"

    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "FlashCardApp/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
                ConnectionResetError, OSError) as e:
            if attempt < retries - 1:
                wait = (attempt + 1) * 10
                print(f"  Retry {attempt + 1} for '{word}' after {wait}s: {e}")
                time.sleep(wait)
            else:
                print(f"  FAILED for '{word}': {e}")
                return None


def score_sentence(text, word):
    """Score a sentence for quality as an example. Higher is better.
    Returns None to reject a sentence entirely."""
    words_in_sentence = text.split()
    length = len(words_in_sentence)

    # Hard floor: skip 1-2 word sentences (filler like "Cociné.", "Llama.")
    if length < 3:
        return None

    # Reject truncated sentences
    if '...' in text or '…' in text:
        return None

    score = 0

    # Prefer sentences of 4-20 words
    if 4 <= length <= 20:
        score += 10
    elif length == 3:
        score += 3
    elif length <= 25:
        score += 5
    elif length > 30:
        score -= 5

    # HARD REQUIREMENT: sentence must contain the target word
    pattern = r'\b' + re.escape(word.lower()) + r'\b'
    if re.search(pattern, text.lower()):
        score += 20
    else:
        # Also try matching without word boundaries (for Spanish conjugations)
        if word.lower() in text.lower():
            score += 10
        else:
            return None  # reject entirely

    # Penalize sentences with unusual characters or likely metadata
    if any(c in text for c in ['[', ']', '{', '}', '<', '>']):
        score -= 10

    # Prefer sentences starting with a capital letter (proper sentences)
    if text[0].isupper():
        score += 2

    # Prefer sentences ending with punctuation
    if text.rstrip()[-1] in '.!?':
        score += 2

    return score


def extract_examples(api_response, target_word):
    """Extract and rank Spanish-English sentence pairs from API response."""
    if not api_response or "results" not in api_response:
        return []

    candidates = []
    seen_spanish = set()

    for result in api_response["results"]:
        spa_text = result.get("text", "").strip()
        if not spa_text or spa_text in seen_spanish:
            continue
        seen_spanish.add(spa_text)

        # Find English translations
        eng_texts = []
        for translation_group in result.get("translations", []):
            if isinstance(translation_group, list):
                for t in translation_group:
                    if isinstance(t, dict) and t.get("lang") == "eng":
                        eng_text = t.get("text", "").strip()
                        if eng_text:
                            eng_texts.append((eng_text, t.get("isDirect", False)))
            elif isinstance(translation_group, dict) and translation_group.get("lang") == "eng":
                eng_text = translation_group.get("text", "").strip()
                if eng_text:
                    eng_texts.append((eng_text, translation_group.get("isDirect", False)))

        if not eng_texts:
            continue

        # Prefer direct translations
        eng_texts.sort(key=lambda x: (not x[1], len(x[0])))
        eng_text = eng_texts[0][0]

        s = score_sentence(spa_text, target_word)
        if s is None:
            continue  # rejected by hard floor (too short)

        # Bonus for direct translation
        if eng_texts[0][1]:
            s += 3
        # Bonus for having audio (indicates vetted, higher-quality sentence)
        if result.get("audios"):
            s += 5
        # Bonus for community-verified correctness
        correctness = result.get("correctness", 0) or 0
        if correctness > 0:
            s += correctness * 8

        candidates.append({
            "es": spa_text,
            "en": eng_text,
            "_score": s
        })

    # Sort by score descending, take top N (only positive scores)
    candidates.sort(key=lambda x: x["_score"], reverse=True)
    examples = []
    for c in candidates[:MAX_EXAMPLES]:
        if c["_score"] > 0:
            examples.append({"es": c["es"], "en": c["en"]})
    return examples


def parse_args():
    import argparse
    parser = argparse.ArgumentParser(description="Fetch Tatoeba examples for flashcard words.")
    parser.add_argument("--sample", type=int, metavar="N",
                        help="Re-fetch only N random words (clears them from cache first)")
    parser.add_argument("--range", metavar="START:END",
                        help="Re-fetch word indices START to END, e.g. 0:50")
    parser.add_argument("--refetch-all", action="store_true",
                        help="Clear entire cache and re-fetch everything")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be fetched without actually calling the API")
    parser.add_argument("--no-merge", action="store_true",
                        help="Fetch only, don't merge into en_es_words.json")
    return parser.parse_args()


def main():
    args = parse_args()

    print("Loading word list...")
    deck = load_json(WORDS_FILE)
    words = deck["words"]
    print(f"  {len(words)} words in deck")

    cache = load_cache()
    print(f"  {len(cache)} words already cached")

    # Determine which words to fetch
    if args.refetch_all:
        print("  Clearing entire cache...")
        cache = {}
        to_fetch = list(words)
    elif args.sample:
        import random
        n = min(args.sample, len(words))
        to_fetch = random.sample(words, n)
        for w in to_fetch:
            cache.pop(w["id"], None)
        print(f"  Re-fetching {n} random words")
    elif args.range:
        start, end = args.range.split(":")
        start, end = int(start), int(end)
        to_fetch = words[start:end]
        for w in to_fetch:
            cache.pop(w["id"], None)
        print(f"  Re-fetching words [{start}:{end}] ({len(to_fetch)} words)")
    else:
        to_fetch = [w for w in words if w["id"] not in cache]

    print(f"  {len(to_fetch)} words to fetch\n")

    if args.dry_run:
        for i, w in enumerate(to_fetch[:20]):
            print(f"  Would fetch: {w['target']} ({w['source']})")
        if len(to_fetch) > 20:
            print(f"  ... and {len(to_fetch) - 20} more")
        return

    if not to_fetch:
        print("All words cached. Merging into JSON...")
    else:
        for i, w in enumerate(to_fetch):
            word_id = w["id"]
            target = w["target"]
            source = w["source"]

            print(f"[{i+1}/{len(to_fetch)}] {target} ({source})...", end=" ", flush=True)

            response = fetch_tatoeba(target)
            examples = extract_examples(response, target)

            cache[word_id] = examples
            print(f"{len(examples)} examples")

            # Save cache every 10 words
            if (i + 1) % 10 == 0:
                save_cache(cache)

            # Rate limit
            if i < len(to_fetch) - 1:
                time.sleep(RATE_LIMIT_SECONDS)

        save_cache(cache)
        print(f"\nDone fetching. {len(cache)} words cached total.")

    if args.no_merge:
        print("\nSkipping merge (--no-merge).")
        return

    # Merge examples into the word list
    print("\nMerging examples into en_es_words.json...")
    words_with_examples = 0
    total_examples = 0

    for w in deck["words"]:
        examples = cache.get(w["id"], [])
        w["examples"] = examples
        if examples:
            words_with_examples += 1
            total_examples += len(examples)

    # Bump version
    deck["version"] = deck.get("version", 3) + 1

    save_json(WORDS_FILE, deck)
    print(f"  {words_with_examples}/{len(words)} words have examples")
    print(f"  {total_examples} total example sentences")
    print(f"  JSON version bumped to {deck['version']}")
    print("\nDone! You can delete tatoeba_cache.json if you want.")


if __name__ == "__main__":
    main()
