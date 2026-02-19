#!/usr/bin/env python3
"""Second-pass analysis: aggressive classification using Spanish knowledge.

Reads the 'review' items from translation_recommendations.json and sorts them
into: switch, regional, keep.
"""

import json
import os

INPUT = os.path.join(os.path.dirname(__file__), "translation_recommendations.json")
OUTPUT = os.path.join(os.path.dirname(__file__), "final_recommendations.json")

# --- SWITCH: our translation is wrong, misleading, or too obscure ---
# These are cases where a learner would be poorly served by our word.
SWITCH = {
    # Formal/literary where everyday word exists
    "lecho": ("cama", "bed", "'lecho' is poetic; 'cama' is what everyone says"),
    "envergadura": ("amplitud", "breadth", "'envergadura' is technical/formal; 'amplitud' is clearer"),
    "dichoso": ("afortunado", "fortunate", "'dichoso' often means 'damn' colloquially; misleading"),
    "repleto": ("lleno", "full", "'repleto' is emphatic; 'lleno' is the basic word to learn first"),
    "enterado": ("consciente", "aware of", "'consciente de' is the standard translation"),
    "centenar": ("cien", "hundred", "'centenar' means 'about a hundred'; 'cien' is the number"),
    "rotundo": ("categórico", "categorical", "'rotundo' means 'resounding'; 'categórico' is clearer"),
    "acontecer": ("suceder", "to happen", "'acontecer' is literary; 'suceder' or 'pasar' is normal"),
    "desconcierto": ("confusión", "disorder", "'desconcierto' is bewilderment; 'desorden' for disorder"),
    "transcurso": ("paso", "passing, course", "'transcurso' is very formal; 'paso' is everyday"),
    "significación": ("significado", "meaning", "'significado' is the standard word"),
    "procedencia": ("origen", "origin", "'origen' is much more common"),
    "modalidad": ("modo", "mode", "'modo' is the everyday word"),
    "festín": ("fiesta", "feast", "'fiesta' is what learners need; 'festín' is literary"),
    "desplazamiento": ("movimiento", "movement", "'movimiento' is the basic word"),
    "naturalidad": ("facilidad", "ease", "'naturalidad' means naturalness; 'facilidad' for ease"),
    "propiamente": ("exactamente", "exactly", "'propiamente' means 'properly'; misleading for 'exactly'"),
    "indudablemente": ("sin duda", "undoubtedly", "'sin duda' is simpler and more common"),
    "sencillamente": ("simplemente", "simply", "'simplemente' is more universal"),
    "altamente": ("muy", "highly", "'muy' is the word every learner needs"),
    "particularmente": ("en particular", "particularly", "both fine but 'en particular' is simpler"),
    "concurrencia": ("participación", "participation", "'concurrencia' means attendance/crowd"),
    "interlocutor": ("participante", "participant", "'interlocutor' is very formal"),
    "perspicacia": ("percepción", "insight", "'perspicacia' is rare in everyday speech"),
    "acervo": ("conjunto", "collection", "'acervo' is very literary"),
    "porquería": ("basura", "filth, junk", "'basura' is more standard; 'porquería' is slangy"),
    "barbaridad": ("atrocidad", "atrocity", "'barbaridad' means outrage/tons; 'atrocidad' matches better"),
    "planteamiento": ("propuesta", "proposal", "'propuesta' is clearer for learners"),
    "entrenamiento": ("formación", "training", "'formación' is broader/more common in many contexts"),
    "prenda": ("ropa", "piece of clothing", "'ropa' is the basic word for clothing"),
    "desaparecido": ("perdido", "missing", "'desaparecido' means disappeared (people); for objects 'perdido'"),
    "pretender": ("intentar", "to attempt", "'pretender' is a false friend; 'intentar' is correct"),
    "intuir": ("sentir", "to sense", "'sentir' is the basic word learners need"),
    "encaminar": ("dirigir", "to head for", "'dirigir' or 'dirigirse a' is more standard"),
    "relatar": ("contar", "to tell, narrate", "'contar' is the everyday word"),
    "presentir": ("intuir", "to sense in advance", "'presentir' is fine but 'intuir' more useful"),
    "entablar": ("empezar", "to start", "'empezar' or 'iniciar' is standard"),
    "apoderar": ("tomar el poder", "to take power", "'apoderarse de' needs the reflexive"),
    "remediar": ("curar", "to heal", "'curar' is the standard medical/everyday word"),
    "alumbrar": ("iluminar", "to light", "'iluminar' or 'encender' is more standard"),
    "sustentar": ("mantener", "to maintain", "'mantener' is the word learners need"),
    "conmover": ("emocionar", "to move, affect", "'emocionar' is more commonly used"),
    "proseguir": ("continuar", "to continue", "'continuar' or 'seguir' is everyday"),
    "desmentir": ("contradecir", "to contradict", "'contradecir' is more transparent"),
    "perjudicar": ("dañar", "to endanger", "'dañar' is simpler; 'perjudicar' means to harm/prejudice"),
    "discurrir": ("fluir", "to flow", "'fluir' is the standard word"),
    "espantar": ("asustar", "to scare", "'asustar' is the everyday word"),
    "aferrar": ("agarrar", "to grasp", "'agarrar' is more common"),
    "transitar": ("pasar", "to roam", "'pasar' or 'caminar' is everyday"),
    "procurar": ("intentar", "to try, seek", "'intentar' is clearer for 'to try'"),
    "atribuir": ("asignar", "to attribute", "DeepL garbled this but 'atribuir' is fine; keep"),
    "destrozar": ("romper", "to rip/break", "'romper' is the basic word"),
    "solucionar": ("resolver", "to solve", "'resolver' is more common"),
    "reclamar": ("exigir", "to demand", "'exigir' or 'demandar' is clearer"),
    "difundir": ("extender", "to spread", "'extender' or 'propagar' is more common"),
    "eventualmente": ("finalmente", "eventually", "FALSE COGNATE: 'eventualmente' means 'possibly' in Spanish!"),
    "infante": ("bebé", "infant", "'bebé' is the everyday word; 'infante' is archaic"),
    "pelaje": ("piel", "fur", "'piel' is more general and common"),
    "espécimen": ("muestra", "specimen", "'muestra' is more everyday"),
    "penalización": ("sanción", "penalty", "'sanción' or 'multa' is more common"),
    "sentencia": ("frase", "sentence", "'frase' for grammar; 'sentencia' is a court sentence"),
    "producción": ("salida", "output", "'salida' is more accurate for output"),
}

# --- REGIONAL: Latin American vs European Spanish ---
# Not wrong, but worth flagging as regional choice
REGIONAL = {
    "computadora": ("ordenador", "LatAm 'computadora' vs Spain 'ordenador'"),
    "refrigerador": ("frigorífico", "LatAm 'refrigerador' vs Spain 'frigorífico'"),
    "boleto": ("billete", "LatAm 'boleto' vs Spain 'billete'"),
    "mesero": ("camarero", "LatAm 'mesero' vs Spain 'camarero'"),
    "papa": ("patata", "LatAm 'papa' vs Spain 'patata'"),
    "jugo": ("zumo", "LatAm 'jugo' vs Spain 'zumo'"),
    "piso": ("suelo", "Both valid; 'piso' also means apartment/floor level"),
    "platicar": ("hablar", "Mexican 'platicar' vs universal 'hablar'"),
    "manejar": ("conducir", "LatAm 'manejar' vs Spain 'conducir'"),
    "enojado": ("enfadado", "LatAm 'enojado' vs Spain 'enfadado'"),
    "torta": ("tarta", "LatAm 'torta' vs Spain 'tarta' for cake"),
    "celular": ("móvil", "LatAm 'celular' vs Spain 'móvil'"),
    "jalar": ("tirar", "LatAm 'jalar' vs Spain 'tirar' for pull"),
    "apurarse": ("darse prisa", "LatAm 'apurarse' vs Spain 'darse prisa'"),
    "canasta": ("cesta", "LatAm 'canasta' vs Spain 'cesta'"),
    "gerente": ("director", "Both valid; 'gerente' more LatAm business"),
    "portafolio": ("cartera", "LatAm 'portafolio' vs Spain 'cartera'"),
}

# --- DEEPL GARBLED: DeepL gave nonsense/commands, ours is clearly right ---
DEEPL_GARBLED = {
    # DeepL gave imperative/command forms instead of infinitives
    "ver", "empezar", "pensar", "seguir", "dar", "decir", "sentir",
    "buscar", "usar", "querer", "notar", "intentar", "escoger",
    "sostener", "ahorrar", "correr", "rechazar", "reemplazar",
    "retener", "sacudir", "apretar", "quedarse", "advertir",
    "suplicar", "sumergir", "preservar", "resaltar", "involucrar",
    "asegurar", "permitir", "encerrar", "conceder", "contar",
    "revelar", "exceder", "exhibir", "doblar", "derretir",
    "descuidar", "erigir", "drenar", "derrotar", "declinar",
    "atrapar", "comprometerse", "lograr", "reconocer", "disculparse",
    "ensamblar", "computar", "requerir", "replicar", "valorar",
    "beneficiar", "interesar", "temer", "bordear", "abusar",
    "agradecer", "recetar", "nombrar", "renunciar",
    # DeepL translated as phrase/explanation, ours is the actual word
    "comunitario", "callejero",
    # Our word is fine, DeepL gave a different but not better word
    "ojalá", "latinoamericano", "norteamericano", "asombroso",
    "acercamiento", "asamblea", "provecho", "cariño", "parto",
    "vinculado", "destacado", "pacífico", "constancia", "orientado",
    "poderoso", "prisionero", "rol", "sueldo", "lástima",
    "destreza", "pesar", "específicamente", "soporte", "seguramente",
    "finalmente", "ámbito", "vigente", "domicilio", "resignación",
    "reposo", "relacionado", "cualidad", "cuestión", "finalidad",
    "fundamento", "amistoso", "plenamente", "primordial",
    "despedida", "escondido", "lejano", "aficionado", "foco",
    "sangriento", "cautela", "reivindicación", "manto",
    "comando", "compañía", "queja", "referente", "enfrentamiento",
    "revuelto", "consistencia", "contienda", "aporte", "conveniente",
    "ejemplar", "acertado", "delincuente", "gana",
    "desilusión", "prolongación", "incendio",
    "vereda", "pedazo", "interrogante", "hacienda",
    "colorado", "conforme", "encargado", "efectivamente",
    "enfrente", "entrañas", "chiquillo", "buque",
    "liviano", "poquito", "sonoro", "decena",
    "atener", "asaltar", "destinar", "abundar", "bastar",
    "ignorar", "alegrar", "abordar", "aburrir", "tranquilizar",
    "despejar", "trepar", "convivir", "provenir", "aproximar",
    "cometer", "dialogar", "internar", "alentar", "disculpar",
    "expandir", "combatir", "rematar", "enfocar", "parir",
    "aparentar", "retroceder", "traspasar", "influir", "acabar",
    "encabezar", "doler", "contagiar", "incidir", "adelantar",
    "adentrar", "agradar", "plantear", "proveer", "agregar",
    "meter", "llover", "repasar", "mandar", "comprobar",
    "velar", "calzar", "desechar", "echar",
    # Common words where both are fine
    "jamás", "próximo", "ese, esa", "aquel", "ahí", "allá",
    "adonde", "adónde", "tranquilamente", "curiosamente",
    "difícilmente", "completamente", "desperdicio",
    "actualidad", "apunte", "actualmente", "ambulante",
    "solidario", "indudable", "insólito", "aviso", "silvestre",
    "alambre", "pozo", "desgraciadamente", "gira", "traslado",
    "arreglo", "conciencia", "equilibrio", "lienzo", "conveniencia",
    "coraje", "fracaso", "trama", "poder", "premisa",
    "rango", "tasa", "razón", "promesa", "ritmo",
    "camino", "imagen", "tono", "proporción", "promedio",
    "mitad", "niño", "crimen", "costumbre", "evidencia",
    "niña", "herencia", "esposo", "ofensa", "aldea",
    "pueblo", "juicio", "transmisión", "otra vez", "temprano",
    "frecuentemente", "después", "previo", "todavía",
    "partida", "alojamiento", "fecha límite", "negocio",
    "consejo", "calificación", "impuesto",
    "ganancia", "sobre", "alrededor", "lejos", "cuchilla",
    "cabina", "mostrador", "entero", "pocos", "tener",
    "lo", "medio", "podría", "apagado", "parte",
    "bastante", "lado", "debajo de", "cuál", "quién",
    "oreja", "exacto", "audaz", "claro", "integral",
    "fresco", "mudo", "justo", "libre", "lleno",
    "gracioso", "genuino", "bueno", "magnífico", "genial",
    "duro", "afortunado", "múltiple", "viejo", "educado",
    "prominente", "silencioso", "severo", "afilado", "liso",
    "sustancial", "delgado", "exhaustivo", "diminuto", "mojado",
    "diario", "asustado", "comodidad", "animar", "reír",
    "solo", "elogio", "alivio", "pez", "comida",
    "crudo", "sabor", "propina", "vegetal", "desorden",
    "sanar", "lastimar", "pastilla", "plaga", "habitar",
    "cerca", "tenedor", "vaso", "hogar", "plancha",
    "llave", "ornamento", "techo", "mesa", "criar",
    "cosecha", "desastre", "erupcionar", "pronóstico",
    "tierra", "polo", "ola", "clima",
    "hacer cumplir", "haber",
    # Superlatives - our forms are correct
    "altísimo", "larguísimo", "pequeñito",
    # Fixed expressions
    "pena  (valer la pena)", "seguida: en seguida",
    "ninguno (adj pron)",
    "apresurar(se) (v)",
}


def classify(entry):
    ours = entry["our_target"]
    ours_lower = ours.lower().strip()

    # Check explicit switch list
    if ours_lower in SWITCH:
        rec, context, reason = SWITCH[ours_lower]
        return "switch", rec, reason

    # Check regional
    if ours_lower in REGIONAL:
        alt, note = REGIONAL[ours_lower]
        return "regional", alt, note

    # Check keep list
    if ours_lower in DEEPL_GARBLED:
        return "keep", None, "Our translation is correct"

    # Fallback: if DeepL gave a command/usted form, ours is probably the correct infinitive
    theirs = entry["deepl_target"].lower().strip()
    if ours_lower.endswith(("ar", "er", "ir")) and not theirs.endswith(("ar", "er", "ir")):
        return "keep", None, "We have correct infinitive; DeepL gave conjugated form"

    return "unclear", None, "Needs manual review"


def main():
    with open(INPUT, "r", encoding="utf-8") as f:
        all_data = json.load(f)

    reviews = [r for r in all_data if r["verdict"] == "review"]
    keeps = [r for r in all_data if r["verdict"] == "keep"]
    prev_switches = [r for r in all_data if r["verdict"] == "switch"]

    new_switches = []
    new_keeps = []
    regional = []
    unclear = []

    for entry in reviews:
        verdict, rec, reason = classify(entry)
        entry["verdict2"] = verdict
        entry["recommendation"] = rec
        entry["reason2"] = reason

        if verdict == "switch":
            new_switches.append(entry)
        elif verdict == "regional":
            regional.append(entry)
        elif verdict == "keep":
            new_keeps.append(entry)
        else:
            unclear.append(entry)

    print(f"Second-pass results on {len(reviews)} 'review' items:")
    print(f"  Switch to DeepL:  {len(new_switches)}")
    print(f"  Regional variant: {len(regional)}")
    print(f"  Keep ours:        {len(new_keeps)}")
    print(f"  Still unclear:    {len(unclear)}")

    # Combine with first-pass switches
    all_switches = prev_switches + new_switches
    print(f"\nTotal recommended switches: {len(all_switches)}")

    output = {
        "switches": [],
        "regional": [],
        "unclear": [],
    }

    for s in all_switches:
        rec = s.get("recommendation") or s.get("deepl_target", "")
        output["switches"].append({
            "id": s["id"],
            "source": s["source"],
            "current": s["our_target"],
            "recommended": rec,
            "reason": s.get("reason2") or s.get("reason", ""),
        })

    for r in regional:
        output["regional"].append({
            "id": r["id"],
            "source": r["source"],
            "current": r["our_target"],
            "alternative": r["recommendation"],
            "note": r["reason2"],
        })

    for u in unclear:
        output["unclear"].append({
            "id": u["id"],
            "source": u["source"],
            "current": u["our_target"],
            "deepl": u["deepl_target"],
        })

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\nSaved to: {OUTPUT}")

    print(f"\n--- ALL RECOMMENDED SWITCHES ({len(output['switches'])}) ---")
    for s in output["switches"]:
        print(f"  {s['source']:30s}  {s['current']:20s} -> {s['recommended']:20s}  ({s['reason']})")

    if output["regional"]:
        print(f"\n--- REGIONAL VARIANTS ({len(output['regional'])}) ---")
        for r in output["regional"]:
            print(f"  {r['source']:30s}  {r['current']:15s} alt: {r['alternative']:15s}  ({r['note']})")

    if output["unclear"]:
        print(f"\n--- STILL UNCLEAR ({len(output['unclear'])}) ---")
        for u in output["unclear"]:
            print(f"  {u['source']:30s}  {u['current']:20s} vs {u['deepl']}")


if __name__ == "__main__":
    main()
