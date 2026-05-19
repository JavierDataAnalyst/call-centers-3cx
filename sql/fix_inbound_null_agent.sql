-- ============================================================
-- FIX: incluir llamadas Inbound (agent_id = NULL) en kpi_llamadas
--
-- En 3CX los registros Inbound se guardan desde el lado del caller:
--   - agent_id = NULL  (el caller externo no tiene extensión)
--   - direction_id = 'Inbound'
--   - call_source = 'Cola' o 'Directo'
--
-- La solución: UNION ALL con dos ramas:
--   Rama 1 → llamadas Outbound/Internal con agente conocido (JOIN dim_agent)
--   Rama 2 → llamadas Inbound (agent_id IS NULL, filtradas por queue_id para dept)
-- ============================================================

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

    -- ── Rama 1: Outbound e Internal con agente conocido ──────────────────
    SELECT fc.talking_seconds, fc.status_id, fc.call_source, fc.direction_id
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo    = true
      AND fc.direction_id IN ('Outbound', 'Internal')
      AND (dept        = 'todos' OR da.departamento = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
      AND (p_status     IS NULL  OR fc.status_id   = p_status)
      AND (p_agent_id   IS NULL  OR fc.agent_id    = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id = p_direction)

    UNION ALL

    -- ── Rama 2: Inbound (agent_id = NULL, caller externo) ────────────────
    -- Solo se incluye cuando no hay filtro por agente específico
    -- y el filtro de dirección es NULL o 'Inbound'
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

-- ── Verificación ─────────────────────────────────────────────────────────

-- Sin filtro: debe incluir Inbound + Outbound + Internal
SELECT 'Sin filtro'  AS filtro, * FROM kpi_llamadas();

-- Solo Inbound: debe mostrar las 3,355 llamadas inbound
SELECT 'Inbound'     AS filtro, * FROM kpi_llamadas(p_direction => 'Inbound');

-- Solo Outbound
SELECT 'Outbound'    AS filtro, * FROM kpi_llamadas(p_direction => 'Outbound');

-- Solo Internal
SELECT 'Internal'    AS filtro, * FROM kpi_llamadas(p_direction => 'Internal');
