-- ============================================================
-- kpi_cobertura_login: correlación volumen de llamadas vs
-- agentes logueados por hora del día
-- Columnas reales: logged_in, logged_out, date_key, agent_id
-- ============================================================

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
  -- Llamadas totales por hora
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

  -- Días únicos con datos (para promedio diario)
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

  -- Por cada hora y día: cuántos agentes estaban logueados
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

  -- Promedio de agentes por hora entre todos los días
  agentes_hora AS (
    SELECT
      hora,
      ROUND(AVG(num_agentes), 1) AS avg_agentes
    FROM agentes_por_dia_hora
    GROUP BY hora
  )

  SELECT
    h.hora,
    COALESCE(lh.total, 0)::bigint                                           AS total_llamadas,
    ROUND(COALESCE(lh.total,0)::numeric / NULLIF(dt.num_dias,0), 1)        AS avg_llamadas_dia,
    COALESCE(ah.avg_agentes, 0)                                             AS avg_agentes_hora,
    CASE WHEN COALESCE(ah.avg_agentes, 0) > 0
      THEN ROUND(
        COALESCE(lh.total,0)::numeric / NULLIF(dt.num_dias,0) / ah.avg_agentes,
        1)
      ELSE 0
    END                                                                     AS llamadas_por_agente
  FROM generate_series(7, 21) AS h(hora)
  CROSS JOIN dias_totales dt
  LEFT JOIN llamadas_hora lh ON lh.hora = h.hora
  LEFT JOIN agentes_hora  ah ON ah.hora = h.hora
  ORDER BY h.hora;
$func$;

-- Verificación
SELECT
  hora,
  total_llamadas,
  avg_llamadas_dia   AS llamadas_por_dia,
  avg_agentes_hora   AS agentes_prom,
  llamadas_por_agente AS ratio
FROM kpi_cobertura_login()
ORDER BY hora;
