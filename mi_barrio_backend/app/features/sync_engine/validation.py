"""Validación de los payloads del sync con las MISMAS reglas que las rutas REST.

El sync es una segunda puerta a la base de datos: si no valida igual que REST,
se puede guardar por ahí lo que REST rechaza (lat=999, status inventados, fotos
de 3 MB...). Cada error lanza ValueError con un mensaje claro, que el sync
devuelve en `rejected` para ese ítem.
"""
import re
from typing import get_args

from app.shared.contract_values import (
    MAX_PHOTO_B64,
    MAX_SERVICE_PHOTOS,
    FlowType,
    Modality,
    PostStatus,
    PublisherType,
    ReportStatus,
    ServiceCategory,
    UrgencyLevel,
    VulnerabilityType,
)

MAX_BATCH = 200


def _one_of(literal) -> set[str]:
    return set(get_args(literal))


# campo → (tipo de regla, parámetro)
_RULES: dict[str, dict[str, tuple[str, object]]] = {
    "solidarity_posts": {
        "flow_type": ("enum", _one_of(FlowType)),
        "modality": ("enum", _one_of(Modality)),
        "status": ("enum", _one_of(PostStatus)),
        "title": ("text", (1, 200)),
        "description": ("text_opt", (0, 2000)),
        "lat": ("lat", None),
        "lng": ("lng", None),
        # Foto opcional del favor: mismo tope que las fotos de calificaciones.
        "photo_b64": ("text_opt", (0, 110_000)),
    },
    "local_services": {
        "category": ("enum", _one_of(ServiceCategory)),
        "title": ("text", (1, 200)),
        "description": ("text_opt", (0, 2000)),
        "publisher_type": ("enum_opt", _one_of(PublisherType)),
        "publisher_name": ("text_opt", (0, 120)),
        "price_text": ("text_opt", (0, 60)),
        "photos": ("photos", None),
        "lat": ("lat", None),
        "lng": ("lng", None),
    },
    "neighbor_endorsements": {
        "rating": ("rating", None),
        "short_comment": ("text_opt", (0, 255)),
        "photo_b64": ("text_opt", (0, 110_000)),
    },
    "vulnerable_reports": {
        "urgency_level": ("enum", _one_of(UrgencyLevel)),
        "vulnerability_type": ("enum", _one_of(VulnerabilityType)),
        "status": ("enum", _one_of(ReportStatus)),
        "description": ("text", (1, 2000)),
        "lat": ("lat", None),
        "lng": ("lng", None),
    },
    "users": {
        "full_name": ("text", (1, 150)),
        "phone": ("text_opt", (0, 20)),
        "address_reference": ("text_opt", (0, 200)),
        "home_lat": ("lat", None),
        "home_lng": ("lng", None),
        # Migración B: mismas reglas que la app (profile_local_storage.dart).
        "whatsapp": ("phone_opt", None),
        "facebook_url": ("https_url_opt", 300),
        "instagram_url": ("https_url_opt", 300),
        "email_contacto": ("email_opt", 254),
        "photo_b64": ("text_opt", (0, 110_000)),
        "publisher_type": ("enum_opt", _one_of(PublisherType)),
        "publisher_category": ("text_opt", (0, 50)),
        "publisher_name": ("text_opt", (0, 120)),
    },
}

_PHONE = re.compile(r"^\+?[0-9 ]{6,20}$")
_HTTPS_URL = re.compile(r"^https://[^\s]+$")
# Mismo patrón que la app (profile_local_storage.dart).
_EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")

_BOOL_FIELDS = {"is_deleted", "is_emergency_context", "is_available_in_emergency", "tutorial_completed"}


def _number(field: str, value) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} debe ser un número")
    return float(value)


def validate_payload(table: str, payload: dict) -> None:
    """Valida solo los campos presentes (un update puede ser parcial)."""
    for field, (rule, param) in _RULES.get(table, {}).items():
        if field not in payload:
            continue
        value = payload[field]
        if rule in ("enum", "enum_opt"):
            if value is None and rule == "enum_opt":
                continue
            if value not in param:
                raise ValueError(f"{field} inválido: {value!r}")
        elif rule in ("text", "text_opt"):
            if value is None and rule == "text_opt":
                continue
            if not isinstance(value, str):
                raise ValueError(f"{field} debe ser texto")
            low, high = param
            length = len(value.strip()) if rule == "text" else len(value)
            if length < low or len(value) > high:
                raise ValueError(f"{field} debe tener entre {low} y {high} caracteres")
        elif rule == "lat":
            if not -90 <= _number(field, value) <= 90:
                raise ValueError(f"{field} fuera de rango (-90 a 90)")
        elif rule == "lng":
            if not -180 <= _number(field, value) <= 180:
                raise ValueError(f"{field} fuera de rango (-180 a 180)")
        elif rule == "phone_opt":
            if value is None:
                continue
            if not isinstance(value, str) or not _PHONE.match(value):
                raise ValueError(f"{field} inválido: usa solo dígitos (6 a 20), con + opcional")
        elif rule == "email_opt":
            if value is None:
                continue
            if not isinstance(value, str) or len(value) > param or not _EMAIL.match(value):
                raise ValueError(f"{field} debe ser un correo válido de hasta {param} caracteres")
        elif rule == "https_url_opt":
            if value is None:
                continue
            if (
                not isinstance(value, str)
                or len(value) > param
                or not _HTTPS_URL.match(value)
            ):
                raise ValueError(f"{field} debe ser un enlace https:// de hasta {param} caracteres")
        elif rule == "photos":
            if value is None:
                continue
            if (
                not isinstance(value, list)
                or len(value) > MAX_SERVICE_PHOTOS
                or any(not isinstance(p, str) or not p or len(p) > MAX_PHOTO_B64 for p in value)
            ):
                raise ValueError(
                    f"photos debe ser una lista de hasta {MAX_SERVICE_PHOTOS} fotos (máx. {MAX_PHOTO_B64} caracteres c/u)"
                )
        elif rule == "rating":
            if value is None:
                continue
            if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 5:
                raise ValueError("rating debe ser un entero de 1 a 5")
    for field in _BOOL_FIELDS & payload.keys():
        if not isinstance(payload[field], bool):
            raise ValueError(f"{field} debe ser true o false")
