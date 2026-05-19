-- ============================================================
-- Agregar filtro p_direction (Inbound / Outbound / Internal)
-- a todas las funciones del dashboard
-- ============================================================

-- ── 1. kpi_llamadas ──────────────────────────────────────────

DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT oid::regprocedure::text AS sig FROM pg_proc WHERE proname = 'kpi_llamadas'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

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
LANGUAGE sql SECURITY DEFINER AS
$func$
  WITH base AS (
    SELECT fc.talking_seconds, fc.status_id, fc.call_source, fc.direction_id
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo = true
      AND (dept        = 'todos' OR da.departamento  = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key      >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key      <= fecha_fin)
      AND (p_status     IS NULL  OR fc.status_id     = p_status)
      AND (p_agent_id   IS NULL  OR fc.agent_id      = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id  = p_direction)

    UNION ALL

    SELECT fc.talking_seconds, fc.status_id, fc.call_source, fc.direction_id
    FROM fact_calls fc
    WHERE fc.agent_id IS NULL
      AND fc.call_source = 'Cola'
      AND fc.status_id   = 'Waiting'
      AND p_agent_id IS NULL
      AND (p_direction IS NULL OR fc.direction_id = p_direction)
      AND (
        dept = 'todos'
        OR (dept = 'Lender Review'    AND fc.queue_id = '835')
        OR (dept = 'Customer Service' AND fc.queue_id = '840')
      )
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
      AND (p_status     IS NULL OR fc.status_id = p_status)
  )
  SELECT
    ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD(
      (AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60)::int::text, 2, '0'
    ) || ':' || LPAD(
      MOD(ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12))::int, 60)::text, 2, '0'
    ),
    COUNT(*) FILTER (WHERE talking_seconds >= 12),
    COUNT(*) FILTER (WHERE status_id = 'Answered'),
    COUNT(*) FILTER (WHERE status_id NOT IN ('Answered','Transferred')),
    COUNT(*) FILTER (WHERE status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL))
  FROM base;
$func$;

-- ── 2. kpi_agentes ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION kpi_agentes(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(
  agente          text,
  agent_id        text,
  departamento    text,
  avg_real_min    numeric,
  avg_real_mm_ss  text,
  llamadas_reales bigint
)
LANGUAGE sql SECURITY DEFINER AS
$func$
  SELECT
    da.nombre, da.agent_id, da.departamento,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD(
      (AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60)::int::text, 2, '0'
    ) || ':' || LPAD(
      MOD(ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12))::int, 60)::text, 2, '0'
    ),
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key     >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key     <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id    = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY da.nombre, da.agent_id, da.departamento
  ORDER BY llamadas_reales DESC;
$func$;

-- ── 3. kpi_heatmap_horas ─────────────────────────────────────

DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT oid::regprocedure::text AS sig FROM pg_proc WHERE proname = 'kpi_heatmap_horas'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

CREATE OR REPLACE FUNCTION kpi_heatmap_horas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, total bigint)
LANGUAGE sql SECURITY DEFINER AS
$func$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key     >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key     <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_status     IS NULL  OR fc.status_id    = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2;
$func$;

-- ── 4. kpi_heatmap_por_status ────────────────────────────────

CREATE OR REPLACE FUNCTION kpi_heatmap_por_status(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, status_id text, total bigint)
LANGUAGE sql SECURITY DEFINER AS
$func$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    fc.status_id,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key     >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key     <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2, 3;
$func$;

-- ── 5. get_llamadas_detalle ──────────────────────────────────

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
LANGUAGE sql SECURITY DEFINER AS
$func$
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
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (fecha_inicio IS NULL  OR fc.date_key     >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key     <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id    = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
    AND (p_hora       IS NULL  OR EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int = p_hora)
    AND (p_dia        IS NULL  OR EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int = p_dia)
  ORDER BY fc.call_time DESC
  LIMIT p_limit OFFSET p_offset;
$func$;

-- VERIFICACIÓN
SELECT * FROM kpi_llamadas(p_direction => 'Inbound');
SELECT * FROM kpi_llamadas(p_direction => 'Outbound');
