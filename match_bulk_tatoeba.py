#!/usr/bin/env python3
"""Match flashcard words against the Tatoeba bulk download for example sentences.

Uses local TSV files (no API calls) to find Spanish sentences containing each
target word, paired with their English translations. Much faster and more
complete than the API approach.

Usage:
    python3 match_bulk_tatoeba.py
"""

import json
import os
import re
import csv
from collections import defaultdict

WORDS_FILE = os.path.join(os.path.dirname(__file__), "flashCards", "Data", "en_es_words.json")
CACHE_FILE = os.path.join(os.path.dirname(__file__), "tatoeba_cache.json")
SPA_SENTENCES = os.path.join(os.path.dirname(__file__), "tatoeba_bulk", "spa_sentences.tsv")
ENG_SENTENCES = os.path.join(os.path.dirname(__file__), "tatoeba_bulk", "eng_sentences.tsv")
SPA_ENG_LINKS = os.path.join(os.path.dirname(__file__), "tatoeba_bulk", "spa-eng_links.tsv")
MAX_EXAMPLES = 3


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def score_sentence(text, word):
    """Score a sentence for quality. Returns None to reject."""
    words_in_sentence = text.split()
    length = len(words_in_sentence)

    if length < 3:
        return None

    # HARD REQUIREMENT: sentence must contain the target word
    pattern = r'\b' + re.escape(word.lower()) + r'\b'
    if re.search(pattern, text.lower()):
        score = 20
    elif word.lower() in text.lower():
        score = 10
    else:
        return None

    # Prefer sentences of 4-20 words
    if 4 <= length <= 20:
        score += 10
    elif length == 3:
        score += 3
    elif length <= 25:
        score += 5
    elif length > 30:
        score -= 5

    # Proper sentence structure
    if text[0].isupper():
        score += 2
    if text.rstrip()[-1] in '.!?':
        score += 2

    # Penalize unusual characters
    if any(c in text for c in ['[', ']', '{', '}', '<', '>']):
        score -= 10

    return score


def tokenize(text):
    """Extract lowercase word tokens from text."""
    return re.findall(r'[a-záéíóúüñ]+', text.lower())


def main():
    print("Loading word list...")
    deck = load_json(WORDS_FILE)
    words = deck["words"]
    print(f"  {len(words)} words in deck")

    # Collect all search terms we need
    search_terms = {}  # search_term -> [word_ids]
    for w in words:
        target = w["target"]
        search_term = target.lower().split(",")[0].split("(")[0].strip()
        parts = search_term.split()
        if len(parts) > 1:
            articles = {"el", "la", "los", "las", "un", "una", "unos", "unas", "de", "a", "en", "se"}
            content_parts = [p for p in parts if p not in articles]
            search_term = max(content_parts, key=len) if content_parts else parts[0]
        if search_term not in search_terms:
            search_terms[search_term] = []
        search_terms[search_term].append(w["id"])
    print(f"  {len(search_terms)} unique search terms")

    # Step 1: Load Spanish-English links
    print("\nLoading Spanish-English links...")
    spa_to_eng = {}
    with open(SPA_ENG_LINKS, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                spa_id, eng_id = parts[0], parts[1]
                if spa_id not in spa_to_eng:
                    spa_to_eng[spa_id] = []
                spa_to_eng[spa_id].append(eng_id)
    print(f"  {len(spa_to_eng)} linked Spanish sentences")

    # Step 2: Load Spanish sentences and build inverted word index
    # Only index sentences that have English translations
    print("Loading Spanish sentences and building word index...")
    spa_sentences = {}
    word_index = defaultdict(list)  # token -> [sentence_id, ...]
    with open(SPA_SENTENCES, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t", 2)
            if len(parts) < 3:
                continue
            sid, lang, text = parts[0], parts[1], parts[2]
            if sid not in spa_to_eng:
                continue  # skip sentences without English translations
            spa_sentences[sid] = text
            for token in set(tokenize(text)):
                if token in search_terms:
                    word_index[token].append(sid)
    print(f"  {len(spa_sentences)} Spanish sentences with English translations")
    print(f"  {len(word_index)} search terms found in index")

    # Step 3: Load English sentences (only those we need)
    needed_eng_ids = set()
    for token, sids in word_index.items():
        for sid in sids:
            for eid in spa_to_eng.get(sid, []):
                needed_eng_ids.add(eid)
    print(f"\nLoading {len(needed_eng_ids)} needed English sentences...")
    eng_sentences = {}
    with open(ENG_SENTENCES, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t", 2)
            if len(parts) < 3:
                continue
            sid = parts[0]
            if sid in needed_eng_ids:
                eng_sentences[sid] = parts[2]
    print(f"  {len(eng_sentences)} English sentences loaded")

    # Step 4: Match each flashcard word using the index
    print("\nMatching words to sentences...")
    cache = {}
    words_with_examples = 0
    total_examples = 0
    words_zero = 0

    for i, w in enumerate(words):
        word_id = w["id"]
        target = w["target"]
        search_term = target.lower().split(",")[0].split("(")[0].strip()
        parts = search_term.split()
        if len(parts) > 1:
            articles = {"el", "la", "los", "las", "un", "una", "unos", "unas", "de", "a", "en", "se"}
            content_parts = [p for p in parts if p not in articles]
            search_term = max(content_parts, key=len) if content_parts else parts[0]

        candidate_sids = word_index.get(search_term, [])
        candidates = []

        for sid in candidate_sids:
            spa_text = spa_sentences.get(sid, "")
            if not spa_text:
                continue

            s = score_sentence(spa_text, search_term)
            if s is None:
                continue

            # Find English translation
            best_eng = None
            for eid in spa_to_eng.get(sid, []):
                eng_text = eng_sentences.get(eid, "")
                if eng_text:
                    best_eng = eng_text
                    break

            if best_eng:
                candidates.append((s, spa_text, best_eng))

        # Sort by score, take top N
        candidates.sort(key=lambda x: x[0], reverse=True)
        examples = [{"es": c[1], "en": c[2]} for c in candidates[:MAX_EXAMPLES] if c[0] > 0]

        cache[word_id] = examples

        if examples:
            words_with_examples += 1
            total_examples += len(examples)
        else:
            words_zero += 1

        if (i + 1) % 500 == 0:
            print(f"  [{i+1}/{len(words)}] {words_with_examples} matched, {total_examples} examples")

    print(f"\nResults:")
    print(f"  {words_with_examples}/{len(words)} words have examples ({words_zero} with zero)")
    print(f"  {total_examples} total example sentences")

    # Load existing cache and merge — prefer bulk results, fall back to existing
    existing_cache = {}
    if os.path.exists(CACHE_FILE):
        existing_cache = load_json(CACHE_FILE)

    merged = {}
    bulk_wins = 0
    existing_wins = 0
    for w in words:
        wid = w["id"]
        bulk = cache.get(wid, [])
        existing = existing_cache.get(wid, [])
        if bulk:
            merged[wid] = bulk
            bulk_wins += 1
        elif existing:
            merged[wid] = existing
            existing_wins += 1
        else:
            merged[wid] = []

    save_json(CACHE_FILE, merged)
    print(f"\nSaved merged cache: {len(merged)} entries")
    print(f"  {bulk_wins} from bulk, {existing_wins} kept from existing cache")


if __name__ == "__main__":
    main()
