# 3CX Dashboard — Pipeline de Datos

Pipeline automatizado que extrae reportes del sistema telefónico 3CX, los transforma y los carga en Supabase para alimentar un dashboard de gerencia.

---

## Arquitectura

```
3CX Reports (CSV)
      │
      ▼
GitHub → data/incoming/
      │
      ▼  (push trigger)
GitHub Actions
      │
      ▼
Python ETL (scripts/ingest.py)
      │
      ▼
Supabase (PostgreSQL)
      │
      ▼
Dashboard Gerencia (Vercel) ← próximo paso
```

---

## Estructura del Repositorio

```
3cx-dashboard/
├── .github/
│   └── workflows/
│       └── ingest.yml          # GitHub Actions — trigger automático
├── data/
│   ├── incoming/               # Depositar CSVs aquí para procesar
│   └── processed/              # CSVs archivados tras ingesta exitosa
├── scripts/
│   ├── ingest.py               # ETL principal (Python)
│   └── requirements.txt        # Dependencias Python
├── sql/
│   ├── schema.sql              # Schema completo de Supabase
│   └── migration_star.sql      # Migración: dim_direction + dim_call_status
├── .env.example                # Variables de entorno requeridas
└── README.md
```

---

## Modelo de Datos (Estrella — 13 tablas)

### Dimensiones
| Tabla | Descripción |
|-------|-------------|
| `dim_agent` | Agentes del equipo (extensión, nombre, flag `es_equipo`) |
| `dim_queue` | Colas de atención (CS, Calidad) |
| `dim_date` | Calendario completo 2025–2026 |
| `dim_direction` | Dirección de llamada (Inbound, Outbound, Internal) |
| `dim_call_status` | Estado de llamada (Answered, Waiting, Unanswered, etc.) |

### Tabla de Hechos
| Tabla | Descripción |
|-------|-------------|
| `fact_calls` | Registro individual de cada llamada con métricas y FKs |

### Tablas Operacionales
| Tabla | Fuente CSV |
|-------|-----------|
| `agent_login_history` | Login History (CS + Calidad) |
| `agents_in_queue_stats` | Agent In Queue Statistics |
| `detailed_queue_stats` | Detailed Queue Statistics |
| `queue_performance` | Queue Performance Overview |
| `queue_answered_calls` | Queue Answered Calls By Waiting Time |
| `extension_statistics` | Extension Statistics |
| `team_queue_stats` | Team Queue General Statistics |

---

## Reportes Soportados (9 tipos de CSV)

| Nombre del archivo | Tabla destino |
|--------------------|---------------|
| `call_reports_YYYY-MM-DD.csv` | `fact_calls` |
| `agent_login_history_YYYY-MM-DD.csv` | `agent_login_history` |
| `agent_login_history_calidad.csv` | `agent_login_history` |
| `agents_in_queue_statistics_YYYY-MM-DD.csv` | `agents_in_queue_stats` |
| `detailed_queue_statistics_YYYY-MM-DD.csv` | `detailed_queue_stats` |
| `queue_performance_YYYY-MM-DD.csv` | `queue_performance` |
| `queue_answered_calls_by_wait_time_YYYY-MM-DD.csv` | `queue_answered_calls` |
| `extension_statistics_by_group_YYYY-MM-DD.csv` | `extension_statistics` |
| `team_queue_general_statistics_YYYY-MM-DD.csv` | `team_queue_stats` |

> El script detecta el tipo automáticamente por nombre de archivo y headers. La fecha en el nombre (`YYYY-MM-DD`) es opcional pero recomendada.

---

## Cómo Usar

### 1. Configurar variables de entorno

```bash
cp .env.example .env
# Editar .env con tus credenciales de Supabase
```

```
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_KEY=tu-service-role-key
```

### 2. Instalar dependencias

```bash
pip install -r scripts/requirements.txt
```

### 3. Procesar CSVs manualmente

```bash
# Todos los archivos en data/incoming/
python scripts/ingest.py

# Un archivo específico
python scripts/ingest.py data/incoming/call_reports_2026-05-14.csv
```

### 4. Procesar vía GitHub Actions (automático)

1. Copiar los CSVs a `data/incoming/`
2. Hacer `git add` y `git push`
3. GitHub Actions ejecuta el ETL automáticamente
4. Los CSVs procesados se mueven a `data/processed/`

---

## GitHub Actions

**Trigger:** Push de archivos a `data/incoming/**`

**Secrets requeridos en el repositorio:**
- `SUPABASE_URL`
- `SUPABASE_KEY` (service_role, no anon key)

**Permisos:** `contents: write` (para archivar CSVs procesados)

---

## KPIs del Dashboard

| KPI | Fuente | Notas |
|-----|--------|-------|
| Tiempo promedio en llamada | `fact_calls` | Filtrar `talking_seconds >= 30` para excluir transferencias cortas |
| Colas más eficientes | `detailed_queue_stats` | Usar `SUM(calls_answered)/SUM(calls_total)`, no promediar `pct_calls_serviced` |
| Llamadas perdidas | `fact_calls` + `dim_call_status` | `es_contactada = false` |
| Productividad por agente | `fact_calls` + `dim_agent` | Filtrar `es_equipo = true` |

---

## Variables de Entorno

| Variable | Descripción |
|----------|-------------|
| `SUPABASE_URL` | URL del proyecto Supabase (`https://xxx.supabase.co`) |
| `SUPABASE_KEY` | Service role key (Legacy JWT — no usar anon key) |

---

## Próximos Pasos

- [ ] Construir dashboard en Vercel (Next.js)
- [ ] Autenticación para acceso exclusivo de gerencia
- [ ] Automatizar envío de CSVs con Power Automate (email → GitHub)
- [ ] Agregar `date_key` a `queue_answered_calls`
