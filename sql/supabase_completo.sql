-- ============================================================
-- 3CX DASHBOARD — SUPABASE SCHEMA COMPLETO
-- Corre este archivo de una sola vez en un Supabase nuevo.
-- Orden: dimensiones → hechos → resúmenes → índices → funciones
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. DIMENSIONES
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS dim_direction (
    direction_id TEXT PRIMARY KEY,
    tipo         TEXT    NOT NULL,
    es_entrante  BOOLEAN
);

INSERT INTO dim_direction (direction_id, tipo, es_entrante) VALUES
    ('Inbound',  'Inbound',  true),
    ('Outbound', 'Outbound', false),
    ('Internal', 'Internal', false)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_call_status (
    status_id     TEXT PRIMARY KEY,
    nombre        TEXT    NOT NULL,
    es_contactada BOOLEAN,
    categoria     TEXT
);

INSERT INTO dim_call_status (status_id, nombre, es_contactada, categoria) VALUES
    ('Answered',    'Answered',    true,  'Exitosa'),
    ('Unanswered',  'Unanswered',  false, 'Perdida'),
    ('No Answer',   'No Answer',   false, 'Perdida'),
    ('Busy',        'Busy',        false, 'Ocupada'),
    ('Failed',      'Failed',      false, 'Fallida'),
    ('Transferred', 'Transferred', true,  'Transferida'),
    ('Cancelled',   'Cancelled',   false, 'Perdida'),
    ('Waiting',     'Waiting',     false, 'Perdida')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_agent (
    agent_id     TEXT PRIMARY KEY,
    nombre       TEXT NOT NULL,
    extension    TEXT,
    departamento TEXT,
    es_equipo    BOOLEAN DEFAULT false,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_queue (
    queue_id   TEXT PRIMARY KEY,
    nombre     TEXT NOT NULL,
    codigo     TEXT,
    tipo       TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_date (
    date_key      DATE PRIMARY KEY,
    anio          INT,
    mes           INT,
    dia           INT,
    dia_semana    TEXT,
    semana        INT,
    es_fin_semana BOOLEAN
);


-- ════════════════════════════════════════════════════════════
-- 2. TABLA DE HECHOS
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS fact_calls (
    call_id               TEXT PRIMARY KEY,
    call_time             TIMESTAMPTZ,
    date_key              DATE REFERENCES dim_date(date_key),
    agent_id              TEXT REFERENCES dim_agent(agent_id),
    queue_id              TEXT,
    direction             TEXT,
    direction_id          TEXT REFERENCES dim_direction(direction_id),
    status                TEXT,
    status_id             TEXT REFERENCES dim_call_status(status_id),
    call_source           TEXT,
    from_no               TEXT,
    to_no                 TEXT,
    duration              TEXT,
    ringing_seconds       INT,
    talking_seconds       INT,
    cost                  NUMERIC(10,4),
    call_activity_details TEXT,
    sentiment             TEXT,
    summary               TEXT,
    transcription         TEXT,
    imported_at           TIMESTAMPTZ DEFAULT NOW()
);


-- ════════════════════════════════════════════════════════════
-- 3. TABLAS DE RESUMEN
-- ════════════════════════════════════════════════════════════

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

-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS queue_performance (
    id                       SERIAL PRIMARY KEY,
    queue_id                 TEXT REFERENCES dim_queue(queue_id),
    agent_id                 TEXT REFERENCES dim_agent(agent_id),
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

-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS user_activity (
    id               SERIAL PRIMARY KEY,
    time_scale       TIMESTAMPTZ UNIQUE,
    answered_calls   INT,
    unanswered_calls INT
);

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_schedules (
    agent_id   TEXT PRIMARY KEY REFERENCES dim_agent(agent_id),
    start_hour INT  NOT NULL,
    end_hour   INT  NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);


-- ════════════════════════════════════════════════════════════
-- 4. ÍNDICES
-- ════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_fact_calls_date         ON fact_calls (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_calls_agent        ON fact_calls (agent_id);
CREATE INDEX IF NOT EXISTS idx_fact_calls_status_id    ON fact_calls (status_id);
CREATE INDEX IF NOT EXISTS idx_fact_calls_direction_id ON fact_calls (direction_id);
CREATE INDEX IF NOT EXISTS idx_fact_calls_queue        ON fact_calls (queue_id);
CREATE INDEX IF NOT EXISTS idx_aiq_queue_date          ON agents_in_queue_stats (queue_id, report_date);
CREATE INDEX IF NOT EXISTS idx_aiq_agent_date          ON agents_in_queue_stats (agent_id, report_date);
CREATE INDEX IF NOT EXISTS idx_login_agent_date        ON agent_login_history (agent_id, date_key);
CREATE INDEX IF NOT EXISTS idx_qperf_queue_agent       ON queue_performance (queue_id, agent_id);


-- ════════════════════════════════════════════════════════════
-- 5. FUNCIONES RPC
-- ════════════════════════════════════════════════════════════

-- ── get_equipo ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_equipo()
RETURNS TABLE(agent_id text, nombre text, departamento text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT agent_id, nombre, departamento
  FROM dim_agent
  WHERE es_equipo = true
  ORDER BY departamento, nombre;
$$;

-- ── kpi_llamadas ──────────────────────────────────────────────

DROP FUNCTION IF EXISTS kpi_llamadas(text,date,date,text,text);

CREATE OR REPLACE FUNCTION kpi_llamadas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(
  avg_real_min     numeric,
  avg_real_mm_ss   text,
  llamadas_reales  bigint,
  total_answered   bigint,
  total_perdidas   bigint,
  total_unanswered bigint,
  waiting_cola     bigint,
  waiting_agente   bigint
)
LANGUAGE sql SECURITY DEFINER AS $$
  WITH base AS (
    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo = true
      AND (dept        = 'todos' OR da.departamento = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key  >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key  <= fecha_fin)
      AND (p_status     IS NULL  OR fc.status_id  = p_status)
      AND (p_agent_id   IS NULL  OR fc.agent_id   = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id = p_direction)

    UNION ALL

    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    WHERE fc.agent_id  IS NULL
      AND fc.call_source = 'Cola'
      AND fc.status_id   = 'Waiting'
      AND p_agent_id  IS NULL
      AND (p_direction IS NULL OR p_direction = 'Inbound')
      AND (dept = 'todos'
        OR (dept = 'Lender Review'    AND fc.queue_id = '835')
        OR (dept = 'Customer Service' AND fc.queue_id = '840'))
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
      AND (p_status     IS NULL OR fc.status_id = p_status)
  )
  SELECT
    ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD((AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12))::int, 60)::text, 2, '0'),
    COUNT(*) FILTER (WHERE talking_seconds >= 12),
    COUNT(*) FILTER (WHERE status_id = 'Answered'),
    COUNT(*) FILTER (WHERE status_id NOT IN ('Answered','Transferred')),
    COUNT(*) FILTER (WHERE status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL))
  FROM base;
$$;

-- ── kpi_agentes ───────────────────────────────────────────────

DROP FUNCTION IF EXISTS kpi_agentes(text,date,date,text);
DROP FUNCTION IF EXISTS kpi_agentes(text,date,date,text,text);

CREATE OR REPLACE FUNCTION kpi_agentes(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(
  agente            text,
  agent_id          text,
  departamento      text,
  avg_real_min      numeric,
  avg_real_mm_ss    text,
  llamadas_reales   bigint,
  dias_activos      bigint,
  avg_llamadas_dia  numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    da.nombre,
    da.agent_id,
    da.departamento,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD((AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12))::int, 60)::text, 2, '0'),
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12),
    COUNT(DISTINCT fc.date_key),
    ROUND(
      COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)::numeric
      / NULLIF(COUNT(DISTINCT fc.date_key), 0),
    1)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento  = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key      >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key      <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id      = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id   = p_direction)
  GROUP BY da.nombre, da.agent_id, da.departamento
  ORDER BY 6 DESC;
$$;

-- ── kpi_llamadas_perdidas ─────────────────────────────────────

CREATE OR REPLACE FUNCTION kpi_llamadas_perdidas()
RETURNS TABLE(
  categoria text,
  status_id text,
  total     bigint,
  pct       numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  WITH base AS (
    SELECT fc.status_id, dcs.categoria, COUNT(*) AS total
    FROM fact_calls fc
    JOIN dim_agent da     ON fc.agent_id  = da.agent_id
    JOIN dim_call_status dcs ON fc.status_id = dcs.status_id
    WHERE da.es_equipo = true
      AND dcs.es_contactada = false
    GROUP BY fc.status_id, dcs.categoria
  ),
  grand_total AS (SELECT SUM(total) AS gt FROM base)
  SELECT b.categoria, b.status_id, b.total,
    ROUND(b.total * 100.0 / NULLIF(gt.gt, 0), 1)
  FROM base b, grand_total gt
  ORDER BY b.total DESC;
$$;

-- ── kpi_heatmap_horas ─────────────────────────────────────────

DROP FUNCTION IF EXISTS kpi_heatmap_horas(text,date,date,text,text);
DROP FUNCTION IF EXISTS kpi_heatmap_horas(text,date,date,text);

CREATE OR REPLACE FUNCTION kpi_heatmap_horas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, total bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_status     IS NULL  OR fc.status_id    = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2;
$$;

-- ── kpi_heatmap_por_status ────────────────────────────────────

DROP FUNCTION IF EXISTS kpi_heatmap_por_status(text,date,date,text);

CREATE OR REPLACE FUNCTION kpi_heatmap_por_status(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, status_id text, total bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    fc.status_id,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2, 3;
$$;

-- ── kpi_colas_detalle ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION kpi_colas_detalle()
RETURNS TABLE(
  cola           text,
  mes            int,
  total_llamadas bigint,
  contestadas    bigint,
  colgaron       bigint,
  pct_servicio   numeric,
  avg_min_habla  numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    dq.nombre,
    EXTRACT(MONTH FROM dqs.report_date)::int,
    SUM(dqs.calls_total)::bigint,
    SUM(dqs.calls_answered)::bigint,
    SUM(dqs.calls_abandoned)::bigint,
    ROUND(SUM(dqs.calls_answered) * 100.0 / NULLIF(SUM(dqs.calls_total), 0), 1),
    ROUND(SUM(dqs.talk_time_total_seconds)::numeric / NULLIF(SUM(dqs.calls_answered), 0) / 60.0, 1)
  FROM detailed_queue_stats dqs
  JOIN dim_queue dq ON dq.queue_id = dqs.queue_id
  GROUP BY dq.nombre, EXTRACT(MONTH FROM dqs.report_date)
  ORDER BY 1, 2;
$$;

-- ── kpi_login_detalle ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION kpi_login_detalle(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL
)
RETURNS TABLE(
  agente                  text,
  departamento            text,
  fecha                   date,
  primer_login            timestamptz,
  ultimo_logout           timestamptz,
  total_logged_in_seconds bigint,
  total_talking_seconds   bigint
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    da.nombre,
    da.departamento,
    alh.date_key,
    MIN(alh.logged_in),
    MAX(alh.logged_out),
    SUM(alh.total_logged_in_seconds)::bigint,
    COALESCE(SUM(DISTINCT fc_agg.habla), 0)::bigint
  FROM agent_login_history alh
  JOIN dim_agent da ON alh.agent_id = da.agent_id
  LEFT JOIN (
    SELECT agent_id, date_key, SUM(talking_seconds) AS habla
    FROM fact_calls
    WHERE status_id = 'Answered'
    GROUP BY agent_id, date_key
  ) fc_agg ON fc_agg.agent_id = alh.agent_id AND fc_agg.date_key = alh.date_key
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR alh.date_key   >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR alh.date_key   <= fecha_fin)
    AND (p_agent_id   IS NULL  OR alh.agent_id    = p_agent_id)
  GROUP BY da.nombre, da.departamento, alh.date_key
  ORDER BY alh.date_key DESC, da.nombre;
$$;

-- ── kpi_sla_asa ───────────────────────────────────────────────

DROP FUNCTION IF EXISTS kpi_sla_asa(text);
DROP FUNCTION IF EXISTS kpi_sla_asa(text, integer);
DROP FUNCTION IF EXISTS kpi_sla_asa();

CREATE OR REPLACE FUNCTION kpi_sla_asa(
  p_dept        TEXT    DEFAULT 'todos',
  p_sla_seconds INTEGER DEFAULT 50
)
RETURNS TABLE(
  cola           text,
  total_llamadas bigint,
  dentro_sla     bigint,
  pct_sla        numeric,
  asa_avg_sec    numeric,
  asa_med_sec    numeric,
  asa_p90_sec    numeric,
  sla_threshold  integer
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    dq.nombre,
    COUNT(*),
    COUNT(*) FILTER (WHERE qac.ringing_seconds <= p_sla_seconds),
    ROUND(COUNT(*) FILTER (WHERE qac.ringing_seconds <= p_sla_seconds) * 100.0
          / NULLIF(COUNT(*), 0), 1),
    ROUND(AVG(qac.ringing_seconds)::numeric, 0),
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qac.ringing_seconds)::numeric, 0),
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY qac.ringing_seconds)::numeric, 0),
    p_sla_seconds
  FROM queue_answered_calls qac
  JOIN dim_queue dq ON dq.queue_id = qac.queue_id
  WHERE (p_dept = 'todos' OR dq.nombre ILIKE
         CASE p_dept
           WHEN 'Customer Service' THEN '%servicio%'
           WHEN 'Lender Review'    THEN '%calidad%'
           ELSE '%'
         END)
  GROUP BY dq.nombre
  ORDER BY 1;
$$;

-- ── get_llamadas_detalle ──────────────────────────────────────

DROP FUNCTION IF EXISTS get_llamadas_detalle(text,text,date,date,int,int,int,int,text);

CREATE OR REPLACE FUNCTION get_llamadas_detalle(
  dept         TEXT    DEFAULT 'todos',
  p_agent_id   TEXT    DEFAULT NULL,
  fecha_inicio DATE    DEFAULT NULL,
  fecha_fin    DATE    DEFAULT NULL,
  p_limit      INT     DEFAULT 50,
  p_offset     INT     DEFAULT 0,
  p_hora       INT     DEFAULT NULL,
  p_dia        INT     DEFAULT NULL,
  p_status     TEXT    DEFAULT NULL,
  p_direction  TEXT    DEFAULT NULL
)
RETURNS TABLE(
  call_id         text,
  call_time       timestamptz,
  agente          text,
  departamento    text,
  direction       text,
  status          text,
  ringing_seconds int,
  talking_seconds int,
  sentiment       text,
  summary         text
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    fc.call_id, fc.call_time,
    da.nombre, da.departamento,
    fc.direction_id, fc.status_id,
    fc.ringing_seconds, fc.talking_seconds,
    fc.sentiment, fc.summary
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (p_agent_id   IS NULL  OR fc.agent_id    = p_agent_id)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id   = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
    AND (p_hora       IS NULL  OR EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int = p_hora)
    AND (p_dia        IS NULL  OR EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int = p_dia)
  ORDER BY fc.call_time DESC
  LIMIT p_limit OFFSET p_offset;
$$;

-- ── kpi_llamadas_detalle ──────────────────────────────────────

DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT oid::regprocedure::text AS sig FROM pg_proc WHERE proname = 'kpi_llamadas_detalle'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

CREATE OR REPLACE FUNCTION kpi_llamadas_detalle(
  p_tipo       TEXT,
  dept         TEXT    DEFAULT 'todos',
  fecha_inicio DATE    DEFAULT NULL,
  fecha_fin    DATE    DEFAULT NULL,
  p_agent_id   TEXT    DEFAULT NULL,
  p_direction  TEXT    DEFAULT NULL,
  p_limit      INT     DEFAULT 200,
  p_offset     INT     DEFAULT 0
)
RETURNS TABLE(
  call_id         text,
  call_time       timestamptz,
  agente          text,
  departamento    text,
  direction_id    text,
  status_id       text,
  call_source     text,
  cola            text,
  ringing_seconds int,
  talking_seconds int
)
LANGUAGE sql SECURITY DEFINER AS
$func$
  WITH base_calls AS (
    SELECT
      fc.call_id, fc.call_time,
      da.nombre AS agente, da.departamento,
      fc.direction_id, fc.status_id, fc.call_source, fc.queue_id,
      fc.ringing_seconds, fc.talking_seconds
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo    = true
      AND fc.direction_id IN ('Outbound', 'Internal')
      AND (dept        = 'todos' OR da.departamento = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key     >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key     <= fecha_fin)
      AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id = p_direction)

    UNION ALL

    SELECT
      fc.call_id, fc.call_time,
      'Sin agente' AS agente, '—' AS departamento,
      fc.direction_id, fc.status_id, fc.call_source, fc.queue_id,
      fc.ringing_seconds, fc.talking_seconds
    FROM fact_calls fc
    WHERE fc.direction_id = 'Inbound'
      AND fc.agent_id     IS NULL
      AND p_agent_id      IS NULL
      AND (p_direction    IS NULL OR p_direction = 'Inbound')
      AND (
        dept = 'todos'
        OR (dept = 'Lender Review'    AND fc.queue_id = '835')
        OR (dept = 'Customer Service' AND fc.queue_id = '840')
      )
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
  ),
  ignorada_calls AS (
    SELECT
      fc.call_id, fc.call_time,
      COALESCE(da.nombre, 'Agente ' || fc.agent_id) AS agente,
      COALESCE(da.departamento, '—') AS departamento,
      fc.direction_id, fc.status_id, fc.call_source, fc.queue_id,
      fc.ringing_seconds, fc.talking_seconds
    FROM fact_calls fc
    LEFT JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE fc.status_id    = 'Waiting'
      AND fc.call_source  = 'Cola'
      AND fc.direction_id = 'Internal'
      AND fc.agent_id     IS NOT NULL
      AND (
        dept = 'todos'
        OR (dept = 'Lender Review'    AND fc.queue_id = '835')
        OR (dept = 'Customer Service' AND fc.queue_id = '840')
      )
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
      AND (p_agent_id   IS NULL OR fc.agent_id = p_agent_id)
  )
  SELECT
    bc.call_id, bc.call_time, bc.agente, bc.departamento,
    bc.direction_id, bc.status_id, bc.call_source,
    COALESCE(dq.nombre, bc.queue_id, '—') AS cola,
    bc.ringing_seconds, bc.talking_seconds
  FROM (
    SELECT * FROM base_calls
    WHERE (p_tipo = 'answered'       AND status_id = 'Answered')
       OR (p_tipo = 'unanswered'     AND status_id = 'Unanswered')
       OR (p_tipo = 'reales'         AND talking_seconds >= 12)
       OR (p_tipo = 'abandono_cola'  AND status_id = 'Waiting'
                                     AND call_source = 'Cola'
                                     AND direction_id = 'Inbound')
       OR (p_tipo = 'waiting_agente' AND status_id = 'Waiting'
                                     AND (call_source = 'Directo' OR call_source IS NULL))
    UNION ALL
    SELECT * FROM ignorada_calls
    WHERE p_tipo = 'cola_ignorada'
  ) bc
  LEFT JOIN dim_queue dq ON bc.queue_id = dq.queue_id
  ORDER BY bc.call_time DESC
  LIMIT p_limit OFFSET p_offset;
$func$;

-- ── kpi_llamadas_diarias ──────────────────────────────────────

DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT oid::regprocedure::text AS sig FROM pg_proc WHERE proname = 'kpi_llamadas_diarias'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

CREATE OR REPLACE FUNCTION kpi_llamadas_diarias(
  dept         TEXT  DEFAULT 'todos',
  fecha_inicio DATE  DEFAULT NULL,
  fecha_fin    DATE  DEFAULT NULL,
  p_agent_id   TEXT  DEFAULT NULL
)
RETURNS TABLE(
  agent_id      text,
  agente        text,
  departamento  text,
  fecha         date,
  total         bigint,
  contestadas   bigint,
  unanswered    bigint,
  reales        bigint,
  avg_seg       numeric,
  avg_mm_ss     text
)
LANGUAGE sql SECURITY DEFINER AS
$func$
  SELECT
    da.agent_id,
    da.nombre,
    da.departamento,
    fc.date_key,
    COUNT(*),
    COUNT(*) FILTER (WHERE fc.status_id = 'Answered'),
    COUNT(*) FILTER (WHERE fc.status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12),
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0),
    LPAD(FLOOR(COALESCE(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0) / 60)::int::text, 2, '0')
      || ':' ||
    LPAD(MOD(FLOOR(COALESCE(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0))::int, 60)::text, 2, '0')
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo    = true
    AND (dept        = 'todos' OR da.departamento  = dept)
    AND (p_agent_id  IS NULL   OR fc.agent_id      = p_agent_id)
    AND (fecha_inicio IS NULL  OR fc.date_key      >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key      <= fecha_fin)
  GROUP BY da.agent_id, da.nombre, da.departamento, fc.date_key
  ORDER BY da.nombre, fc.date_key DESC;
$func$;

-- ── kpi_cobertura_login ───────────────────────────────────────

DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT oid::regprocedure::text AS sig FROM pg_proc WHERE proname = 'kpi_cobertura_login'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

CREATE OR REPLACE FUNCTION kpi_cobertura_login(
  p_dept       TEXT  DEFAULT 'todos',
  fecha_inicio DATE  DEFAULT NULL,
  fecha_fin    DATE  DEFAULT NULL
)
RETURNS TABLE(
  hora                 int,
  total_llamadas       bigint,
  avg_llamadas_dia     numeric,
  avg_agentes_hora     numeric,
  llamadas_por_agente  numeric
)
LANGUAGE sql SECURITY DEFINER AS
$func$
  WITH
  llamadas_hora AS (
    SELECT
      EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int AS hora,
      COUNT(*) AS total
    FROM fact_calls fc
    LEFT JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE (
      p_dept = 'todos'
      OR (da.es_equipo = true AND da.departamento = p_dept)
      OR (fc.direction_id = 'Inbound' AND fc.agent_id IS NULL
          AND ((p_dept = 'Lender Review'    AND fc.queue_id = '835')
            OR (p_dept = 'Customer Service' AND fc.queue_id = '840')))
    )
    AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
    AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
    GROUP BY hora
  ),
  dias_totales AS (
    SELECT COUNT(DISTINCT fc.date_key) AS num_dias
    FROM fact_calls fc
    LEFT JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE (
      p_dept = 'todos'
      OR (da.es_equipo = true AND da.departamento = p_dept)
      OR (fc.direction_id = 'Inbound' AND fc.agent_id IS NULL
          AND ((p_dept = 'Lender Review'    AND fc.queue_id = '835')
            OR (p_dept = 'Customer Service' AND fc.queue_id = '840')))
    )
    AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
    AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
  ),
  agentes_por_dia_hora AS (
    SELECT
      h.hora,
      alh.date_key AS fecha,
      COUNT(DISTINCT alh.agent_id) AS num_agentes
    FROM generate_series(7, 21) AS h(hora)
    JOIN agent_login_history alh
      ON EXTRACT(HOUR FROM alh.logged_in  AT TIME ZONE 'UTC')::int <= h.hora
     AND EXTRACT(HOUR FROM alh.logged_out AT TIME ZONE 'UTC')::int >= h.hora
     AND alh.logged_in  IS NOT NULL
     AND alh.logged_out IS NOT NULL
    LEFT JOIN dim_agent da ON alh.agent_id = da.agent_id
    WHERE (p_dept = 'todos' OR da.departamento = p_dept)
      AND (fecha_inicio IS NULL OR alh.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR alh.date_key <= fecha_fin)
    GROUP BY h.hora, alh.date_key
  ),
  agentes_hora AS (
    SELECT hora, ROUND(AVG(num_agentes), 1) AS avg_agentes
    FROM agentes_por_dia_hora
    GROUP BY hora
  )
  SELECT
    h.hora,
    COALESCE(lh.total, 0)::bigint,
    ROUND(COALESCE(lh.total,0)::numeric / NULLIF(dt.num_dias,0), 1),
    COALESCE(ah.avg_agentes, 0),
    CASE WHEN COALESCE(ah.avg_agentes, 0) > 0
      THEN ROUND(COALESCE(lh.total,0)::numeric / NULLIF(dt.num_dias,0) / ah.avg_agentes, 1)
      ELSE 0
    END
  FROM generate_series(7, 21) AS h(hora)
  CROSS JOIN dias_totales dt
  LEFT JOIN llamadas_hora lh ON lh.hora = h.hora
  LEFT JOIN agentes_hora  ah ON ah.hora = h.hora
  ORDER BY h.hora;
$func$;

-- ════════════════════════════════════════════════════════════
-- FIN — Schema listo para recibir datos del ETL
-- ════════════════════════════════════════════════════════════
