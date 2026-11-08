"""Censura de groserías y discurso de odio en lo que escriben los vecinos.

Se aplica en el servidor ANTES de guardar (sync y rutas REST), así nada
ofensivo llega a otros vecinos aunque venga de una app vieja. La app usa la
MISMA lista para avisar mientras se escribe.

Las palabras se cambian por su primera letra y asteriscos ("p***"). Nunca se
rechaza el envío: un pedido de ayuda en una emergencia se guarda siempre.

La lista vive en offensive_words.json (junto a este archivo). La app tiene una
copia idéntica en assets/moderation/; una prueba de la app falla si difieren,
así que al cambiar una hay que copiarla a la otra.
"""
from __future__ import annotations

import json
import re
import unicodedata
from functools import lru_cache
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_WORDS_FILE = _HERE / "offensive_words.json"

_LEET = str.maketrans({"4": "a", "@": "a", "3": "e", "1": "i", "!": "i", "0": "o", "5": "s", "$": "s", "7": "t"})
_TOKEN = re.compile(r"[\w@$!]+", re.UNICODE)
_REPEATS = re.compile(r"(.)\1+")

# Campos de texto libre que se censuran (en cualquier tabla).
TEXT_FIELDS = frozenset({
    "title", "description", "publisher_name", "other_type_label", "full_name",
    "address_reference", "comment", "body", "name", "meeting_point", "details",
    "detail", "reason_detail",
})


def normalize(word: str) -> str:
    """minúsculas, sin tildes, 4→a…, letras repetidas juntas ("puuuta" → "puta")."""
    text = unicodedata.normalize("NFKD", word.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.translate(_LEET)
    text = re.sub(r"[^a-zñ ]", "", text)
    return _REPEATS.sub(r"\1", text)


@lru_cache(maxsize=1)
def _lists() -> tuple[frozenset[str], tuple[tuple[str, ...], ...]]:
    data = json.loads(_WORDS_FILE.read_text(encoding="utf-8"))
    words = frozenset(normalize(w) for w in data["words"])
    phrases = tuple(
        tuple(normalize(part) for part in phrase.split()) for phrase in data["hate_phrases"]
    )
    return words, phrases


def _mask(token: str) -> str:
    return token[0] + "*" * (len(token) - 1)


def censor(text: str | None) -> str | None:
    """Devuelve el texto con las palabras ofensivas cambiadas por asteriscos."""
    if not text:
        return text
    words, phrases = _lists()
    matches = list(_TOKEN.finditer(text))
    normalized = [normalize(m.group()) for m in matches]
    flagged = {i for i, w in enumerate(normalized) if w in words}
    for phrase in phrases:
        size = len(phrase)
        for start in range(len(normalized) - size + 1):
            if tuple(normalized[start:start + size]) == phrase:
                flagged.update(range(start, start + size))
    if not flagged:
        return text
    out, last = [], 0
    for i, m in enumerate(matches):
        if i in flagged:
            out.append(text[last:m.start()])
            out.append(_mask(m.group()))
            last = m.end()
    out.append(text[last:])
    return "".join(out)


def is_offensive(text: str | None) -> bool:
    return bool(text) and censor(text) != text


def censor_payload(payload: dict) -> dict:
    """Copia del payload de sync con los campos de texto libre censurados."""
    changed = {
        key: censor(value)
        for key, value in payload.items()
        if key in TEXT_FIELDS and isinstance(value, str) and is_offensive(value)
    }
    return {**payload, **changed} if changed else payload
