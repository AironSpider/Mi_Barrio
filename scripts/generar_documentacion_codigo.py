"""Genera docs/DOCUMENTACION_DEL_CODIGO.md a partir de los comentarios del código.

Lee los docstrings del backend (Python) y los comentarios /// de la app (Dart),
así el documento siempre dice lo mismo que el código. Volver a correrlo después
de cambiar comentarios:

    python scripts/generar_documentacion_codigo.py
"""
from __future__ import annotations

import ast
import datetime
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "mi_barrio_app" / "lib"
BACKEND = ROOT / "mi_barrio_backend" / "app"
OUT = ROOT / "docs" / "DOCUMENTACION_DEL_CODIGO.md"

ROUTE = re.compile(r"@(\w+)\.(get|post|put|patch|delete|websocket)\(\s*[\"']([^\"']*)[\"']")
PREFIX = re.compile(r"(\w+)\s*=\s*APIRouter\([^)]*prefix\s*=\s*[\"']([^\"']+)[\"']")

APP_SECTIONS = {
    "main.dart": "Arranque de la app",
    "core": "Núcleo (core): base de datos local, sincronización, red, sesión y diseño",
    "shared": "Utilidades compartidas",
    "features/auth_barrio": "Cuentas: login, registro, Google, correo y administradores",
    "features/chat": "Chat entre vecinos",
    "features/emergency_support": "Modo emergencia: pedir ayuda, mapa y grupos de apoyo",
    "features/legal": "Documentos legales dentro de la app",
    "features/moderation": "Moderación: reportes y cuentas suspendidas",
    "features/onboarding_tutorial": "Tutorial de bienvenida",
    "features/profile_me": "Pestaña Tú: perfil, historial y cuenta",
    "features/proximity_services": "Servicios del barrio",
    "features/solidarity_network": "Apoyo: muro de favores",
}
BACKEND_SECTIONS = {
    "main.py": "Arranque de la API",
    "core": "Núcleo (core): seguridad, base de datos, correo, Google y errores",
    "shared": "Piezas compartidas",
    "features/auth_barrio": "Cuentas, barrios y perfil",
    "features/chat": "Chat entre vecinos",
    "features/emergency_support": "Modo emergencia",
    "features/moderation": "Moderación",
    "features/proximity_services": "Servicios del barrio",
    "features/solidarity_network": "Muro de apoyo",
    "features/sync_engine": "Sincronización offline-first",
}


def section_of(rel: str, sections: dict[str, str]) -> str:
    for key in sorted(sections, key=len, reverse=True):
        if rel == key or rel.startswith(key + "/"):
            return key
    return rel.split("/")[0]


def clean(text: str) -> str:
    """Comentario en una línea de Markdown por párrafo (sin sangría).

    Quita los bloques de código (```) y convierte las listas "- x" en "• x".
    """
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    text = re.sub(r"\n\s*[-*]\s+", " • ", text)
    parts = [" ".join(p.split()) for p in re.split(r"\n\s*\n", text.strip())]
    return "\n\n".join(p for p in parts if p)


def dart_name(sig: str) -> str:
    """Nombre declarado en una firma de Dart (para saltar los privados)."""
    m = re.search(r"(?:class|enum|mixin|extension|typedef)\s+(\w+)", sig)
    if m:
        return m.group(1)
    m = re.search(r"([A-Za-z_]\w*)\s*(?:\(|=|$)", sig)
    return m.group(1) if m else sig


# ── Backend (Python) ──────────────────────────────────────────────────────

def python_file(path: Path) -> dict:
    src = path.read_text(encoding="utf-8")
    tree = ast.parse(src)
    lines = src.splitlines()
    prefixes = {m.group(1): m.group(2) for m in PREFIX.finditer(src)}
    items = []

    def route_of(node) -> str | None:
        for deco in node.decorator_list:
            m = ROUTE.search(lines[deco.lineno - 1])
            if m:
                router, method, sub = m.groups()
                return f"{method.upper()} {prefixes.get(router, '')}{sub}"
        return None

    def visit(nodes, owner: str | None = None):
        for node in nodes:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                if node.name.startswith("_"):
                    continue
                doc = ast.get_docstring(node)
                kind = "clase" if isinstance(node, ast.ClassDef) else "función"
                name = f"{owner}.{node.name}" if owner else node.name
                if doc:
                    items.append({"name": name, "kind": kind, "route": route_of(node), "doc": clean(doc)})
                if isinstance(node, ast.ClassDef):
                    visit(node.body, node.name)

    visit(tree.body)
    return {"doc": clean(ast.get_docstring(tree) or ""), "items": items}


# ── App (Dart) ────────────────────────────────────────────────────────────

DECL = re.compile(
    r"^(?P<indent>\s*)(?:@\w+\s*)*"
    r"(?:(?:abstract|interface|sealed|final|base|static|const|factory|late|external)\s+)*"
    r"(?P<sig>(?:class|enum|mixin|extension|typedef)\s+\w+.*|[\w<>?,\s\[\]]+?\s+\w+\s*(?:\(|=|;|=>).*|\w+\s*\(.*)$"
)


def dart_signature(line: str) -> str:
    sig = line.strip()
    for stop in (" {", "{", " =>", " = "):
        if stop in sig:
            sig = sig.split(stop)[0]
    return sig.rstrip(" ({;,").strip()


def dart_file(path: Path) -> dict:
    lines = path.read_text(encoding="utf-8").splitlines()
    header: list[str] = []
    items = []
    i = 0
    # Comentario al inicio del archivo (// o /// antes del primer import o declaración).
    while i < len(lines) and (lines[i].strip().startswith("//") or not lines[i].strip()):
        if lines[i].strip().startswith("//"):
            header.append(lines[i].strip().lstrip("/").strip())
        i += 1
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith("///"):
            block = []
            while i < len(lines) and lines[i].strip().startswith("///"):
                block.append(lines[i].strip()[3:].strip())
                i += 1
            while i < len(lines) and lines[i].strip().startswith("@"):
                i += 1
            if i >= len(lines):
                break
            decl = lines[i]
            indent = len(decl) - len(decl.lstrip())
            if indent > 2:  # solo nivel superior y miembros directos de clases
                continue
            sig = dart_signature(decl)
            if not sig or sig.startswith(("import", "export", "part", "library")):
                continue
            if dart_name(sig).startswith("_") or re.search(r"\s_\w*\s*(?:=|;|$)", sig):
                continue  # lo privado no se documenta hacia afuera
            name_match = re.search(r"(?:class|enum|mixin|extension|typedef)\s+(\w+)", sig)
            kind = "tipo" if name_match else ("miembro" if indent else "función/valor")
            items.append({
                "sig": sig,
                "member": indent > 0,
                "kind": kind,
                "doc": clean("\n".join(block)),
            })
        else:
            i += 1
    top_doc = clean("\n".join(header)) if header else ""
    if not top_doc and items and not items[0]["member"]:
        top_doc = ""
    return {"doc": top_doc, "items": items}


# ── Documento ─────────────────────────────────────────────────────────────

def anchor(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    return re.sub(r"\s+", "-", text.strip())


def build() -> str:
    app_files = sorted(p for p in APP.rglob("*.dart") if not p.name.endswith(".g.dart"))
    py_files = sorted(p for p in BACKEND.rglob("*.py") if "__pycache__" not in p.parts and p.name != "__init__.py")

    app_data = {p: dart_file(p) for p in app_files}
    py_data = {p: python_file(p) for p in py_files}
    n_app_items = sum(len(d["items"]) for d in app_data.values())
    n_py_items = sum(len(d["items"]) for d in py_data.values())
    routes = [it for d in py_data.values() for it in d["items"] if it["route"]]

    out: list[str] = []
    w = out.append
    today = datetime.date.today().strftime("%d/%m/%Y")
    w("# Mi Barrio: documentación del código")
    w("")
    w(f"**Generado:** {today} desde los comentarios del código con `scripts/generar_documentacion_codigo.py`.")
    w("**Titular:** NetSurex · **Equipo:** Root Crew Code · Hackathon UTP – El Comercio 2026")
    w("")
    w("Este documento junta **todos los comentarios de documentación** del proyecto: los `///` de la app "
      "(Flutter/Dart) y los docstrings del backend (FastAPI/Python). Si cambias un comentario en el código, "
      "vuelve a correr el script y este documento se actualiza solo.")
    w("")
    w("| | Archivos | Elementos documentados |")
    w("| --- | --- | --- |")
    w(f"| App (Flutter) | {len(app_files)} | {n_app_items} |")
    w(f"| Backend (FastAPI) | {len(py_files)} | {n_py_items} (de ellos {len(routes)} rutas de la API) |")
    w("")
    w("## Índice")
    w("")
    w("1. [Cómo está hecho Mi Barrio](#cómo-está-hecho-mi-barrio)")
    w("2. [Rutas de la API](#rutas-de-la-api)")
    w("3. [App (Flutter)](#app-flutter)")
    for key, title in APP_SECTIONS.items():
        w(f"   - [{title}](#{anchor('App: ' + title)})")
    w("4. [Backend (FastAPI)](#backend-fastapi)")
    for key, title in BACKEND_SECTIONS.items():
        w(f"   - [{title}](#{anchor('Backend: ' + title)})")
    w("")
    w("---")
    w("")
    w("## Cómo está hecho Mi Barrio")
    w("")
    w("```")
    w("Celular (Flutter)                                 Servidor (Render)")
    w("┌──────────────────────────────┐                  ┌────────────────────────────┐")
    w("│ Pantallas (features/*)       │                  │ FastAPI (app/features/*)   │")
    w("│   ↓ guardan primero aquí     │   push / pull    │   TenantMiddleware:        │")
    w("│ SQLite local + cola outbox   │ ───────────────▶ │   token + X-Tenant-ID      │")
    w("│   ↑ SyncCoordinator          │ ◀─────────────── │ PostgreSQL (Neon)          │")
    w("│ Sesión (SharedPreferences)   │   HTTPS + JWT    │ Correo: Brevo / Gmail      │")
    w("└──────────────────────────────┘                  │ Google: tokeninfo          │")
    w("                                                  └────────────────────────────┘")
    w("```")
    w("")
    w("- **Offline-first:** todo lo que hace el vecino se guarda primero en el celular (SQLite) y entra a "
      "una cola (`sync_outbox`). Cuando hay internet, `SyncCoordinator` sube la cola (**push**) y baja lo "
      "nuevo del barrio (**pull**). Los choques se resuelven con *gana el último* (LWW, por `updated_at`).")
    w("- **Por barrio (multi-tenant):** cada petición lleva el token de sesión y `X-Tenant-ID`; el "
      "servidor no deja leer ni escribir en otro barrio.")
    w("- **Cuentas:** correo + contraseña (PBKDF2) o Google; código de 6 números al correo para confirmar "
      "y para recuperar la contraseña; borrar la cuenta desde la app.")
    w("- **Roles:** vecino, comerciante, administrador del barrio y superadministrador de la plataforma.")
    w("")
    w("---")
    w("")
    w("## Rutas de la API")
    w("")
    w("La misma información se ve en Swagger: `/docs` del servidor.")
    w("")
    w("| Ruta | Qué hace |")
    w("| --- | --- |")
    for it in sorted(routes, key=lambda r: (r["route"].split(" ", 1)[1], r["route"])):
        first = it["doc"].split("\n\n")[0].replace("|", "\\|")
        w(f"| `{it['route']}` | {first} |")
    w("")
    w("---")
    w("")

    def emit(title: str, data: dict, base: Path, sections: dict[str, str], prefix: str, lang: str):
        w(f"## {title}")
        w("")
        grouped: dict[str, list[Path]] = {}
        for p in data:
            rel = p.relative_to(base).as_posix()
            grouped.setdefault(section_of(rel, sections), []).append(p)
        for key, stitle in sections.items():
            files = grouped.get(key, [])
            if not files:
                continue
            w(f"### {prefix}: {stitle}")
            w("")
            for p in files:
                d = data[p]
                rel = p.relative_to(ROOT).as_posix()
                if not d["doc"] and not d["items"]:
                    continue
                w(f"#### `{rel}`")
                w("")
                if d["doc"]:
                    w(d["doc"])
                    w("")
                for it in d["items"]:
                    if lang == "dart":
                        label = f"`{it['sig']}`"
                        bullet = "  -" if it["member"] else "-"
                    else:
                        label = f"`{it['name']}`" + (f" · **{it['route']}**" if it["route"] else "")
                        bullet = "  -" if "." in it["name"] else "-"
                    doc = it["doc"].replace("\n\n", " ")
                    w(f"{bullet} {label}: {doc}")
                w("")

    emit("App (Flutter)", app_data, APP, APP_SECTIONS, "App", "dart")
    w("---")
    w("")
    emit("Backend (FastAPI)", py_data, BACKEND, BACKEND_SECTIONS, "Backend", "py")
    w("---")
    w("")
    w("Documentos relacionados: [Manual de usuario](manual_de_usuario.md) · "
      "[Documentos legales](legal/README.md) · [Guía de cuentas reales](CUENTAS_REALES.md)")
    w("")
    return "\n".join(out)


if __name__ == "__main__":
    OUT.write_text(build(), encoding="utf-8")
    print(f"Listo: {OUT.relative_to(ROOT)}")
