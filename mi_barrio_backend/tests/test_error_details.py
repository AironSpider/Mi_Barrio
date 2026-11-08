"""Los errores 500 no muestran detalles técnicos en producción (Render).

Uso:  venv\\Scripts\\python.exe tests\\test_error_details.py
"""
import asyncio
import json
import logging
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from starlette.requests import Request  # noqa: E402

from app.core import exceptions  # noqa: E402

REQUEST = Request({"type": "http", "method": "GET", "path": "/x", "headers": [], "query_string": b""})
BOOM = RuntimeError("ProgrammingError: SQL INSERT INTO users")


def body(env: dict) -> dict:
    """Respuesta del manejador de errores con esas variables de entorno."""
    saved = {k: os.environ.pop(k, None) for k in ("RENDER", "API_DEBUG_ERRORS")}
    os.environ.update(env)
    try:
        response = asyncio.run(exceptions.unhandled_exception_handler(REQUEST, BOOM))
        return {"status": response.status_code, **json.loads(response.body)}
    finally:
        for key in ("RENDER", "API_DEBUG_ERRORS"):
            os.environ.pop(key, None)
            if saved[key] is not None:
                os.environ[key] = saved[key]


class ErrorDetailsTest(unittest.TestCase):
    def setUp(self):
        logging.disable(logging.CRITICAL)

    def tearDown(self):
        logging.disable(logging.NOTSET)

    def test_produccion_oculta_el_detalle(self):
        b = body({"RENDER": "true"})
        self.assertEqual(b["status"], 500)
        self.assertNotIn("detail", b)
        self.assertNotIn("hint", b)
        self.assertNotIn("SQL", json.dumps(b))
        self.assertIn("Intenta de nuevo", b["error"])

    def test_en_la_pc_se_ve_el_detalle_para_depurar(self):
        b = body({})
        self.assertIn("SQL INSERT", b["detail"])

    def test_api_debug_errors_lo_muestra_en_produccion(self):
        b = body({"RENDER": "true", "API_DEBUG_ERRORS": "1"})
        self.assertIn("detail", b)


if __name__ == "__main__":
    unittest.main()
