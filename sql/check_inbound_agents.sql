-- 1. Inbound calls: ¿tienen agent_id? ¿están en dim_agent?
SELECT
  fc.direction_id,
  fc.status_id,
  fc.agent_id,
  fc.call_source,
  da.nombre        AS nombre_agente,
  da.es_equipo,
  COUNT(*)         AS total
FROM fact_calls fc
LEFT JOIN dim_agent da ON fc.agent_id = da.agent_id
WHERE fc.direction_id = 'Inbound'
GROUP BY fc.direction_id, fc.status_id, fc.agent_id, fc.call_source,
         da.nombre, da.es_equipo
ORDER BY total DESC
LIMIT 30;

-- 2. Muestra de 10 llamadas Inbound para ver cómo lucen
SELECT
  call_id, call_time, direction_id, status_id,
  agent_id, call_source, queue_id, talking_seconds
FROM fact_calls
WHERE direction_id = 'Inbound'
ORDER BY call_time DESC
LIMIT 10;
