# Cuentas reales: Google, código al correo y recuperar contraseña

Qué hace la app ahora:

| Función | Cómo se ve |
| --- | --- |
| Entrar con Google | Botón **"Continuar con Google"** en el login y **"Registrarme con Google"** en el registro (solo en el celular). La primera vez pide el código del barrio y si es vecino o comerciante. |
| Confirmar el correo | Al crear cuenta con contraseña llega un **código de 6 números** al correo. La app no deja entrar hasta escribirlo. Se puede reenviar cada 60 s. |
| Recuperar contraseña | **"¿Olvidaste tu contraseña?"** en el login → llega un código → contraseña nueva → entra solo. También sirve para que quien entró con Google cree una contraseña. |
| Validaciones | Correo válido, contraseña de 8+ con letras y números, no acepta las muy comunes (12345678…), "Repite la contraseña", barra de fuerza (Débil → Fuerte). |

Las cuentas que ya existían **no se bloquean**: quedan como verificadas.

Para que funcione de verdad faltan **3 configuraciones** (10–15 minutos). Sin ellas, la app funciona igual que antes y el botón de Google avisa que no está configurado.

---

## 1. Correo: Gmail con contraseña de aplicación

1. Usa una cuenta Gmail del equipo (ej. `mibarrio.app@gmail.com`).
2. Activa la **verificación en 2 pasos**: https://myaccount.google.com/security
3. Crea una **contraseña de aplicación**: https://myaccount.google.com/apppasswords → nombre "Mi Barrio" → copia las 16 letras.
4. En **Render → mi-barrio-backend → Environment**, agrega:

| Variable | Valor |
| --- | --- |
| `SMTP_USER` | el correo, ej. `mibarrio.app@gmail.com` |
| `SMTP_PASSWORD` | las 16 letras (sin espacios) |

Opcionales: `SMTP_FROM_NAME` (por defecto "Mi Barrio"), `SMTP_HOST` (`smtp.gmail.com`), `SMTP_PORT` (`587`).
Gmail permite ~500 correos al día: de sobra para la demo.

## 2. Google Cloud: los "client ID"

1. Entra a https://console.cloud.google.com/ y crea el proyecto **Mi Barrio**.
2. **APIs y servicios → Pantalla de consentimiento de OAuth**: tipo *Externo*, nombre "Mi Barrio", correo de soporte del equipo. En *Usuarios de prueba* agrega los correos que usarán en la demo (mientras la app esté "en prueba", solo ellos pueden entrar).
3. **Credenciales → Crear credenciales → ID de cliente de OAuth → Aplicación web** → nombre "Mi Barrio servidor". Copia el **ID de cliente** (`xxxx.apps.googleusercontent.com`). Este es el **Web client ID**.
4. **Crear credenciales → ID de cliente de OAuth → Android**:
   - Nombre del paquete: `com.example.mi_barrio_app`
   - Huella SHA-1: la de la PC que **compila la APK** (Dev 2). Se saca con:

```
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

   (keytool está en `C:\Program Files\Android\Android Studio\jbr\bin\`). Copia la línea `SHA1:`.
   Si otra PC compila la APK, agrega otro cliente Android con su SHA-1.

5. En **Render → Environment** agrega:

| Variable | Valor |
| --- | --- |
| `GOOGLE_CLIENT_IDS` | el **Web client ID** del paso 3 |

## 3. Compilar la APK con Google

```
flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
```

Va el **Web client ID** (el del paso 3, no el de Android).

---

## Probar en local (sin Gmail ni Google)

```
cd mi_barrio_backend
venv\Scripts\python.exe -m alembic upgrade head
set AUTH_DEBUG_CODES=1
venv\Scripts\python.exe -m uvicorn app.main:app --port 8000
```

Sin `SMTP_USER`, el código se escribe en los logs del servidor (`Código de verificación para …`).
Con `AUTH_DEBUG_CODES=1` además vuelve en la respuesta (solo si el correo NO está configurado, nunca en producción).

Pruebas: `venv\Scripts\python.exe scripts\test_auth_accounts.py http://127.0.0.1:8000` (27 pruebas).

## Rutas nuevas del backend (públicas)

| Ruta | Para qué |
| --- | --- |
| `POST /api/v1/auth/google` | `{id_token, join_code?, role?}` → entra o crea la cuenta. **428** = cuenta nueva, falta `join_code`. |
| `POST /api/v1/auth/email/send-code` | Reenvía el código de verificación. |
| `POST /api/v1/auth/email/verify` | `{email, code}` → confirma el correo y devuelve la sesión. |
| `POST /api/v1/auth/password/forgot` | Envía el código para cambiar la contraseña. |
| `POST /api/v1/auth/password/reset` | `{email, code, new_password}` → cambia la contraseña y entra. |

Seguridad: los códigos vencen en 15 min, se guardan como huella HMAC (nunca el código), 5 intentos máximo, 1 envío por minuto y 5 por hora. Pedir un código no revela si el correo existe. El token de Google se valida con Google (`aud`, `iss`, `exp`, `email_verified`).
Migración: `f9e8d7c6b5a4` (después de `d4e5f6a7b8c9`).
