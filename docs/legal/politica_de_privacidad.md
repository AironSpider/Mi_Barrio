# Política de Privacidad

**Mi Barrio**
**Última actualización:** 8 de noviembre de 2026

En **Mi Barrio** cuidamos tus datos. Esta política explica, en palabras simples, **qué datos usamos, para qué, quién los ve, dónde se guardan y cómo puedes pedir que los cambiemos o borremos**.

Se aplica a la aplicación móvil Mi Barrio y a su servidor. Cumple con la **Ley N.° 29733, Ley de Protección de Datos Personales del Perú**, y su Reglamento.

---

## 1. Quién es responsable de tus datos

| | |
| --- | --- |
| Responsable | **NetSurex** (equipo **Root Crew Code**) (ver el [Aviso legal](aviso_legal.md)) |
| Correo de contacto | **mibarrio.app.peru@gmail.com** |
| País | Perú |

---

## 2. Qué datos recopilamos

### 2.1 Datos que tú nos das

| Dato | Cuándo | ¿Obligatorio? |
| --- | --- | --- |
| Nombre completo | Al crear tu cuenta | Sí |
| Correo electrónico | Al crear tu cuenta | Sí |
| Contraseña | Si creas la cuenta con correo | Sí (si no usas Google) |
| Código de tu barrio | Al crear tu cuenta | Sí |
| Rol: vecino o comerciante | Al crear tu cuenta | Sí |
| Teléfono y WhatsApp | Si los agregas en "Editar perfil" | No |
| Correo de contacto, Facebook, Instagram | Si los agregas en tu perfil de negocio | No |
| Foto de perfil o de negocio | Si la subes | No |
| Referencia de dirección | Si la escribes | No |
| Publicaciones: servicios, pedidos u ofertas de ayuda, fotos, precios | Cuando publicas | No |
| Mensajes del chat | Cuando escribes a otro vecino | No |
| Comentarios, calificaciones (estrellas) y respuestas | Cuando opinas sobre un servicio o un favor | No |
| Reportes de contenido | Cuando reportas una publicación | No |
| Reportes de personas vulnerables en emergencia | Cuando pides ayuda para alguien en modo emergencia | No |

### 2.2 Datos que recibimos de Google (solo si usas "Continuar con Google")

Google nos confirma **tu correo, tu nombre y un identificador interno de tu cuenta de Google**.

**Nunca recibimos tu contraseña de Google.** Tampoco usamos tu foto ni tus contactos de Google.

### 2.3 Ubicación

- La app pide permiso de **ubicación (GPS)** para mostrarte servicios y pedidos de ayuda **cerca de ti**, y para ubicar en el mapa lo que publicas.
- Cuando publicas algo, guardamos **el punto del mapa de esa publicación**, no tu recorrido.
- **No seguimos tu ubicación en segundo plano.** Solo se usa mientras usas la app.
- Puedes negar el permiso. La app seguirá funcionando y usará el centro de tu barrio como referencia.

### 2.4 Datos técnicos

- **Registros del servidor (logs):** fecha y hora, dirección IP y la acción pedida. Sirven para la seguridad y para arreglar errores.
- **Códigos de seguridad:** guardamos solo una "huella" cifrada (HMAC) del código de 6 números, nunca el código. Vence en **15 minutos**.

### 2.5 Lo que NO recopilamos

- No usamos publicidad ni identificadores de publicidad.
- No usamos herramientas de analítica ni de rastreo (por ejemplo, Google Analytics o píxeles).
- No accedemos a tus contactos, llamadas, SMS, micrófono ni archivos. La cámara y la galería se usan **solo** cuando tú eliges subir una foto.

---

## 3. Para qué usamos tus datos

| Finalidad | Datos que usa |
| --- | --- |
| Crear tu cuenta e iniciar sesión | Nombre, correo, contraseña o Google |
| Confirmar tu correo y recuperar tu contraseña | Correo y código de 6 números |
| Ponerte en tu barrio | Código del barrio |
| Mostrar y publicar servicios y pedidos de ayuda cerca | Ubicación de las publicaciones, contenido publicado |
| Que otros vecinos te contacten por un servicio | Teléfono o WhatsApp (solo si los diste) |
| Chat entre vecinos | Mensajes |
| Modo emergencia: coordinar ayuda en el barrio | Reportes, ubicación, grupos de apoyo |
| Moderación: ocultar contenido que infringe las normas | Reportes de contenido |
| Seguridad y prevención de fraude | Logs, intentos de inicio de sesión |

**No vendemos, alquilamos ni comercializamos tus datos personales.**

**Base legal:**
- tu **consentimiento**, que das al crear tu cuenta y que puedes retirar cuando quieras;
- la **ejecución del servicio** que pediste.

---

## 4. Quién ve tus datos

| Dato | Quién lo ve |
| --- | --- |
| Tu nombre | Los vecinos de **tu barrio**, en versión corta: nombre + inicial ("Rosa C.") |
| Teléfono y WhatsApp | Los vecinos de tu barrio, **solo** en los servicios que tú ofreces |
| Tus publicaciones, fotos, comentarios y calificaciones | Los vecinos de tu barrio |
| Tus mensajes de chat | Solo la otra persona de la conversación |
| Tu correo, tu dirección y tu perfil completo | **Solo tú** |
| Reportes de contenido | El administrador del barrio. La persona reportada **no** sabe quién la reportó. |

Los datos de un barrio **no se muestran en otros barrios.**

---

## 5. Con quién compartimos datos (proveedores)

Solo usamos proveedores necesarios para que la app funcione:

| Proveedor | Para qué | Datos |
| --- | --- | --- |
| **Google** (Google Identity) | "Continuar con Google" | Correo, nombre, identificador de Google |
| **Render** | Servidor donde funciona la app | Todos los datos pasan por aquí |
| **Neon** | Base de datos (PostgreSQL) | Datos de cuenta y contenido |
| **Brevo** o **Gmail** | Enviar los códigos al correo | Correo, nombre y el código |
| **OpenStreetMap** | Imágenes del mapa | Tu dirección IP y la zona del mapa que miras |

Algunos de estos proveedores tienen servidores **fuera del Perú** (por ejemplo, en Estados Unidos o Europa). Al aceptar esta política, consientes este **flujo transfronterizo**. Solo trabajamos con proveedores que cuentan con medidas de seguridad adecuadas.

Podemos entregar datos a una autoridad **solo** si la ley lo exige.

---

## 6. Cómo protegemos tus datos

- Toda la comunicación entre la app y el servidor va **cifrada (HTTPS)**.
- Las contraseñas se guardan con **hash PBKDF2**, nunca en texto. Nadie del equipo puede verlas.
- Los códigos de verificación se guardan como **huella HMAC**. Duran **15 minutos** y permiten **5 intentos**. Se puede pedir **1 por minuto** y **5 por hora**.
- Al pedir un código, la app **no revela** si un correo tiene cuenta.
- La sesión dura **24 horas** y luego hay que volver a entrar.
- Cada barrio está **separado**: un vecino no puede ver datos de otro barrio.

---

## 7. Datos guardados en tu celular

Para que funcione **sin internet**, la app guarda en tu teléfono una copia de los datos de tu barrio, tu sesión y tus cambios pendientes de enviar. Más detalle en la [Política de cookies y almacenamiento](politica_de_cookies.md).

Al **cerrar sesión**, se borran tu sesión y los datos de tu barrio del celular. Si tienes cambios sin enviar, la app te avisa antes.

---

## 8. Cuánto tiempo guardamos tus datos

| Dato | Tiempo |
| --- | --- |
| Cuenta y perfil | Mientras tengas la cuenta |
| Publicaciones, comentarios y mensajes | Mientras tengas la cuenta, o hasta que los borres |
| Códigos de verificación | 15 minutos (luego no sirven) |
| Logs del servidor | El tiempo que los guarda el proveedor (Render), normalmente unos días |

Cuando borras una publicación, **deja de mostrarse de inmediato** en todos los celulares del barrio.

**Cuando borras tu cuenta** (en **Tú → Eliminar mi cuenta**):
- se borran tu nombre, correo, contraseña, teléfono, WhatsApp, redes, dirección, foto y la conexión con Google;
- tus servicios, favores, comentarios, calificaciones, mensajes y reportes dejan de verse para todos, y se borran sus fotos;
- tu correo queda libre por si quieres crear otra cuenta más adelante.

---

## 9. Tus derechos (ARCO)

Puedes pedir en cualquier momento:

- **Acceso:** saber qué datos tenemos de ti.
- **Rectificación:** corregir datos. Casi todo lo puedes cambiar tú en **Tú → Editar perfil**.
- **Cancelación:** borrar tu cuenta y tus datos. **Lo puedes hacer tú mismo** en **Tú → Eliminar mi cuenta**: es inmediato.
- **Oposición:** que dejemos de usar un dato para una finalidad.

**Cómo pedir lo demás:** escribe a **mibarrio.app.peru@gmail.com** desde el correo de tu cuenta, con el asunto **"Derechos ARCO"** y lo que quieres. Respondemos en un máximo de **10 días hábiles** (acceso) o **20 días hábiles** (otros derechos), como manda la ley.

Si no estás conforme con la respuesta, puedes reclamar ante la **Autoridad Nacional de Protección de Datos Personales** del Ministerio de Justicia y Derechos Humanos.

---

## 10. Menores de edad

Mi Barrio es para personas de **14 años o más**. Si tienes menos de 14 años, necesitas permiso de tu madre, padre o tutor. Si sabemos que una cuenta es de un menor de 14 años sin ese permiso, la borraremos.

---

## 11. Cambios en esta política

Si cambiamos algo importante, te avisaremos **en la app o por correo** antes de que empiece a aplicarse. La fecha de arriba indica la última versión.

---

## 12. Contacto

Preguntas sobre tus datos: **mibarrio.app.peru@gmail.com**

Documentos relacionados: [Términos y condiciones](terminos_y_condiciones.md) · [Términos de uso de la información](terminos_de_uso_de_informacion.md) · [Política de cookies y almacenamiento](politica_de_cookies.md)
