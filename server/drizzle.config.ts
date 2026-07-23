import { defineConfig } from 'drizzle-kit';

// Load server/.env so DATABASE_URL is available to drizzle-kit (it does not read
// .env on its own). Missing file is fine when the env is provided directly.
try {
  process.loadEnvFile();
} catch {
  // no .env — rely on the ambient environment
}

export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env.DATABASE_URL ?? '',
  },
});
