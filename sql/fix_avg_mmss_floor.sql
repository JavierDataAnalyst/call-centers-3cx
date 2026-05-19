-- ============================================================
-- FIX: avg_real_mm_ss usa FLOOR; todo el agregado en CTE "agg"
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
    -- Outbound e Internal con agente conocido
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

    -- Inbound (agent_id = NULL, caller externo)
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
  agg AS (
    SELECT
      AVG(talking_seconds)  FILTER (WHERE talking_seconds >= 12)                        AS avg_sec,
      COUNT(*)              FILTER (WHERE talking_seconds >= 12)                        AS llamadas_reales,
      COUNT(*)              FILTER (WHERE status_id = 'Answered')                       AS total_answered,
      COUNT(*)              FILTER (WHERE status_id NOT IN ('Answered','Transferred'))  AS total_perdidas,
      COUNT(*)              FILTER (WHERE status_id = 'Unanswered')                     AS total_unanswered,
      COUNT(*)              FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola')                       AS waiting_cola,
      COUNT(*)              FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL)) AS waiting_agente
    FROM base
  )
  SELECT
    ROUND(avg_sec / 60.0, 1)::numeric,
    LPAD(FLOOR(avg_sec / 60.0)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(FLOOR(avg_sec)::int, 60)::text, 2, '0'),
    llamadas_reales,
    total_answered,
    total_perdidas,
    total_unanswered,
    waiting_cola,
    waiting_agente
  FROM agg;
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
    da.nombre                                                                            AS agente,
    da.agent_id,
    da.departamento,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)::numeric
                                                                                         AS avg_real_min,
    LPAD(FLOOR(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(FLOOR(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12))::int, 60)::text, 2, '0')
                                                                                         AS avg_real_mm_ss,
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)                                    AS llamadas_reales
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
-- Outbound debe mostrar avg_real_min y avg_real_mm_ss consistentes
-- Ej: 3.7 min → "03:41"
SELECT * FROM kpi_llamadas(p_direction => 'Outbound');
