-- ============================================================
-- kpi_llamadas_detalle: llamadas subyacentes de cada KPI card
-- p_tipo: 'answered' | 'unanswered' | 'reales' |
--         'abandono_cola' | 'cola_ignorada' | 'waiting_agente'
-- ============================================================

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
    -- Outbound e Internal: agentes del equipo (es_equipo=true)
    SELECT
      fc.call_id, fc.call_time,
      da.nombre       AS agente,
      da.departamento AS departamento,
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

    -- Inbound: llamadas externas (agent_id IS NULL)
    SELECT
      fc.call_id, fc.call_time,
      'Sin agente' AS agente,
      '—'          AS departamento,
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

  -- Cola ignorada: cualquier agente (sin filtro es_equipo)
  ignorada_calls AS (
    SELECT
      fc.call_id, fc.call_time,
      COALESCE(da.nombre, 'Agente ' || fc.agent_id) AS agente,
      COALESCE(da.departamento, '—')                AS departamento,
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
    bc.call_id,
    bc.call_time,
    bc.agente,
    bc.departamento,
    bc.direction_id,
    bc.status_id,
    bc.call_source,
    COALESCE(dq.nombre, bc.queue_id, '—') AS cola,
    bc.ringing_seconds,
    bc.talking_seconds
  FROM (
    SELECT * FROM base_calls
    WHERE (p_tipo = 'answered'      AND status_id = 'Answered')
       OR (p_tipo = 'unanswered'    AND status_id = 'Unanswered')
       OR (p_tipo = 'reales'        AND talking_seconds >= 12)
       OR (p_tipo = 'abandono_cola' AND status_id = 'Waiting'
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

-- ============================================================
-- Verificación: los totales deben coincidir con kpi_llamadas()
-- ============================================================
SELECT COUNT(*) AS contestadas    FROM kpi_llamadas_detalle('answered',      p_limit := 9999);
-- Esperado: 6968

SELECT COUNT(*) AS no_contestadas FROM kpi_llamadas_detalle('unanswered',    p_limit := 9999);
-- Esperado: 730

SELECT COUNT(*) AS abandono_cola  FROM kpi_llamadas_detalle('abandono_cola', p_limit := 9999);
-- Esperado: 389

SELECT COUNT(*) AS cola_ignorada  FROM kpi_llamadas_detalle('cola_ignorada', p_limit := 9999);
-- Esperado: 592
