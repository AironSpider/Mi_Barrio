"""Envío de correos (códigos de verificación y de recuperar contraseña).

Usa SMTP. Con Gmail: una cuenta del equipo y una "contraseña de aplicación"
(Cuenta de Google → Seguridad → Verificación en 2 pasos → Contraseñas de aplicaciones).

Variables de entorno (en Render → Environment):
    SMTP_USER       correo que envía, p. ej. mibarrio.app@gmail.com
    SMTP_PASSWORD   la contraseña de aplicación de 16 letras (sin espacios)
    SMTP_HOST       por defecto smtp.gmail.com
    SMTP_PORT       por defecto 587 (STARTTLS)
    SMTP_FROM_NAME  por defecto "Mi Barrio"

Render (plan gratis) BLOQUEA el SMTP ("Network is unreachable"). Por eso, si existe
BREVO_API_KEY, se envía por la API HTTPS de Brevo (gratis, 300 correos/día):
    BREVO_API_KEY       la clave de API de Brevo (SMTP & API → API Keys)
    BREVO_SENDER_EMAIL  remitente verificado en Brevo (por defecto SMTP_USER)

Si no hay ni Brevo ni SMTP, el correo NO se envía: el código se
escribe en los logs del servidor (útil en desarrollo) y la función devuelve False.
"""
from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from starlette.concurrency import run_in_threadpool

logger = logging.getLogger("mi_barrio.email")


BREVO_URL = "https://api.brevo.com/v3/smtp/email"


def _brevo_configured() -> bool:
    return bool(os.getenv("BREVO_API_KEY") and _brevo_sender())


def _brevo_sender() -> str:
    return os.getenv("BREVO_SENDER_EMAIL") or os.getenv("SMTP_USER") or ""


def is_configured() -> bool:
    """True si hay forma de enviar correos: Brevo (BREVO_API_KEY) o SMTP (SMTP_USER y SMTP_PASSWORD)."""
    return _brevo_configured() or bool(os.getenv("SMTP_USER") and os.getenv("SMTP_PASSWORD"))


def _send_brevo_sync(to: str, subject: str, text: str, html: str) -> None:
    body = {
        "sender": {"name": os.getenv("SMTP_FROM_NAME", "Mi Barrio"), "email": _brevo_sender()},
        "to": [{"email": to}],
        "subject": subject,
        "textContent": text,
        "htmlContent": html,
    }
    request = urllib.request.Request(
        BREVO_URL,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "api-key": os.environ["BREVO_API_KEY"].strip(),
            "content-type": "application/json",
            "accept": "application/json",
        },
    )
    # urlopen lanza HTTPError si Brevo responde 4xx/5xx (p. ej. remitente sin verificar).
    with urllib.request.urlopen(request, timeout=15) as response:
        response.read()


def _send_sync(to: str, subject: str, text: str, html: str) -> None:
    user = os.environ["SMTP_USER"]
    password = os.environ["SMTP_PASSWORD"].replace(" ", "")
    host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    port = int(os.getenv("SMTP_PORT", "587"))
    sender_name = os.getenv("SMTP_FROM_NAME", "Mi Barrio")

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = formataddr((sender_name, user))
    message["To"] = to
    message.set_content(text)
    message.add_alternative(html, subtype="html")

    context = ssl.create_default_context()
    if port == 465:
        with smtplib.SMTP_SSL(host, port, context=context, timeout=15) as smtp:
            smtp.login(user, password)
            smtp.send_message(message)
    else:
        with smtplib.SMTP(host, port, timeout=15) as smtp:
            smtp.starttls(context=context)
            smtp.login(user, password)
            smtp.send_message(message)


async def send_email(to: str, subject: str, text: str, html: str) -> bool:
    """True si se envió. Nunca lanza: un correo caído no debe romper el registro."""
    if not is_configured():
        logger.warning("SMTP sin configurar: no se envió '%s' a %s", subject, to)
        return False
    sender = _send_brevo_sync if _brevo_configured() else _send_sync
    try:
        await run_in_threadpool(sender, to, subject, text, html)
        return True
    except urllib.error.HTTPError as error:
        # Brevo explica el motivo en el cuerpo (clave mala, remitente sin verificar…).
        detail = error.read().decode("utf-8", "replace")[:300]
        logger.error("Brevo rechazó el correo '%s' a %s: %s %s", subject, to, error.code, detail)
        return False
    except Exception:  # noqa: BLE001 - se registra y se sigue
        logger.exception("No se pudo enviar el correo '%s' a %s", subject, to)
        return False


def _code_html(title: str, intro: str, code: str, outro: str) -> str:
    return f"""\
<!doctype html>
<html lang="es"><body style="margin:0;background:#F3F4F6;font-family:Arial,sans-serif;color:#1F2937">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:480px;background:#FFFFFF;border-radius:16px;padding:28px">
        <tr><td style="font-size:22px;font-weight:700;color:#1E7A2E">Mi Barrio</td></tr>
        <tr><td style="padding-top:16px;font-size:18px;font-weight:700">{title}</td></tr>
        <tr><td style="padding-top:8px;font-size:15px;line-height:22px">{intro}</td></tr>
        <tr><td align="center" style="padding:24px 0">
          <div style="display:inline-block;font-size:34px;letter-spacing:10px;font-weight:700;
                      background:#E7F1E9;color:#14532D;border-radius:12px;padding:14px 22px">{code}</div>
        </td></tr>
        <tr><td style="font-size:14px;line-height:21px;color:#4B5563">{outro}</td></tr>
      </table>
    </td></tr>
  </table>
</body></html>"""


async def send_verification_code(to: str, name: str, code: str) -> bool:
    """Envía el código de 6 números para confirmar el correo. Si no se pudo enviar, deja el código en los logs y devuelve False."""
    first = (name or "vecino").split(" ")[0]
    subject = f"{code} es tu código de Mi Barrio"
    intro = f"Hola, {first}. Escribe este código en la app para confirmar tu correo:"
    outro = "El código vence en 15 minutos. Si no creaste una cuenta en Mi Barrio, ignora este correo."
    text = f"{intro}\n\n{code}\n\n{outro}"
    sent = await send_email(to, subject, text, _code_html("Confirma tu correo", intro, code, outro))
    if not sent:
        logger.warning("Código de verificación para %s: %s", to, code)
    return sent


async def send_password_reset_code(to: str, name: str, code: str) -> bool:
    """Envía el código de 6 números para cambiar la contraseña. Si no se pudo enviar, deja el código en los logs y devuelve False."""
    first = (name or "vecino").split(" ")[0]
    subject = f"{code} es tu código para cambiar la contraseña"
    intro = f"Hola, {first}. Pediste cambiar tu contraseña de Mi Barrio. Tu código es:"
    outro = ("El código vence en 15 minutos. Si no pediste este cambio, ignora este correo: "
             "tu contraseña sigue igual.")
    text = f"{intro}\n\n{code}\n\n{outro}"
    sent = await send_email(to, subject, text, _code_html("Cambiar contraseña", intro, code, outro))
    if not sent:
        logger.warning("Código para cambiar la contraseña de %s: %s", to, code)
    return sent
