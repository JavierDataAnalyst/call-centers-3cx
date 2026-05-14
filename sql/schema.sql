-- ============================================================
-- 3CX Dashboard — Supabase Schema (Star Model)
-- Run once in Supabase → SQL Editor
-- ============================================================

-- ── Dimensions ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_agent (
    agent_id   TEXT PRIMARY KEY,       -- extension number, e.g. "402"
    nombre     TEXT NOT NULL,
    extension  TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dim_queue (
    queue_id   TEXT PRIMARY KEY,       -- queue code, e.g. "835"
    nombre     TEXT NOT NULL,          -- "WH Financial - Calidad"
    codigo     TEXT,
    tipo       TEXT,                   -- 'Calidad' | 'SAC' | 'General'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dim_date (
    date_key      DATE PRIMARY KEY,
    anio          INT,
    mes           INT,
    dia           INT,
    dia_semana    TEXT,
    semana        INT,
    es_fin_semana BOOLEAN
);

-- ── Fact table ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS fact_calls (
    call_id               TEXT PRIMARY KEY,
    call_time             TIMESTAMPTZ,
    date_key              DATE        REFERENCES dim_date(date_key),
    agent_id              TEXT        REFERENCES dim_agent(agent_id),
    direction             TEXT,        -- 'Inbound' | 'Outbound'
    status                TEXT,        -- 'Answered' | 'Unanswered'
    ringing_seconds       INT,
    talking_seconds       INT,
    cost                  NUMERIC(10,4),
    call_activity_details TEXT,
    sentiment             TEXT,
    summary               TEXT,
    transcription         TEXT,
    imported_at           TIMESTAMPTZ DEFAULT NOW()
);

-- ── Summary tables ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_login_history (
    id                      SERIAL PRIMARY KEY,
    date_key                DATE REFERENCES dim_date(date_key),
    agent_id                TEXT REFERENCES dim_agent(agent_id),
    logged_in               TIMESTAMPTZ,
    logged_out              TIMESTAMPTZ,
    total_logged_in_seconds INT,
    total_talking_seconds   INT,
    UNIQUE (date_key, agent_id, logged_in)
);

CREATE TABLE IF NOT EXISTS agents_in_queue_stats (
    id                      SERIAL PRIMARY KEY,
    queue_id                TEXT REFERENCES dim_queue(queue_id),
    agent_id                TEXT REFERENCES dim_agent(agent_id),
    report_date             DATE REFERENCES dim_date(date_key),
    total_logged_in_seconds INT,
    calls_answered          INT,
    pct_calls_serviced      NUMERIC(5,2),
    calls_answered_per_hour NUMERIC(8,2),
    ring_time_total_seconds INT,
    ring_time_mean_seconds  INT,
    talk_time_total_seconds INT,
    talk_time_mean_seconds  INT,
    UNIQUE (queue_id, agent_id, report_date)
);

CREATE TABLE IF NOT EXISTS team_queue_stats (
    id                 SERIAL PRIMARY KEY,
    queue_id           TEXT REFERENCES dim_queue(queue_id),
    report_date        DATE REFERENCES dim_date(date_key),
    agents_in_team     INT,
    calls_received     INT,
    calls_serviced     INT,
    calls_unanswered   INT,
    total_talk_seconds INT,
    avg_talk_seconds   INT,
    UNIQUE (queue_id, report_date)
);

CREATE TABLE IF NOT EXISTS detailed_queue_stats (
    id                      SERIAL PRIMARY KEY,
    queue_id                TEXT REFERENCES dim_queue(queue_id),
    report_date             DATE REFERENCES dim_date(date_key),
    calls_total             INT,
    calls_abandoned         INT,
    calls_answered          INT,
    pct_calls_serviced      NUMERIC(5,2),
    successful_callbacks    INT,
    talk_time_total_seconds INT,
    talk_time_mean_seconds  INT,
    UNIQUE (queue_id, report_date)
);

CREATE TABLE IF NOT EXISTS queue_performance (
    id                       SERIAL PRIMARY KEY,
    queue_id                 TEXT REFERENCES dim_queue(queue_id),
    agent_id                 TEXT,
    report_date              DATE REFERENCES dim_date(date_key),
    queue_received_calls     INT,
    queue_serviced_calls     INT,
    queue_unanswered_calls   INT,
    extension_serviced_calls INT,
    extension_polls          INT,
    talk_time_seconds        INT,
    avg_talk_time_seconds    INT,
    UNIQUE (queue_id, agent_id, report_date)
);

CREATE TABLE IF NOT EXISTS queue_answered_calls (
    id                   SERIAL PRIMARY KEY,
    queue_id             TEXT        REFERENCES dim_queue(queue_id),
    call_time            TIMESTAMPTZ,
    destination_agent_id TEXT        REFERENCES dim_agent(agent_id),
    caller_id            TEXT,
    ringing_seconds      INT,
    answer_time          TIMESTAMPTZ,
    sentiment            TEXT,
    imported_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS extension_statistics (
    id                    SERIAL PRIMARY KEY,
    agent_id              TEXT REFERENCES dim_agent(agent_id),
    report_date           DATE REFERENCES dim_date(date_key),
    inbound_answered      INT,
    inbound_unanswered    INT,
    outbound_answered     INT,
    outbound_unanswered   INT,
    total_answered        INT,
    total_unanswered      INT,
    total_talking_seconds INT,
    sentiment             TEXT,
    UNIQUE (agent_id, report_date)
);

CREATE TABLE IF NOT EXISTS user_activity (
    id               SERIAL PRIMARY KEY,
    time_scale       TIMESTAMPTZ UNIQUE,
    answered_calls   INT,
    unanswered_calls INT
);

-- ── Indexes for dashboard performance ────────────────────────

CREATE INDEX IF NOT EXISTS idx_fact_calls_date      ON fact_calls (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_calls_agent     ON fact_calls (agent_id);
CREATE INDEX IF NOT EXISTS idx_fact_calls_status    ON fact_calls (status);
CREATE INDEX IF NOT EXISTS idx_fact_calls_direction ON fact_calls (direction);
CREATE INDEX IF NOT EXISTS idx_aiq_queue_date       ON agents_in_queue_stats (queue_id, report_date);
CREATE INDEX IF NOT EXISTS idx_aiq_agent_date       ON agents_in_queue_stats (agent_id, report_date);
