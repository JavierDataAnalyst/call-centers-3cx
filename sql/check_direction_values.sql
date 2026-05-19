-- Ver todos los valores distintos de direction_id en fact_calls
SELECT
  direction_id,
  COUNT(*) AS total
FROM fact_calls
GROUP BY direction_id
ORDER BY total DESC;
