"""Valores permitidos del contrato de datos (memoria técnica, sección 4.2).

Se usan como `Literal` en los schemas de creación: Swagger los muestra como
lista desplegable y su ejemplo por defecto ya es válido (antes guardaba "string").
Los schemas de respuesta siguen aceptando `str` para no romper con datos viejos.
"""
from typing import Literal

FlowType = Literal["SOLICITO_AYUDA", "OFREZCO_AYUDA"]
Modality = Literal[
    "PRESTAMO_HERRAMIENTA", "AYUDA_TEMPORAL", "DONACION_MATERIAL",
    "INTERCAMBIO_HABILIDAD", "MOVILIDAD_SOLIDARIA", "RECURSO_CRITICO",
    # Nuevos: más tipos de favor y "Otro" (el detalle va en la descripción).
    "ALIMENTOS", "ROPA", "MASCOTAS", "APOYO_ESCOLAR", "OTRO",
]
PostStatus = Literal["DISPONIBLE", "EN_COORDINACION", "COMPLETADO"]
ServiceCategory = Literal[
    "GASFITERIA", "CARPINTERIA", "ELECTRICIDAD", "PASEADOR_MASCOTAS",
    "CLASES", "CERRAJERIA", "SOPORTE_EMERGENCIA",
    # Rubros nuevos (Sprint 13)
    "ALBANILERIA", "PINTURA", "MECANICA", "TECNOLOGIA", "COSTURA", "BELLEZA",
    "LIMPIEZA", "LAVANDERIA", "JARDINERIA", "MUDANZA", "COMIDA", "BODEGA",
    "CUIDADO", "SALUD", "OTROS",
]
# Fotos de un servicio: hasta 4, cada una ≤ 110 000 caracteres (JPEG ~480-800 px).
MAX_SERVICE_PHOTOS = 4
MAX_PHOTO_B64 = 110_000
PublisherType = Literal["PERSONA_NATURAL", "EMPRENDEDOR", "BODEGA", "MINI_EMPRESA", "EMPRESA"]
UrgencyLevel = Literal["CRITICA", "ALTA", "MEDIA"]
VulnerabilityType = Literal[
    "ADULTO_MAYOR_SOLO", "MOVILIDAD_REDUCIDA", "ATENCION_MEDICA",
    "VIVIENDA_AFECTADA", "FALTA_SUMINISTROS",
    # Lluvias e incendios + "Otro" (el vecino escribe qué pasa, máx. 30).
    "INUNDACION", "INCENDIO", "ATRAPADOS", "OTRO",
]
# Grupos que necesitan más cuidado en una emergencia (pueden ser varios).
VulnerableGroup = Literal["NINOS", "MAYORES", "DISCAPACIDAD", "EMBARAZADA", "MASCOTAS"]
MAX_OTHER_TYPE_LABEL = 30
ReportStatus = Literal["PENDIENTE_APOYO", "VECINOS_EN_CAMINO", "ATENDIDO"]
# Reportes de publicaciones (moderación vecinal).
ReportTargetType = Literal["SOLIDARITY_POST", "LOCAL_SERVICE"]
ReportReason = Literal[
    "FALSO", "ESTAFA", "OFENSIVO", "SPAM", "PELIGROSO", "DATOS_PERSONALES", "OTRO",
]
# Con estos reportes de vecinos DISTINTOS la publicación pasa a revisión.
REPORTS_TO_REVIEW = 3
# Reportes de vecinos distintos (sobre cualquiera de sus publicaciones) para
# suspender una cuenta. Solo el jefe del barrio la puede reactivar.
REPORTS_TO_SUSPEND = 3
SupportGroupType = Literal[
    "PRIMEROS_AUXILIOS", "RESCATE", "ALBERGUE", "ALIMENTOS", "LOGISTICA", "SALUD_MENTAL",
]
