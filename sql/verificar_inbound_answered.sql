-- ============================================================
-- Verificación: llamadas Inbound Answered
-- ============================================================

-- 1. Total por dirección y estado
SELECT
  direction_id,
  status_id,
  COUNT(*)            AS total,
  COUNT(*) FILTER (WHERE talking_seconds >= 12) AS reales_12s,
  ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60.0, 1) AS avg_min
FROM fact_calls fc
JOIN dim_agent da ON fc.agent_id = da.agent_id
WHERE da.es_equipo = true
GROUP BY direction_id, status_id
ORDER BY direction_id, total DESC;

-- ============================================================

-- 2. Inbound Answered por agente
SELECT
  da.nombre                                               AS agente,
  da.departamento,
  COUNT(*)                                                AS total_answered,
  COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)        AS reales_12s,
  ROUND(AVG(fc.talking_seconds)
    FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)   AS avg_min
FROM fact_calls fc
JOIN dim_agent da ON fc.agent_id = da.agent_id
WHERE da.es_equipo = true
  AND fc.direction_id = 'Inbound'
  AND fc.status_id    = 'Answered'
GROUP BY da.nombre, da.departamento
ORDER BY total_answered DESC;

-- ============================================================

-- 3. Inbound Answered por mes (para comparar contra CSV histórico)
SELECT
  EXTRACT(YEAR  FROM fc.date_key)::int AS anio,
  EXTRACT(MONTH FROM fc.date_key)::int AS mes,
  COUNT(*)                              AS total_answered,
  COUNT(*) FILTER (WHERE fc.talking_seconds >= 12) AS reales_12s
FROM fact_calls fc
JOIN dim_agent da ON fc.agent_id = da.agent_id
WHERE da.es_equipo = true
  AND fc.direction_id = 'Inbound'
  AND fc.status_id    = 'Answered'
GROUP BY anio, mes
ORDER BY anio, mes;

-- ============================================================

-- 4. Comparación rápida: total contestadas en fact_calls vs queue stats
SELECT 'fact_calls Inbound Answered'        AS fuente, COUNT(*) AS total
FROM fact_calls fc
JOIN dim_agent da ON fc.agent_id = da.agent_id
WHERE da.es_equipo = true
  AND fc.direction_id = 'Inbound'
  AND fc.status_id    = 'Answered'

UNION ALL

SELECT 'detailed_queue_stats calls_answered' AS fuente, SUM(calls_answered)::bigint
FROM detailed_queue_stats

UNION ALL

SELECT 'agents_in_queue_stats calls_answered' AS fuente, SUM(calls_answered)::bigint
FROM agents_in_queue_stats;
