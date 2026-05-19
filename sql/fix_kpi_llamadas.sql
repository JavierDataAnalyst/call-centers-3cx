-- ============================================================
-- FIX: eliminar todas las versiones duplicadas de kpi_llamadas
-- y recrear una sola versión correcta
-- Ejecutar completo en Supabase SQL Editor
-- ============================================================

-- PASO 1: borrar todas las versiones existentes
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure::text AS sig
    FROM pg_proc
    WHERE proname = 'kpi_llamadas'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

-- PASO 2: también limpiar heatmap si tiene duplicados
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure::text AS sig
    FROM pg_proc
    WHERE proname = 'kpi_heatmap_horas'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

-- PASO 3: recrear kpi_llamadas correcta
CREATE OR REPLACE FUNCTION kpi_llamadas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL
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
    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo = true
      AND (dept = 'todos' OR da.departamento = dept)
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
      AND (p_status     IS NULL OR fc.status_id = p_status)
      AND (p_agent_id   IS NULL OR fc.agent_id  = p_agent_id)

    UNION ALL

    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    WHERE fc.agent_id IS NULL
      AND fc.call_source = 'Cola'
      AND fc.status_id   = 'Waiting'
      AND p_agent_id IS NULL
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
      (AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60)::int::text,
      2, '0'
    ) || ':' || LPAD(
      MOD(ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12))::int, 60)::text,
      2, '0'
    ),
    COUNT(*) FILTER (WHERE talking_seconds >= 12),
    COUNT(*) FILTER (WHERE status_id = 'Answered'),
    COUNT(*) FILTER (WHERE status_id NOT IN ('Answered','Transferred')),
    COUNT(*) FILTER (WHERE status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL))
  FROM base;
$func$;

-- PASO 4: recrear kpi_heatmap_horas con p_status
CREATE OR REPLACE FUNCTION kpi_heatmap_horas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_status     TEXT DEFAULT NULL
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
    AND (dept = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
    AND (fecha_fin   IS NULL OR fc.date_key <= fecha_fin)
    AND (p_agent_id  IS NULL OR fc.agent_id  = p_agent_id)
    AND (p_status    IS NULL OR fc.status_id = p_status)
  GROUP BY 1, 2;
$func$;

-- VERIFICACIÓN: debe devolver una fila con números
SELECT * FROM kpi_llamadas();
