#!/usr/bin/env python3
"""Analyze mismatches and recommend which translations to switch to DeepL's.

Uses heuristics to categorize each mismatch:
- "keep": our translation is fine or better for learners
- "switch": DeepL's translation is more useful for a learner
- "review": genuinely unclear, needs human judgment

Known patterns where DeepL is usually better for learners:
- Ours is a formal/literary synonym; DeepL gives the everyday word
- Ours is an uncommon variant; DeepL gives what people actually say

Known patterns where ours is usually better:
- DeepL didn't translate (left English)
- DeepL gave a verb where we have a noun (or vice versa)
- DeepL's is a phrase/explanation, ours is the actual word
"""

import json
import os

INPUT = os.path.join(os.path.dirname(__file__), "mismatches_to_review.json")
OUTPUT = os.path.join(os.path.dirname(__file__), "translation_recommendations.json")

# Known formal/literary words where a more common alternative exists.
# Maps our_target -> the common everyday word a learner should know.
FORMAL_TO_COMMON = {
    # Formal/literary -> everyday
    "posteriormente": "después",
    "grato": "agradable",
    "propicio": "adecuado",
    "asimismo": "también",
    "nuevamente": "de nuevo",
    "acorde": "acuerdo",
    "contestación": "respuesta",
    "instancia": "solicitud",
    "acontecimiento": "evento",
    "acerca": "sobre",
    "exactitud": "precisión",
    "hallar": "encontrar",
    "anhelar": "desear",
    "brindar": "ofrecer",
    "carecer": "faltar",
    "certeza": "seguridad",
    "constatar": "comprobar",
    "despojar": "quitar",
    "discernir": "distinguir",
    "elocuente": "expresivo",
    "enaltecer": "exaltar",
    "enmendar": "corregir",
    "estimar": "calcular",
    "forjar": "crear",
    "fulgor": "brillo",
    "galardón": "premio",
    "gentil": "amable",
    "impartir": "dar",
    "indagar": "investigar",
    "inquietud": "preocupación",
    "ímpetu": "impulso",
    "jornada": "día",
    "laborar": "trabajar",
    "litigio": "disputa",
    "menester": "necesidad",
    "morada": "casa",
    "obstante": "embargo",
    "padecer": "sufrir",
    "perjuicio": "daño",
    "platicar": "hablar",
    "pormenor": "detalle",
    "prescindir": "eliminar",
    "pugna": "lucha",
    "recabar": "obtener",
    "sosiego": "calma",
    "trayecto": "camino",
    "veraz": "honesto",
    "vocablo": "palabra",
    "yerro": "error",
    "allegado": "cercano",
    "auspicio": "patrocinio",
    "menoscabo": "daño",
    "acaparar": "monopolizar",
    "abogar": "defender",
    "suscitar": "provocar",
    "vislumbrar": "entrever",
    "acarrear": "causar",
    "ameritar": "merecer",
    "ataviado": "vestido",
    "cúmulo": "montón",
    "emprender": "comenzar",
    "fomentar": "promover",
    "disipar": "dispersar",
    "escindir": "dividir",
    "ostentar": "mostrar",
    "soslayar": "evitar",
    "subyacer": "existir debajo",
    "vertiginoso": "rápido",
    "acervo": "conjunto",
    "acotar": "limitar",
}


def classify(entry):
    """Classify a mismatch as keep/switch/review with a reason."""
    ours = entry["our_target"]
    theirs = entry["deepl_target"]
    source = entry["source"]
    ours_lower = ours.lower().strip()
    theirs_lower = theirs.lower().strip()

    # --- KEEP: DeepL didn't translate (left English) ---
    if theirs_lower == source.lower().strip():
        return "keep", "DeepL didn't translate"

    # --- KEEP: DeepL echoed source format with brackets ---
    if "[" in theirs and "[" in source:
        return "keep", "DeepL echoed source formatting"

    # --- KEEP: DeepL gave a much longer phrase (ours is the actual word) ---
    if len(theirs) > len(ours) * 2.5 and len(ours.split()) <= 2:
        return "keep", "DeepL gave a long explanation, ours is concise"

    # --- KEEP: Our word is correct, DeepL gave wrong part of speech ---
    # e.g., we have noun "acto", DeepL gave verb "actuar"
    pos = entry.get("partOfSpeech") or ""
    if "noun" in pos and not any(c.isalpha() and c.isupper() for c in theirs[1:]):
        # Check if DeepL gave an infinitive verb for our noun
        theirs_words = theirs_lower.split(",")
        verb_endings = ("ar", "er", "ir", "arse", "erse", "irse")
        if any(w.strip().endswith(verb_endings) for w in theirs_words):
            if not ours_lower.endswith(verb_endings):
                return "keep", "DeepL gave a verb, we correctly have a noun"

    # --- SWITCH: Known formal-to-common mapping ---
    if ours_lower in FORMAL_TO_COMMON:
        common = FORMAL_TO_COMMON[ours_lower]
        if common in theirs_lower:
            return "switch", f"'{ours}' is formal/literary; '{common}' is the everyday word"
        else:
            return "switch", f"'{ours}' is formal/literary; DeepL suggests '{theirs}'"

    # --- SWITCH: DeepL gives a shorter, simpler single word for our multi-syllable one ---
    if " " not in ours_lower and " " not in theirs_lower:
        if len(ours) > len(theirs) + 4 and len(theirs) >= 3:
            return "review", f"DeepL's '{theirs}' is simpler; ours '{ours}' may be formal"

    # --- REVIEW: genuinely different translations ---
    return "review", f"Different translations: '{ours}' vs '{theirs}'"


def main():
    with open(INPUT, "r", encoding="utf-8") as f:
        mismatches = json.load(f)

    results = {"keep": [], "switch": [], "review": []}

    for entry in mismatches:
        verdict, reason = classify(entry)
        entry["verdict"] = verdict
        entry["reason"] = reason
        results[verdict].append(entry)

    print(f"Results:")
    print(f"  Keep ours:       {len(results['keep'])}")
    print(f"  Switch to DeepL: {len(results['switch'])}")
    print(f"  Needs review:    {len(results['review'])}")

    # Save all with verdicts
    all_results = results["switch"] + results["review"] + results["keep"]
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    print(f"\nSaved to: {OUTPUT}")

    # Print switches
    if results["switch"]:
        print(f"\n--- RECOMMENDED SWITCHES ({len(results['switch'])}) ---")
        for r in results["switch"]:
            print(f"  {r['source']:30s}  {r['our_target']:20s} -> {r['deepl_target']:20s}  ({r['reason']})")

    # Print a sample of review-needed
    if results["review"]:
        print(f"\n--- SAMPLE NEEDING REVIEW (first 20 of {len(results['review'])}) ---")
        for r in results["review"][:20]:
            print(f"  {r['source']:30s}  {r['our_target']:20s} vs {r['deepl_target']:20s}")


if __name__ == "__main__":
    main()
