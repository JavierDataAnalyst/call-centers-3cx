-- ============================================================
-- cola_ignorada: CTE separado sin filtro es_equipo
-- Los 590 registros pertenecen a agentes es_equipo=false
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
  waiting_agente   bigint,
  cola_ignorada    bigint
)
LANGUAGE sql SECURITY DEFINER AS
$func$
  WITH base AS (
    -- Outbound e Internal con agente del equipo (es_equipo=true)
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

  -- Cola ignorada: ANY agente (es_equipo cualquiera) que no contestó la cola
  ignorada AS (
    SELECT COUNT(*) AS total
    FROM fact_calls fc
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
      AND (p_agent_id   IS NULL OR fc.agent_id  = p_agent_id)
  ),

  agg AS (
    SELECT
      AVG(talking_seconds)  FILTER (WHERE talking_seconds >= 12)                        AS avg_sec,
      COUNT(*)              FILTER (WHERE talking_seconds >= 12)                        AS llamadas_reales,
      COUNT(*)              FILTER (WHERE status_id = 'Answered')                       AS total_answered,
      COUNT(*)              FILTER (WHERE status_id NOT IN ('Answered','Transferred'))  AS total_perdidas,
      COUNT(*)              FILTER (WHERE status_id = 'Unanswered')                     AS total_unanswered,
      COUNT(*)              FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'
                                      AND direction_id = 'Inbound')                     AS waiting_cola,
      COUNT(*)              FILTER (WHERE status_id = 'Waiting'
                                      AND (call_source = 'Directo' OR call_source IS NULL)) AS waiting_agente
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
    waiting_agente,
    (SELECT total FROM ignorada)
  FROM agg;
$func$;

-- Verificación
SELECT
  total_answered,
  total_unanswered,
  waiting_cola  AS abandono_cliente_en_cola,
  cola_ignorada AS agente_no_contesto_cola,
  waiting_agente
FROM kpi_llamadas();
