import uuid
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.features.sync_engine.schemas import SyncPushRequest
from app.features.solidarity_network.models import SolidarityPost
from app.features.proximity_services.models import LocalService
from app.features.emergency_support.models import VulnerableReport

# Diccionario para enrutar dinámicamente la tabla del móvil al modelo de PostgreSQL
TABLE_MODEL_MAP = {
    "solidarity_posts": SolidarityPost,
    "local_services": LocalService,
    "vulnerable_reports": VulnerableReport,
}

async def process_sync_push(tenant_uuid: uuid.UUID, request: SyncPushRequest, db: AsyncSession) -> list[str]:
    processed_ids = []

    for item in request.mutations:
        table_name = item.target_table
        payload = item.payload
        rec_id_str = item.record_id

        try:
            rec_id = uuid.UUID(rec_id_str)
        except ValueError:
            continue # Ignorar si el celular envía un ID corrupto

        model_class = TABLE_MODEL_MAP.get(table_name)
        if not model_class:
            continue # Si el frontend envía una tabla no soportada, se ignora

        # 1. Buscar si el registro ya existe en el servidor para este barrio (Tenant)
        query = select(model_class).where(
            model_class.id == rec_id,
            model_class.tenant_id == tenant_uuid
        )
        result = await db.execute(query)
        existing_record = result.scalar_one_or_none()

        # 2. Extraer y formatear la fecha del celular
        client_updated_str = payload.get("updated_at")
        if client_updated_str:
            client_updated_at = datetime.fromisoformat(client_updated_str.replace("Z", "+00:00"))
        else:
            client_updated_at = datetime.now(timezone.utc)

        # 3. Resolución de Conflictos (Last-Write-Wins)
        if existing_record:
            # Asegurar que la fecha de la BD tenga zona horaria para poder compararla
            db_updated_at = existing_record.updated_at
            if db_updated_at.tzinfo is None:
                db_updated_at = db_updated_at.replace(tzinfo=timezone.utc)

            # Solo sobreescribimos si el celular tiene un dato más nuevo
            if db_updated_at <= client_updated_at:
                for key, val in payload.items():
                    if hasattr(existing_record, key) and key not in ["id", "tenant_id", "created_at"]:
                        # Convertir strings a UUID automáticamente si la columna lo requiere
                        if key.endswith("_id") and isinstance(val, str):
                            try:
                                val = uuid.UUID(val)
                            except ValueError:
                                pass
                        setattr(existing_record, key, val)
                existing_record.updated_at = client_updated_at
        else:
            # 4. Inserción de un registro nuevo creado 100% offline
            clean_payload = {
                "id": rec_id, 
                "tenant_id": tenant_uuid, 
                "updated_at": client_updated_at
            }
            
            for key, val in payload.items():
                if hasattr(model_class, key) and key not in ["id", "tenant_id"]:
                    if key.endswith("_id") and isinstance(val, str):
                        try:
                            val = uuid.UUID(val)
                        except ValueError:
                            pass
                    clean_payload[key] = val
            
            new_record = model_class(**clean_payload)
            db.add(new_record)
        
        processed_ids.append(rec_id_str)

    # Confirmar todos los cambios en bloque para máxima velocidad (esencial en hackathons)
    await db.commit()
    return processed_ids