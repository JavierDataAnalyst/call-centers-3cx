-- ============================================================
-- FIX: avg_real_mm_ss usaba ::int (redondea) en lugar de FLOOR (trunca)
-- Ejemplo: 221 seg → 3 min 41 seg → debe ser "03:41" no "04:41"
-- Aplica a kpi_llamadas y kpi_agentes
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
    WHERE da.es_equipo    = true
      AND fc.direction_id IN ('Outbound', 'Internal')
      AND (dept        = 'todos' OR da.departamento  = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key      >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key      <= fecha_fin)
      AND (p_status     IS NULL  OR fc.status_id     = p_status)
      AND (p_agent_id   IS NULL  OR fc.agent_id      = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id  = p_direction)

    UNION ALL

    SELECT fc.talking_seconds, fc.status_id, fc.call_source, fc.direction_id
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
      AND (p_status     IS NULL OR fc.status_id = p_status)
  ),
  stats AS (
    SELECT AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) AS avg_sec
    FROM base
  )
  SELECT
    ROUND(avg_sec / 60.0, 1)::numeric,
    LPAD(FLOOR(avg_sec / 60.0)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(FLOOR(avg_sec)::int, 60)::text, 2, '0'),
    COUNT(*) FILTER (WHERE talking_seconds >= 12),
    COUNT(*) FILTER (WHERE status_id = 'Answered'),
    COUNT(*) FILTER (WHERE status_id NOT IN ('Answered','Transferred')),
    COUNT(*) FILTER (WHERE status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL))
  FROM base, stats;
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
    da.nombre                                                                           AS agente,
    da.agent_id,
    da.departamento,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)::numeric
                                                                                        AS avg_real_min,
    LPAD(FLOOR(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(FLOOR(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12))::int, 60)::text, 2, '0')
                                                                                        AS avg_real_mm_ss,
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)                                   AS llamadas_reales
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

-- ── Verificación ─────────────────────────────────────────────
-- avg_real_min y avg_real_mm_ss deben coincidir ahora
-- Ej: 3.7 min → "03:41"  |  4.7 min → "04:41"
SELECT
  ROUND(avg_sec / 60.0, 1)                                AS avg_min,
  LPAD(FLOOR(avg_sec / 60.0)::int::text, 2, '0') || ':' ||
  LPAD(MOD(FLOOR(avg_sec)::int, 60)::text,        2, '0') AS mm_ss
FROM (SELECT 221.0 AS avg_sec) t;   -- debe dar 3.7 | 03:41

SELECT * FROM kpi_llamadas(p_direction => 'Outbound');
