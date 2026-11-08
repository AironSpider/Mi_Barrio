"""Filtra correos falsos ANTES de crear la cuenta.

La prueba definitiva de que un correo es real y de la persona es el código de
6 números que le llega (la cuenta no se puede usar hasta confirmarlo). Esto
corta antes los casos que nunca van a recibir ese código:

- correos desechables (mailinator, yopmail, 10minutemail…),
- errores de tipeo comunes (gmial.com, hotmal.com…), con sugerencia,
- Gmail con un usuario que Gmail no permite (muy corto, símbolos raros…),
- dominios que no existen o no reciben correo (se consulta el DNS).

La consulta DNS usa DNS sobre HTTPS de Google (sin dependencias extra). Si el
DNS no responde, se deja pasar: el código por correo sigue siendo el filtro.

Variables de entorno:
    EMAIL_DOMAIN_CHECK=0   apaga la consulta DNS (pruebas locales con
                           dominios .test). También se apaga con
                           AUTH_DEBUG_CODES=1.
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

from fastapi import HTTPException
from starlette.concurrency import run_in_threadpool

DOH_URL = "https://dns.google/resolve"

GMAIL_DOMAINS = {"gmail.com", "googlemail.com"}

# Dominios grandes que sabemos que reciben correo: no hace falta preguntar al DNS.
KNOWN_PROVIDERS = GMAIL_DOMAINS | {
    "hotmail.com", "hotmail.es", "outlook.com", "outlook.es", "live.com",
    "msn.com", "yahoo.com", "yahoo.es", "icloud.com", "me.com", "proton.me",
    "protonmail.com", "aol.com", "gmx.com", "zoho.com",
}

DISPOSABLE_DOMAINS = {
    "mailinator.com", "yopmail.com", "yopmail.net", "10minutemail.com",
    "10minutemail.net", "guerrillamail.com", "guerrillamail.net",
    "guerrillamail.org", "sharklasers.com", "grr.la", "tempmail.com",
    "temp-mail.org", "temp-mail.io", "tempmail.net", "tempmailo.com",
    "tempail.com", "throwawaymail.com", "trashmail.com", "trashmail.net",
    "getnada.com", "nada.email", "maildrop.cc", "dispostable.com",
    "fakeinbox.com", "mailnesia.com", "mintemail.com", "emailondeck.com",
    "moakt.com", "mohmal.com", "mytemp.email", "spamgourmet.com",
    "mailcatch.com", "getairmail.com", "burnermail.io", "discard.email",
    "fakemail.net", "emailfake.com", "inboxkitten.com", "mail.tm",
    "mail.gw", "harakirimail.com", "33mail.com", "spambox.us",
    "tmail.ws", "tmpmail.org", "tmpmail.net", "minuteinbox.com",
    "luxusmail.org", "byom.de", "trbvm.com", "dropmail.me",
}

# Errores de tipeo frecuentes → dominio correcto.
TYPOS = {
    "gmial.com": "gmail.com", "gmal.com": "gmail.com", "gmai.com": "gmail.com",
    "gamil.com": "gmail.com", "gnail.com": "gmail.com", "gmail.co": "gmail.com",
    "gmail.con": "gmail.com", "gmail.cm": "gmail.com", "gmail.om": "gmail.com",
    "gmail.es": "gmail.com", "gmail.com.pe": "gmail.com", "gmaill.com": "gmail.com",
    "gmailcom": "gmail.com", "hotmal.com": "hotmail.com", "hotmial.com": "hotmail.com",
    "hotmail.con": "hotmail.com", "hotmail.co": "hotmail.com", "hotmai.com": "hotmail.com",
    "outlok.com": "outlook.com", "outlook.con": "outlook.com", "yahoo.con": "yahoo.com",
    "yaho.com": "yahoo.com", "yhaoo.com": "yahoo.com", "icloud.con": "icloud.com",
}

_GMAIL_USER = re.compile(r"^[a-z0-9.]+$")

# Respuestas del DNS ya consultadas (dominio → (vence, existe)).
_cache: dict[str, tuple[float, bool]] = {}
_CACHE_SECONDS = 6 * 3600


def _bad(detail: str) -> HTTPException:
    return HTTPException(status_code=422, detail=detail)


def check_format(email: str) -> None:
    """Reglas sin red. Lanza 422 con un mensaje para el vecino."""
    local, _, domain = email.strip().lower().rpartition("@")
    if not local or not domain:
        raise _bad("Revisa tu correo (ejemplo: nombre@gmail.com)")
    if domain in TYPOS:
        raise _bad(f"Revisa tu correo: ¿quisiste decir {local}@{TYPOS[domain]}?")
    if domain in DISPOSABLE_DOMAINS:
        raise _bad(
            "No aceptamos correos temporales. Usa tu correo de siempre "
            "(Gmail, Hotmail, Outlook…)."
        )
    if domain in GMAIL_DOMAINS:
        user = local.split("+", 1)[0]
        if (
            not _GMAIL_USER.match(user)
            or user.startswith(".")
            or user.endswith(".")
            or ".." in user
        ):
            raise _bad(
                "Ese correo de Gmail no es válido: solo lleva letras, números y puntos."
            )
        if not 6 <= len(user.replace(".", "")) <= 30:
            raise _bad("Ese correo de Gmail no es válido: el nombre tiene entre 6 y 30 letras o números.")


def _query(domain: str, record: str) -> dict:
    url = DOH_URL + "?" + urllib.parse.urlencode({"name": domain, "type": record})
    request = urllib.request.Request(url, headers={"Accept": "application/dns-json"})
    with urllib.request.urlopen(request, timeout=4) as response:
        return json.loads(response.read().decode())


def _domain_receives_mail(domain: str) -> bool | None:
    """True/False si el DNS respondió; None si no se pudo saber."""
    try:
        mx = _query(domain, "MX")
        if mx.get("Status") == 3:  # NXDOMAIN: el dominio no existe
            return False
        answers = [a for a in mx.get("Answer", []) if a.get("type") == 15]
        if answers:
            # "MX 0 ." (RFC 7505) = el dominio declara que NO recibe correo.
            return not all(a.get("data", "").strip().endswith(" .") for a in answers)
        # Sin MX, el correo va al registro A del dominio.
        a = _query(domain, "A")
        return bool([r for r in a.get("Answer", []) if r.get("type") == 1])
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return None


def _dns_check_enabled() -> bool:
    return os.getenv("EMAIL_DOMAIN_CHECK", "1") != "0" and os.getenv("AUTH_DEBUG_CODES") != "1"


async def check_domain(email: str) -> None:
    """Rechaza (422) correos de dominios que no existen o no reciben correo. Los proveedores conocidos (Gmail, Outlook…) se aceptan sin consultar DNS."""
    domain = email.strip().lower().rpartition("@")[2]
    if domain in KNOWN_PROVIDERS or not _dns_check_enabled():
        return
    cached = _cache.get(domain)
    if cached and cached[0] > time.monotonic():
        exists = cached[1]
    else:
        exists = await run_in_threadpool(_domain_receives_mail, domain)
        if exists is None:
            return  # DNS caído: no se bloquea a nadie por eso
        _cache[domain] = (time.monotonic() + _CACHE_SECONDS, exists)
    if not exists:
        raise _bad(
            f"El dominio @{domain} no recibe correos. Revisa que esté bien escrito."
        )


async def ensure_real_email(email: str) -> None:
    """Formato + dominio. Úsalo antes de crear una cuenta con correo y contraseña."""
    check_format(email)
    await check_domain(email)
