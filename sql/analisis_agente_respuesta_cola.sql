-- ============================================================
-- Análisis: velocidad de respuesta por agente en cola
-- ============================================================

-- 1. ¿Quién contesta más rápido? (promedio de espera del cliente)
SELECT
  da.nombre                                   AS agente,
  da.departamento,
  dq.nombre                                   AS cola,
  COUNT(*)                                    AS llamadas_contestadas,
  ROUND(AVG(qac.ringing_seconds))::int        AS espera_promedio_seg,
  MIN(qac.ringing_seconds)                    AS espera_minima_seg,
  MAX(qac.ringing_seconds)                    AS espera_maxima_seg,
  COUNT(*) FILTER (WHERE qac.ringing_seconds <= 20) AS dentro_sla_20s,
  ROUND(COUNT(*) FILTER (WHERE qac.ringing_seconds <= 20) * 100.0 / COUNT(*), 1) AS pct_sla
FROM queue_answered_calls qac
JOIN dim_agent da ON qac.destination_agent_id = da.agent_id
JOIN dim_queue dq  ON qac.queue_id = dq.queue_id
WHERE da.es_equipo = true
GROUP BY da.nombre, da.departamento, dq.nombre
ORDER BY espera_promedio_seg ASC;

-- ============================================================

-- 2. ¿A qué hora del día contesta más cada agente?
SELECT
  da.nombre                                                   AS agente,
  EXTRACT(HOUR FROM qac.call_time AT TIME ZONE 'UTC')::int    AS hora,
  COUNT(*)                                                    AS llamadas
FROM queue_answered_calls qac
JOIN dim_agent da ON qac.destination_agent_id = da.agent_id
WHERE da.es_equipo = true
GROUP BY da.nombre, hora
ORDER BY da.nombre, hora;

-- ============================================================

-- 3. Distribución de tiempos de espera (¿cuántos clientes esperan más de 1 min?)
SELECT
  dq.nombre AS cola,
  COUNT(*) FILTER (WHERE qac.ringing_seconds <= 20)               AS menos_20s,
  COUNT(*) FILTER (WHERE qac.ringing_seconds BETWEEN 21 AND 60)   AS entre_21_60s,
  COUNT(*) FILTER (WHERE qac.ringing_seconds BETWEEN 61 AND 120)  AS entre_1_2min,
  COUNT(*) FILTER (WHERE qac.ringing_seconds > 120)               AS mas_2min,
  COUNT(*)                                                         AS total
FROM queue_answered_calls qac
JOIN dim_queue dq ON qac.queue_id = dq.queue_id
GROUP BY dq.nombre
ORDER BY dq.nombre;
