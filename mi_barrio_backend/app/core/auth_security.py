import base64
import hashlib
import hmac
import json
import os
import secrets
import time
import uuid

from fastapi import HTTPException, status

PASSWORD_ITERATIONS = 310_000
ACCESS_TOKEN_SECONDS = 60 * 60 * 24
_JWT_HEADER = {"alg": "HS256", "typ": "JWT"}


def _secret_key() -> bytes:
    value = os.getenv("MI_BARRIO_JWT_SECRET")
    if not value or len(value) < 32:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "La autenticación no está configurada. Define "
                "MI_BARRIO_JWT_SECRET con al menos 32 caracteres."
            ),
        )
    return value.encode("utf-8")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PASSWORD_ITERATIONS
    )
    return f"pbkdf2_sha256${PASSWORD_ITERATIONS}${_b64encode(salt)}${_b64encode(digest)}"


def verify_password(password: str, stored_hash: str | None) -> bool:
    if not stored_hash:
        return False
    try:
        algorithm, iterations, salt, expected = stored_hash.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            _b64decode(salt),
            int(iterations),
        )
        return hmac.compare_digest(actual, _b64decode(expected))
    except (ValueError, TypeError):
        return False


def create_access_token(
    *,
    user_id: uuid.UUID,
    tenant_id: uuid.UUID | None,
    role: str,
) -> str:
    now = int(time.time())
    header = _b64encode(json.dumps(_JWT_HEADER, separators=(",", ":")).encode())
    payload = _b64encode(
        json.dumps(
            {
                "sub": str(user_id),
                "tenant_id": str(tenant_id) if tenant_id is not None else None,
                "role": role,
                "iat": now,
                "exp": now + ACCESS_TOKEN_SECONDS,
            },
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode("ascii")
    signature = hmac.new(_secret_key(), signing_input, hashlib.sha256).digest()
    return f"{header}.{payload}.{_b64encode(signature)}"


def decode_access_token(token: str) -> dict:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o vencido",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        header, payload, signature = token.split(".")
        header_data = json.loads(_b64decode(header))
        claims = json.loads(_b64decode(payload))
        if header_data != _JWT_HEADER:
            raise unauthorized
        expected = hmac.new(
            _secret_key(),
            f"{header}.{payload}".encode("ascii"),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(expected, _b64decode(signature)):
            raise unauthorized
        if int(claims["exp"]) <= int(time.time()):
            raise unauthorized
        uuid.UUID(claims["sub"])
        role = claims.get("role")
        if role == "SUPER_ADMIN":
            if claims.get("tenant_id") is not None:
                raise unauthorized
        elif role in {"VECINO", "COMERCIANTE", "ADMIN_BARRIO"}:
            uuid.UUID(claims["tenant_id"])
        else:
            raise unauthorized
        return claims
    except HTTPException:
        raise
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        raise unauthorized from exc


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
