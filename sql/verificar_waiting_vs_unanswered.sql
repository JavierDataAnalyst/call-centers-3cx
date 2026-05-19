-- ¿Qué hay detrás de Waiting y Unanswered?
SELECT
  fc.status_id,
  fc.call_source,
  fc.queue_id,
  fc.direction_id,
  fc.agent_id IS NULL   AS sin_agente,
  COUNT(*)              AS total,
  ROUND(AVG(fc.ringing_seconds))  AS avg_ring_seg,
  ROUND(AVG(fc.talking_seconds))  AS avg_talk_seg
FROM fact_calls fc
WHERE fc.status_id IN ('Waiting', 'Unanswered')
GROUP BY fc.status_id, fc.call_source, fc.queue_id, fc.direction_id, (fc.agent_id IS NULL)
ORDER BY fc.status_id, total DESC;
