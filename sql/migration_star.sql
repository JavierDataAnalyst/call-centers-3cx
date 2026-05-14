-- ============================================================
-- Migration: Add dim_direction and dim_call_status
-- Run in Supabase → SQL Editor
-- ============================================================

-- ── dim_direction ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_direction (
    direction_id TEXT PRIMARY KEY,
    tipo         TEXT NOT NULL,
    es_entrante  BOOLEAN
);

INSERT INTO dim_direction (direction_id, tipo, es_entrante) VALUES
    ('Inbound',  'Inbound',  true),
    ('Outbound', 'Outbound', false),
    ('Internal', 'Internal', false)
ON CONFLICT DO NOTHING;

-- ── dim_call_status ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_call_status (
    status_id     TEXT PRIMARY KEY,
    nombre        TEXT NOT NULL,
    es_contactada BOOLEAN,
    categoria     TEXT     -- 'Exitosa' | 'Perdida' | 'Transferida' | 'Ocupada'
);

INSERT INTO dim_call_status (status_id, nombre, es_contactada, categoria) VALUES
    ('Answered',    'Answered',    true,  'Exitosa'),
    ('Unanswered',  'Unanswered',  false, 'Perdida'),
    ('No Answer',   'No Answer',   false, 'Perdida'),
    ('Busy',        'Busy',        false, 'Ocupada'),
    ('Failed',      'Failed',      false, 'Fallida'),
    ('Transferred', 'Transferred', true,  'Transferida'),
    ('Cancelled',   'Cancelled',   false, 'Perdida')
ON CONFLICT DO NOTHING;

-- ── Add FK columns to fact_calls ──────────────────────────────

ALTER TABLE fact_calls
    ADD COLUMN IF NOT EXISTS direction_id TEXT REFERENCES dim_direction(direction_id),
    ADD COLUMN IF NOT EXISTS status_id    TEXT REFERENCES dim_call_status(status_id);

-- ── Backfill existing rows ────────────────────────────────────

UPDATE fact_calls
SET direction_id = direction
WHERE direction IN (SELECT direction_id FROM dim_direction);

UPDATE fact_calls
SET status_id = status
WHERE status IN (SELECT status_id FROM dim_call_status);

-- ── Indexes ───────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_fact_calls_direction_id ON fact_calls (direction_id);
CREATE INDEX IF NOT EXISTS idx_fact_calls_status_id    ON fact_calls (status_id);
