-- ============================================================
-- kpi_llamadas_diarias: llamadas por agente por día
-- Sin filtro de agente → resumen promedio por agente
-- Con filtro de agente → desglose día a día
-- ============================================================

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
    da.nombre                                                             AS agente,
    da.departamento,
    fc.date_key                                                           AS fecha,
    COUNT(*)                                                              AS total,
    COUNT(*) FILTER (WHERE fc.status_id = 'Answered')                    AS contestadas,
    COUNT(*) FILTER (WHERE fc.status_id = 'Unanswered')                  AS unanswered,
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)                     AS reales,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0) AS avg_seg,
    LPAD(FLOOR(COALESCE(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0) / 60)::int::text, 2, '0')
      || ':' ||
    LPAD(MOD(FLOOR(COALESCE(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12), 0))::int, 60)::text, 2, '0')
                                                                          AS avg_mm_ss
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

-- Verificación: promedio de llamadas diarias por agente (todos)
SELECT
  agente,
  departamento,
  COUNT(DISTINCT fecha)                       AS dias_activos,
  SUM(total)                                  AS total_llamadas,
  ROUND(AVG(total), 1)                        AS promedio_llamadas_dia,
  ROUND(AVG(contestadas), 1)                  AS prom_contestadas_dia,
  ROUND(AVG(reales), 1)                       AS prom_reales_dia
FROM kpi_llamadas_diarias()
GROUP BY agente, departamento
ORDER BY promedio_llamadas_dia DESC;
