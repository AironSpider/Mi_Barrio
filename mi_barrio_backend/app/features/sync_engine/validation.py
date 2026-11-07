"""Validación de los payloads del sync con las MISMAS reglas que las rutas REST.

El sync es una segunda puerta a la base de datos: si no valida igual que REST,
se puede guardar por ahí lo que REST rechaza (lat=999, status inventados, fotos
de 3 MB...). Cada error lanza ValueError con un mensaje claro, que el sync
devuelve en `rejected` para ese ítem.
"""
from typing import get_args

from app.shared.contract_values import (
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
    },
    "local_services": {
        "category": ("enum", _one_of(ServiceCategory)),
        "title": ("text", (1, 200)),
        "description": ("text_opt", (0, 2000)),
        "publisher_type": ("enum_opt", _one_of(PublisherType)),
        "publisher_name": ("text_opt", (0, 120)),
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
    },
}

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
        elif rule == "rating":
            if value is None:
                continue
            if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 5:
                raise ValueError("rating debe ser un entero de 1 a 5")
    for field in _BOOL_FIELDS & payload.keys():
        if not isinstance(payload[field], bool):
            raise ValueError(f"{field} debe ser true o false")
