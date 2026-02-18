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
RATE_LIMIT_SECONDS = 1.5
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
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            if attempt < retries - 1:
                wait = (attempt + 1) * 3
                print(f"  Retry {attempt + 1} for '{word}' after {wait}s: {e}")
                time.sleep(wait)
            else:
                print(f"  FAILED for '{word}': {e}")
                return None


def score_sentence(text, word):
    """Score a sentence for quality as an example. Higher is better."""
    words_in_sentence = text.split()
    length = len(words_in_sentence)
    score = 0

    # Prefer sentences of 4-20 words
    if 4 <= length <= 20:
        score += 10
    elif 3 <= length <= 25:
        score += 5
    elif length > 30:
        score -= 5

    # Penalize very short sentences (less context)
    if length < 3:
        score -= 10

    # Bonus if the word appears as a whole word (not just substring)
    pattern = r'\b' + re.escape(word.lower()) + r'\b'
    if re.search(pattern, text.lower()):
        score += 5

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
        # Bonus for direct translation
        if eng_texts[0][1]:
            s += 3

        candidates.append({
            "es": spa_text,
            "en": eng_text,
            "_score": s
        })

    # Sort by score descending, take top N
    candidates.sort(key=lambda x: x["_score"], reverse=True)
    examples = []
    for c in candidates[:MAX_EXAMPLES]:
        examples.append({"es": c["es"], "en": c["en"]})
    return examples


def main():
    print("Loading word list...")
    deck = load_json(WORDS_FILE)
    words = deck["words"]
    print(f"  {len(words)} words in deck")

    cache = load_cache()
    print(f"  {len(cache)} words already cached")

    # Determine which words still need fetching
    to_fetch = []
    for w in words:
        word_id = w["id"]
        if word_id not in cache:
            to_fetch.append(w)

    print(f"  {len(to_fetch)} words to fetch\n")

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
