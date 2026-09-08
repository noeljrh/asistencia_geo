-- db/init/001_schema_and_seed.sql
-- Esquema básico: users y locations

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  email TEXT UNIQUE,
  name TEXT NOT NULL,
  password_hash TEXT,
  role TEXT NOT NULL DEFAULT 'user',
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verification_token TEXT,
  reset_token TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  metadata JSONB
);

CREATE TABLE IF NOT EXISTS locations (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  accuracy DOUBLE PRECISION,
  timestamp TIMESTAMPTZ,
  maps_url TEXT,
  status TEXT DEFAULT 'RECEIVED',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);

-- Seed: usuario de prueba (contraseña: "devpassword" — reemplaza por hash real si quieres)
INSERT INTO users (email, name, password_hash, role, is_verified)
VALUES ('dev@local', 'Usuario Dev', 'DEV_PASSWORD_PLACEHOLDER', 'supervisor', true)
ON CONFLICT (email) DO NOTHING;
