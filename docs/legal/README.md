# Documentación legal y de usuario: Mi Barrio

**Titular:** NetSurex · **Equipo:** Root Crew Code · **Contacto:** mibarrio.app.peru@gmail.com

Todos los documentos están escritos **según lo que la app hace de verdad**, revisado en el código el 8 de noviembre de 2026: qué datos guarda, quién los ve y qué proveedores usa. Siguen la ley peruana: Ley N.° 29733 de datos personales y Ley N.° 29571 del consumidor.

## Documentos

| Documento | Archivo | ¿Se ve en la app? |
| --- | --- | --- |
| Términos y condiciones | [terminos_y_condiciones.md](terminos_y_condiciones.md) | ✅ |
| Política de privacidad | [politica_de_privacidad.md](politica_de_privacidad.md) | ✅ |
| Términos de uso de la información (consentimiento) | [terminos_de_uso_de_informacion.md](terminos_de_uso_de_informacion.md) | ✅ |
| Política de uso y normas de la comunidad | [politica_de_uso.md](politica_de_uso.md) | ✅ |
| Política de cookies y almacenamiento | [politica_de_cookies.md](politica_de_cookies.md) | ✅ |
| Contrato de licencia (EULA) | [eula.md](eula.md) | ✅ |
| Aviso legal | [aviso_legal.md](aviso_legal.md) | ✅ |
| **Manual de usuario** | [../manual_de_usuario.md](../manual_de_usuario.md) | ✅ |
| Guía técnica de cuentas reales | [../CUENTAS_REALES.md](../CUENTAS_REALES.md) | No (es para el equipo) |

**Política de devoluciones y reembolsos:** no aplica, porque la app es gratis y no tiene pagos. Está explicado en los Términos, sección 4.

---

## Qué hace la app con estos documentos

| Requisito | Estado | Dónde |
| --- | --- | --- |
| Aceptar los términos al crear la cuenta | ✅ Listo | Registro y login (botón de Google): *"Al crear tu cuenta aceptas los Términos y condiciones, la Política de privacidad y las Normas de la comunidad"*, con enlaces |
| Ver los documentos dentro de la app | ✅ Listo | **Tú → Términos y privacidad**. Funciona sin internet. |
| Borrar la cuenta desde la app | ✅ Listo | **Tú → Eliminar mi cuenta**: se confirma escribiendo ELIMINAR. Backend: `DELETE /api/v1/users/me` |
| Política de privacidad en una página web pública | 🔜 Próximamente | Hará falta cuando la app esté en Google Play |

### Cómo funciona "Eliminar mi cuenta"
- Borra los datos personales de la cuenta: nombre, correo, contraseña, teléfono, WhatsApp, redes, dirección, foto y la conexión con Google.
- Oculta en todos los celulares sus servicios, favores, comentarios, calificaciones, mensajes y reportes, y les quita las fotos.
- La sesión deja de servir y el correo queda libre para crear otra cuenta.
- El **administrador del barrio** no puede borrarse desde la app: el servidor le pide escribir al equipo para pasar el cargo.
- Prueba: `venv\Scripts\python.exe scripts\test_delete_account.py http://127.0.0.1:8000` (9 pruebas).

---

## ⚠️ Si cambias un documento

La app muestra **una copia** de estos archivos en `mi_barrio_app/assets/legal/`. Después de editar algo aquí, cópialo también allá:

```
copy docs\legal\*.md mi_barrio_app\assets\legal\
copy docs\manual_de_usuario.md mi_barrio_app\assets\legal\
del mi_barrio_app\assets\legal\README.md
```

Una prueba de la app (`test/features/legal`) revisa que estén todos y que no queden datos por llenar.

---

## Datos clave usados en los documentos (revisados en el código)

- **Datos de cuenta:** nombre, correo, contraseña (hash PBKDF2), rol y código de barrio. Opcionales: teléfono, WhatsApp, foto, referencia de dirección y redes del negocio.
- **Google:** solo correo, nombre e identificador. Nunca la contraseña.
- **Visible para vecinos:** nombre corto ("Rosa C."). El teléfono y el WhatsApp solo aparecen en los servicios que la persona ofrece. El correo nunca es visible.
- **Códigos:** HMAC, 15 min, 5 intentos, 1 por minuto y 5 por hora, sin revelar si el correo existe.
- **Sesión:** 24 h. Al cerrar sesión se borran los datos del celular.
- **Moderación:** 7 motivos de reporte. Con 3 reportes de vecinos distintos se oculta la publicación, y el administrador del barrio la restaura o elimina.
- **Proveedores:** Google, Render, Neon, Brevo o Gmail, y OpenStreetMap.
- **Sin** publicidad, analítica ni rastreo.
- **Permisos:** internet y ubicación (solo con la app abierta). Cámara y galería solo al subir una foto.
- **RUC de NetSurex:** `10726848225`.
