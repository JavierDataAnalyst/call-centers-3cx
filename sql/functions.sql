-- ============================================================
-- 3CX Dashboard — Supabase RPC Functions
-- All functions use SECURITY DEFINER to bypass RLS for the
-- Next.js frontend (anon key, read-only).
-- ============================================================

-- ── get_equipo: team agent list ───────────────────────────────

CREATE OR REPLACE FUNCTION get_equipo()
RETURNS TABLE(agent_id text, nombre text, departamento text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT agent_id, nombre, departamento
  FROM dim_agent
  WHERE es_equipo = true
  ORDER BY departamento, nombre;
$$;

-- ── kpi_llamadas: header KPI cards ───────────────────────────

DROP FUNCTION IF EXISTS kpi_llamadas(text,date,date,text,text);

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
  waiting_agente   bigint
)
LANGUAGE sql SECURITY DEFINER AS $$
  WITH base AS (
    -- Llamadas con agente asignado
    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    JOIN dim_agent da ON fc.agent_id = da.agent_id
    WHERE da.es_equipo = true
      AND (dept        = 'todos' OR da.departamento = dept)
      AND (fecha_inicio IS NULL  OR fc.date_key  >= fecha_inicio)
      AND (fecha_fin    IS NULL  OR fc.date_key  <= fecha_fin)
      AND (p_status     IS NULL  OR fc.status_id  = p_status)
      AND (p_agent_id   IS NULL  OR fc.agent_id   = p_agent_id)
      AND (p_direction  IS NULL  OR fc.direction_id = p_direction)

    UNION ALL

    -- Abandonos en cola (agent_id IS NULL) — siempre Inbound
    SELECT fc.talking_seconds, fc.status_id, fc.call_source
    FROM fact_calls fc
    WHERE fc.agent_id  IS NULL
      AND fc.call_source = 'Cola'
      AND fc.status_id   = 'Waiting'
      AND p_agent_id  IS NULL
      AND (p_direction IS NULL OR p_direction = 'Inbound')
      AND (dept = 'todos'
        OR (dept = 'Lender Review'    AND fc.queue_id = '835')
        OR (dept = 'Customer Service' AND fc.queue_id = '840'))
      AND (fecha_inicio IS NULL OR fc.date_key >= fecha_inicio)
      AND (fecha_fin    IS NULL OR fc.date_key <= fecha_fin)
      AND (p_status     IS NULL OR fc.status_id = p_status)
  )
  SELECT
    ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD((AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12) / 60)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(ROUND(AVG(talking_seconds) FILTER (WHERE talking_seconds >= 12))::int, 60)::text, 2, '0'),
    COUNT(*) FILTER (WHERE talking_seconds >= 12),
    COUNT(*) FILTER (WHERE status_id = 'Answered'),
    COUNT(*) FILTER (WHERE status_id NOT IN ('Answered','Transferred')),
    COUNT(*) FILTER (WHERE status_id = 'Unanswered'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND call_source = 'Cola'),
    COUNT(*) FILTER (WHERE status_id = 'Waiting' AND (call_source = 'Directo' OR call_source IS NULL))
  FROM base;
$$;

-- ── kpi_agentes: per-agent performance table ─────────────────

DROP FUNCTION IF EXISTS kpi_agentes(text,date,date,text);
DROP FUNCTION IF EXISTS kpi_agentes(text,date,date,text,text);

CREATE OR REPLACE FUNCTION kpi_agentes(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(
  agente            text,
  agent_id          text,
  departamento      text,
  avg_real_min      numeric,
  avg_real_mm_ss    text,
  llamadas_reales   bigint,
  dias_activos      bigint,
  avg_llamadas_dia  numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    da.nombre,
    da.agent_id,
    da.departamento,
    ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60.0, 1)::numeric,
    LPAD((AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12) / 60)::int::text, 2, '0')
      || ':' ||
      LPAD(MOD(ROUND(AVG(fc.talking_seconds) FILTER (WHERE fc.talking_seconds >= 12))::int, 60)::text, 2, '0'),
    COUNT(*) FILTER (WHERE fc.talking_seconds >= 12),
    COUNT(DISTINCT fc.date_key),
    ROUND(
      COUNT(*) FILTER (WHERE fc.talking_seconds >= 12)::numeric
      / NULLIF(COUNT(DISTINCT fc.date_key), 0),
    1)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento  = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key      >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key      <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id      = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id   = p_direction)
  GROUP BY da.nombre, da.agent_id, da.departamento
  ORDER BY llamadas_reales DESC;
$$;

-- ── kpi_llamadas_perdidas: lost calls breakdown ───────────────

CREATE OR REPLACE FUNCTION kpi_llamadas_perdidas()
RETURNS TABLE(
  categoria text,
  status_id text,
  total     bigint,
  pct       numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  WITH base AS (
    SELECT fc.status_id, dcs.categoria, COUNT(*) AS total
    FROM fact_calls fc
    JOIN dim_agent da     ON fc.agent_id  = da.agent_id
    JOIN dim_call_status dcs ON fc.status_id = dcs.status_id
    WHERE da.es_equipo = true
      AND dcs.es_contactada = false
    GROUP BY fc.status_id, dcs.categoria
  ),
  grand_total AS (SELECT SUM(total) AS gt FROM base)
  SELECT
    b.categoria,
    b.status_id,
    b.total,
    ROUND(b.total * 100.0 / NULLIF(gt.gt, 0), 1)
  FROM base b, grand_total gt
  ORDER BY b.total DESC;
$$;

-- ── kpi_heatmap_horas: calls heatmap (hour x day) ────────────

DROP FUNCTION IF EXISTS kpi_heatmap_horas(text,date,date,text,text);
DROP FUNCTION IF EXISTS kpi_heatmap_horas(text,date,date,text);

CREATE OR REPLACE FUNCTION kpi_heatmap_horas(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, total bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_status     IS NULL  OR fc.status_id    = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2;
$$;

-- ── kpi_colas_detalle: queue performance by month ─────────────

CREATE OR REPLACE FUNCTION kpi_colas_detalle()
RETURNS TABLE(
  cola          text,
  mes           int,
  total_llamadas bigint,
  contestadas   bigint,
  colgaron      bigint,
  pct_servicio  numeric,
  avg_min_habla numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    dq.nombre,
    EXTRACT(MONTH FROM dqs.report_date)::int,
    SUM(dqs.calls_total)::bigint,
    SUM(dqs.calls_answered)::bigint,
    SUM(dqs.calls_abandoned)::bigint,
    ROUND(SUM(dqs.calls_answered) * 100.0 / NULLIF(SUM(dqs.calls_total), 0), 1),
    ROUND(SUM(dqs.talk_time_total_seconds)::numeric / NULLIF(SUM(dqs.calls_answered), 0) / 60.0, 1)
  FROM detailed_queue_stats dqs
  JOIN dim_queue dq ON dq.queue_id = dqs.queue_id
  GROUP BY dq.nombre, EXTRACT(MONTH FROM dqs.report_date)
  ORDER BY 1, 2;
$$;

-- ── kpi_login_detalle: login times + occupancy per agent/day ──

CREATE OR REPLACE FUNCTION kpi_login_detalle(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL
)
RETURNS TABLE(
  agente                  text,
  departamento            text,
  fecha                   date,
  primer_login            timestamptz,
  ultimo_logout           timestamptz,
  total_logged_in_seconds bigint,
  total_talking_seconds   bigint
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    da.nombre,
    da.departamento,
    alh.date_key,
    MIN(alh.logged_in),
    MAX(alh.logged_out),
    SUM(alh.total_logged_in_seconds)::bigint,
    COALESCE(SUM(DISTINCT fc_agg.habla), 0)::bigint
  FROM agent_login_history alh
  JOIN dim_agent da ON alh.agent_id = da.agent_id
  LEFT JOIN (
    SELECT agent_id, date_key, SUM(talking_seconds) AS habla
    FROM fact_calls
    WHERE status_id = 'Answered'
    GROUP BY agent_id, date_key
  ) fc_agg ON fc_agg.agent_id = alh.agent_id AND fc_agg.date_key = alh.date_key
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR alh.date_key   >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR alh.date_key   <= fecha_fin)
    AND (p_agent_id   IS NULL  OR alh.agent_id    = p_agent_id)
  GROUP BY da.nombre, da.departamento, alh.date_key
  ORDER BY alh.date_key DESC, da.nombre;
$$;

-- ── kpi_heatmap_por_status: calls by hour/day/status ────────

DROP FUNCTION IF EXISTS kpi_heatmap_por_status(text,date,date,text);

CREATE OR REPLACE FUNCTION kpi_heatmap_por_status(
  dept         TEXT DEFAULT 'todos',
  fecha_inicio DATE DEFAULT NULL,
  fecha_fin    DATE DEFAULT NULL,
  p_agent_id   TEXT DEFAULT NULL,
  p_direction  TEXT DEFAULT NULL
)
RETURNS TABLE(hora int, dia int, status_id text, total bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int,
    fc.status_id,
    COUNT(*)
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_agent_id   IS NULL  OR fc.agent_id     = p_agent_id)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
  GROUP BY 1, 2, 3;
$$;

-- ── kpi_sla_asa: SLA % + Average Speed of Answer per queue ───

DROP FUNCTION IF EXISTS kpi_sla_asa(text);
DROP FUNCTION IF EXISTS kpi_sla_asa(text, integer);
DROP FUNCTION IF EXISTS kpi_sla_asa();

CREATE OR REPLACE FUNCTION kpi_sla_asa(
  p_dept        TEXT    DEFAULT 'todos',
  p_sla_seconds INTEGER DEFAULT 20        -- umbral SLA configurable (seg en cola)
)
RETURNS TABLE(
  cola           text,
  total_llamadas bigint,
  dentro_sla     bigint,
  pct_sla        numeric,
  asa_avg_sec    numeric,
  asa_med_sec    numeric,
  asa_p90_sec    numeric,
  sla_threshold  integer
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    dq.nombre,
    COUNT(*),
    COUNT(*) FILTER (WHERE qac.ringing_seconds <= p_sla_seconds),
    ROUND(COUNT(*) FILTER (WHERE qac.ringing_seconds <= p_sla_seconds) * 100.0
          / NULLIF(COUNT(*), 0), 1),
    ROUND(AVG(qac.ringing_seconds)::numeric, 0),
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qac.ringing_seconds)::numeric, 0),
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY qac.ringing_seconds)::numeric, 0),
    p_sla_seconds
  FROM queue_answered_calls qac
  JOIN dim_queue dq ON dq.queue_id = qac.queue_id
  WHERE (p_dept = 'todos' OR dq.nombre ILIKE
         CASE p_dept
           WHEN 'Customer Service' THEN '%servicio%'
           WHEN 'Lender Review'    THEN '%calidad%'
           ELSE '%'
         END)
  GROUP BY dq.nombre
  ORDER BY 1;
$$;

-- ── get_llamadas_detalle: drill-down call records ─────────────

DROP FUNCTION IF EXISTS get_llamadas_detalle(text,text,date,date,int,int,int,int,text);

CREATE OR REPLACE FUNCTION get_llamadas_detalle(
  dept         TEXT    DEFAULT 'todos',
  p_agent_id   TEXT    DEFAULT NULL,
  fecha_inicio DATE    DEFAULT NULL,
  fecha_fin    DATE    DEFAULT NULL,
  p_limit      INT     DEFAULT 50,
  p_offset     INT     DEFAULT 0,
  p_hora       INT     DEFAULT NULL,
  p_dia        INT     DEFAULT NULL,
  p_status     TEXT    DEFAULT NULL,
  p_direction  TEXT    DEFAULT NULL
)
RETURNS TABLE(
  call_id         text,
  call_time       timestamptz,
  agente          text,
  departamento    text,
  direction       text,
  status          text,
  ringing_seconds int,
  talking_seconds int,
  sentiment       text,
  summary         text
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    fc.call_id,
    fc.call_time,
    da.nombre,
    da.departamento,
    fc.direction_id,
    fc.status_id,
    fc.ringing_seconds,
    fc.talking_seconds,
    fc.sentiment,
    fc.summary
  FROM fact_calls fc
  JOIN dim_agent da ON fc.agent_id = da.agent_id
  WHERE da.es_equipo = true
    AND (dept        = 'todos' OR da.departamento = dept)
    AND (p_agent_id   IS NULL  OR fc.agent_id    = p_agent_id)
    AND (fecha_inicio IS NULL  OR fc.date_key    >= fecha_inicio)
    AND (fecha_fin    IS NULL  OR fc.date_key    <= fecha_fin)
    AND (p_status     IS NULL  OR fc.status_id   = p_status)
    AND (p_direction  IS NULL  OR fc.direction_id = p_direction)
    AND (p_hora       IS NULL  OR EXTRACT(HOUR FROM fc.call_time AT TIME ZONE 'UTC')::int = p_hora)
    AND (p_dia        IS NULL  OR EXTRACT(DOW  FROM fc.call_time AT TIME ZONE 'UTC')::int = p_dia)
  ORDER BY fc.call_time DESC
  LIMIT p_limit OFFSET p_offset;
$$;
