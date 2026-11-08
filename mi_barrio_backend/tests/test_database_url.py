import unittest

from app.core.database_url import normalize_database_url


class DatabaseUrlTests(unittest.TestCase):
    def test_normalizes_neon_asyncpg_ssl_url(self):
        result = normalize_database_url(
            "postgresql://demo:secret@ep-example-pooler.neon.tech/app"
            "?sslmode=require&channel_binding=require"
        )

        self.assertTrue(result.startswith("postgresql+asyncpg://"))
        self.assertIn("ssl=require", result)
        self.assertNotIn("sslmode", result)
        self.assertNotIn("channel_binding", result)

    def test_normalizes_legacy_postgres_scheme(self):
        result = normalize_database_url("postgres://demo:secret@localhost/app")

        self.assertTrue(result.startswith("postgresql+asyncpg://"))
        self.assertIn("@localhost/app", result)

    def test_preserves_existing_asyncpg_ssl_parameter(self):
        result = normalize_database_url(
            "postgresql+asyncpg://demo:secret@localhost/app?ssl=verify-full"
        )

        self.assertTrue(result.startswith("postgresql+asyncpg://"))
        self.assertIn("ssl=verify-full", result)


if __name__ == "__main__":
    unittest.main()
