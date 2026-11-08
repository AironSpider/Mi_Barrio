"""Datos de demo para el barrio BARRIO-01 (Sprint 9, Dev 1).

Uso (desde mi_barrio_backend, con DATABASE_URL en el entorno o en .env):

    $env:SEED_DEMO_PASSWORD = "tu-clave-de-demo"
    venv\\Scripts\\python.exe scripts\\seed_demo.py

- Idempotente: se puede correr varias veces; cada fila tiene un UUID fijo
  (uuid5) y solo se inserta si no existe.
- La contrasena de las 3 cuentas demo sale de SEED_DEMO_PASSWORD. No se escribe
  en el repo ni se imprime.
- Coordenadas reales de Piura (Plaza de Armas), radio aproximado de 1 km.
"""
import asyncio
import os
import sys
import uuid
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

JOIN_CODE = "BARRIO-01"
CENTER_LAT, CENTER_LNG = -5.19449, -80.63282  # Plaza de Armas de Piura
# Mismo id que usan la migración de grupos y los scripts de prueba.
DEMO_TENANT_ID = uuid.UUID("a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d")
NS = uuid.UUID("6f1d2c3a-5b7e-4c90-a1b2-0d3e4f5a6b7c")  # namespace fijo del seed


def uid(key: str) -> uuid.UUID:
    return uuid.uuid5(NS, key)


# ---------------------------------------------------------------- datos
# key, nombre, email, rol, telefono, dlat, dlng (desplazamiento del centro)
USERS = [
    ("vecina", "Rosa Calle (demo)", "demo.vecina@mibarrio.demo", "VECINO", "+51900000001", 0.0030, -0.0020),
    ("comerciante", "Luis Ramos (demo)", "demo.comerciante@mibarrio.demo", "COMERCIANTE", "+51900000002", -0.0040, 0.0035),
    ("admin", "Junta Vecinal (demo)", "demo.admin@mibarrio.demo", "ADMIN_BARRIO", "+51900000003", 0.0010, 0.0010),
    ("v1", "Marta Silva", "demo.vecino1@mibarrio.demo", "VECINO", "+51900000011", 0.0055, 0.0040),
    ("v2", "Jorge Prado", "demo.vecino2@mibarrio.demo", "VECINO", "+51900000012", -0.0025, -0.0050),
    ("v3", "Elena Vega", "demo.vecino3@mibarrio.demo", "VECINO", "+51900000013", -0.0060, 0.0010),
    ("v4", "Carlos Rojas", "demo.vecino4@mibarrio.demo", "VECINO", "+51900000014", 0.0070, -0.0030),
]

# key, categoria, titulo, descripcion, proveedor, disponible_en_emergencia, dlat, dlng
SERVICES = [
    ("s1", "GASFITERIA", "Gasfitero a domicilio", "Reparo fugas, griferías y tuberías. Atiendo el mismo día.", "comerciante", True, -0.0042, 0.0033),
    ("s2", "ELECTRICIDAD", "Electricista certificado", "Instalaciones, tableros y cortocircuitos. También de noche.", "comerciante", True, -0.0038, 0.0038),
    ("s3", "CARPINTERIA", "Carpintería y muebles", "Puertas, ventanas y arreglos de muebles de madera.", "v1", False, 0.0052, 0.0042),
    ("s4", "CERRAJERIA", "Cerrajero 24 horas", "Apertura de puertas, cambio de chapas y copias de llaves.", "comerciante", False, -0.0035, 0.0030),
    ("s5", "CLASES", "Clases de refuerzo escolar", "Matemáticas y comunicación para primaria y secundaria.", "v2", False, -0.0028, -0.0047),
    ("s6", "PASEADOR_MASCOTAS", "Paseo de perros", "Paseos de 30 minutos por las tardes, cerca del parque.", "v3", False, -0.0058, 0.0012),
    ("s7", "SOPORTE_EMERGENCIA", "Botiquín y primeros auxilios", "Curaciones básicas y orientación en caso de emergencia.", "v4", False, 0.0068, -0.0028),
    ("s8", "GASFITERIA", "Instalación de calentadores", "Instalo y reviso calentadores de agua y duchas eléctricas.", "v1", False, 0.0057, 0.0038),
]

# servicio -> [(quien califica, estrellas, comentario)]
RATINGS = {
    "s1": [("vecina", 5, "Llegó rápido y dejó todo limpio."), ("v2", 5, "Muy buen trabajo."), ("v3", 4, "Puntual y honesto.")],
    "s2": [("vecina", 5, "Resolvió un corte de luz en una hora."), ("v1", 4, "Buen precio."), ("v4", 5, "Muy recomendado.")],
    "s3": [("vecina", 4, "Arregló mi puerta sin problema."), ("v2", 5, "Trabajo prolijo.")],
    "s4": [("v1", 5, "Abrió mi puerta en minutos."), ("v3", 4, "Atención amable."), ("v4", 3, "Demoró un poco.")],
    "s5": [("vecina", 5, "Mi hijo mejoró sus notas."), ("v1", 4, "Paciente con los niños.")],
    "s6": [("v2", 5, "Mi perro vuelve feliz."), ("vecina", 5, "Muy responsable.")],
    "s7": [("vecina", 5, "Me ayudó con una curacion."), ("v2", 4, "Sabe lo que hace.")],
    "s8": [("v3", 4, "Instaló mi calentador bien."), ("v4", 4, "Cumplió con el plazo.")],
}

# key, flow, modalidad, titulo, descripcion, autor, emergencia, estado, dlat, dlng
POSTS = [
    ("p1", "OFREZCO_AYUDA", "PRESTAMO_HERRAMIENTA", "Presto taladro y escalera", "Disponibles los fines de semana. Se devuelven limpios.", "v1", False, "DISPONIBLE", 0.0050, 0.0035),
    ("p2", "SOLICITO_AYUDA", "AYUDA_TEMPORAL", "Necesito ayuda para mudar un ropero", "Solo una hora por la mañana. Con gusto devuelvo el favor.", "vecina", False, "DISPONIBLE", 0.0032, -0.0018),
    ("p3", "OFREZCO_AYUDA", "INTERCAMBIO_HABILIDAD", "Cambio clases de guitarra por arreglo de bicicleta", "Clases para principiantes.", "v2", False, "EN_COORDINACION", -0.0030, -0.0045),
    ("p4", "OFREZCO_AYUDA", "RECURSO_CRITICO", "Camilla plegable disponible", "La presto para trasladar a una persona. Retiro en mi casa.", "v3", True, "DISPONIBLE", -0.0055, 0.0015),
    ("p5", "OFREZCO_AYUDA", "RECURSO_CRITICO", "Generador eléctrico y bidones de agua", "Puedo compartir agua potable y cargar celulares.", "v4", True, "DISPONIBLE", 0.0066, -0.0025),
    ("p6", "OFREZCO_AYUDA", "MOVILIDAD_SOLIDARIA", "Llevo a adultos mayores al centro de salud", "Tengo auto, salgo por las mañanas.", "comerciante", False, "DISPONIBLE", -0.0038, 0.0034),
]

# key, urgencia, tipo, descripcion, reporta, dlat, dlng
REPORTS = [
    ("r1", "CRITICA", "ATENCION_MEDICA", "Adulto mayor con dificultad para respirar, vive solo.", "v3", -0.0057, 0.0008),
    ("r2", "ALTA", "MOVILIDAD_REDUCIDA", "Vecina en silla de ruedas, el agua entro a su casa.", "v2", -0.0027, -0.0049),
    ("r3", "MEDIA", "FALTA_SUMINISTROS", "Familia con niños sin agua potable desde ayer.", "v1", 0.0054, 0.0039),
]

# Grupos de apoyo: los MISMOS 3 (mismo id) que crea la migración f4a5b6c7d8e9,
# así nunca quedan duplicados. El seed les completa teléfono y coordinador.
# id, nombre, tipo, descripcion, telefono, punto de encuentro, coordinador, lat, lng
GROUPS = [
    ("5a1c0e2b-0001-4c3d-8e9f-0a1b2c3d4e01", "Brigada de primeros auxilios", "PRIMEROS_AUXILIOS",
     "Vecinos con curso de primeros auxilios y botiquín.", "+51900000101", "Losa deportiva", "v4", -5.1940, -80.6320),
    ("5a1c0e2b-0002-4c3d-8e9f-0a1b2c3d4e02", "Albergue parroquial", "ALBERGUE",
     "Espacio techado para familias con vivienda afectada.", "+51900000102", "Parroquia del barrio", "v3", -5.1958, -80.6341),
    ("5a1c0e2b-0003-4c3d-8e9f-0a1b2c3d4e03", "Olla común Mi Barrio", "ALIMENTOS",
     "Almuerzo diario para adultos mayores y familias afectadas.", "+51900000103", "Comedor popular", "vecina", -5.1932, -80.6352),
]
# Grupos que creaban versiones anteriores del seed (duplicaban a la migración):
# se desactivan (is_active = false), no se borran.
OLD_SEED_GROUP_KEYS = ["g1", "g2", "g3"]


async def run() -> None:
    password = os.environ.get("SEED_DEMO_PASSWORD", "")
    if not password:
        sys.exit("Falta la variable SEED_DEMO_PASSWORD. Ejemplo (PowerShell):\n"
                 '  $env:SEED_DEMO_PASSWORD = "tu-clave-de-demo"')

    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from sqlalchemy.pool import NullPool

    from app.core.auth_security import hash_password
    from app.core.database import DATABASE_URL
    from app.features.auth_barrio.models import Tenant, User
    from app.features.emergency_support.models import SupportGroup, VulnerableReport
    from app.features.proximity_services.models import LocalService, NeighborEndorsement
    from app.features.solidarity_network.models import SolidarityPost

    engine = create_async_engine(DATABASE_URL, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    added = {"usuarios": 0, "servicios": 0, "calificaciones": 0,
             "favores": 0, "sos": 0, "grupos": 0,
             "grupos completados": 0, "grupos duplicados desactivados": 0}

    async def put(db, obj, counter: str) -> None:
        if await db.get(type(obj), obj.id) is None:
            db.add(obj)
            added[counter] += 1

    async with session_factory() as db:
        # ---- barrio
        tenant = (await db.execute(select(Tenant).where(Tenant.join_code == JOIN_CODE))).scalar_one_or_none()
        if tenant is None:
            tenant = Tenant(id=DEMO_TENANT_ID, name="Barrio Centro Piura (demo)", join_code=JOIN_CODE,
                            center_lat=CENTER_LAT, center_lng=CENTER_LNG, is_emergency_active=False)
            db.add(tenant)
            await db.flush()
        tid = tenant.id

        # ---- usuarios (por email; el admin es unico por barrio)
        user_ids: dict[str, uuid.UUID] = {}
        pwd_hash = hash_password(password)
        for key, name, email, role, phone, dlat, dlng in USERS:
            existing = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
            if existing is not None:
                user_ids[key] = existing.id
                continue
            if role == "ADMIN_BARRIO":
                other = (await db.execute(select(User).where(
                    User.tenant_id == tid, User.role == "ADMIN_BARRIO", User.is_deleted == False  # noqa: E712
                ))).scalars().first()
                if other is not None:
                    print("Aviso: BARRIO-01 ya tiene un admin; no se crea el admin demo.")
                    user_ids[key] = other.id
                    continue
            u = User(id=uid("user:" + key), tenant_id=tid, full_name=name, email=email,
                     password_hash=pwd_hash, role=role, phone=phone,
                     home_lat=CENTER_LAT + dlat, home_lng=CENTER_LNG + dlng,
                     tutorial_completed=False)
            db.add(u)
            user_ids[key] = u.id
            added["usuarios"] += 1
        await db.flush()

        # ---- servicios y calificaciones
        for key, cat, title, desc, prov, emerg, dlat, dlng in SERVICES:
            n_rat = len(RATINGS.get(key, []))
            await put(db, LocalService(
                id=uid("service:" + key), tenant_id=tid, provider_user_id=user_ids[prov],
                category=cat, title=title, description=desc, is_available_in_emergency=emerg,
                endorsements_count=n_rat, lat=CENTER_LAT + dlat, lng=CENTER_LNG + dlng), "servicios")
        await db.flush()
        for skey, items in RATINGS.items():
            for who, stars, comment in items:
                await put(db, NeighborEndorsement(
                    id=uid(f"endorsement:{skey}:{who}"), tenant_id=tid,
                    service_id=uid("service:" + skey), endorser_user_id=user_ids[who],
                    short_comment=comment, rating=stars), "calificaciones")

        # ---- favores
        for key, flow, modality, title, desc, author, emerg, status, dlat, dlng in POSTS:
            await put(db, SolidarityPost(
                id=uid("post:" + key), tenant_id=tid, author_user_id=user_ids[author],
                flow_type=flow, modality=modality, title=title, description=desc,
                is_emergency_context=emerg, status=status,
                lat=CENTER_LAT + dlat, lng=CENTER_LNG + dlng), "favores")

        # ---- SOS
        for key, urgency, vtype, desc, reporter, dlat, dlng in REPORTS:
            await put(db, VulnerableReport(
                id=uid("report:" + key), tenant_id=tid, reporter_user_id=user_ids[reporter],
                urgency_level=urgency, vulnerability_type=vtype, description=desc,
                lat=CENTER_LAT + dlat, lng=CENTER_LNG + dlng, status="PENDIENTE_APOYO"), "sos")

        # ---- grupos de apoyo (mismos ids que la migración: se crean o se completan)
        for gid, name, gtype, desc, phone, meeting, coord, lat, lng in GROUPS:
            group = await db.get(SupportGroup, uuid.UUID(gid))
            if group is None:
                db.add(SupportGroup(
                    id=uuid.UUID(gid), tenant_id=tid, name=name, group_type=gtype,
                    description=desc, contact_phone=phone, meeting_point=meeting,
                    coordinator_user_id=user_ids[coord], lat=lat, lng=lng, is_active=True))
                added["grupos"] += 1
            elif group.contact_phone is None or group.coordinator_user_id is None:
                group.contact_phone = group.contact_phone or phone
                group.coordinator_user_id = group.coordinator_user_id or user_ids[coord]
                added["grupos completados"] += 1
        for key in OLD_SEED_GROUP_KEYS:
            old = await db.get(SupportGroup, uid("group:" + key))
            if old is not None and old.is_active:
                old.is_active = False
                added["grupos duplicados desactivados"] += 1

        await db.commit()
    await engine.dispose()

    print(f"Seed listo para {JOIN_CODE}. Filas nuevas en esta corrida:")
    for k, v in added.items():
        print(f"  {k}: {v}")
    print("Cuentas demo: demo.vecina@ / demo.comerciante@ / demo.admin@ mibarrio.demo "
          "(clave = SEED_DEMO_PASSWORD)")


if __name__ == "__main__":
    asyncio.run(run())
