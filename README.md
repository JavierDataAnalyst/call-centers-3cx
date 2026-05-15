# 3CX Dashboard — WH Financial

> Pipeline de datos automatizado que transforma los reportes CSV del sistema telefónico 3CX  
> en un dashboard interactivo de gerencia, desplegado en Vercel.

---

## Arquitectura

```
3CX PBX
   │
   │  Exportación manual de CSVs (9 tipos de reporte)
   ▼
GitHub Repository  ──── push a data/incoming/ ────►  GitHub Actions
                                                             │
                                                    Python ETL (ingest.py)
                                                             │
                                                   Batch upsert → Supabase
                                                             │
                                          ◄──── Next.js Dashboard (Vercel)
                                               Consultas via RPC (anon key)
```

---

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| Datos fuente | 3CX PBX — exportación CSV |
| Almacenamiento | Supabase (PostgreSQL + RLS) |
| ETL | Python 3.11 · supabase-py · pandas |
| CI/CD del pipeline | GitHub Actions |
| Dashboard | Next.js 14 · TypeScript · Tailwind CSS |
| Hosting | Vercel Pro |

---

## Modelo de datos (Star Schema — 14 tablas)

```
                      ┌─────────────┐
                      │  dim_date   │
                      │  date_key   │
                      └──────┬──────┘
                             │
  ┌──────────────┐    ┌──────┴──────────┐    ┌──────────────────┐
  │  dim_agent   │    │   fact_calls    │    │  dim_call_status  │
  │  agent_id PK ├────┤  call_id PK     ├────┤  status_id PK     │
  │  nombre      │    │  call_time      │    │  categoria        │
  │  extension   │    │  agent_id  FK   │    │  es_contactada    │
  │  departamento│    │  date_key  FK   │    └──────────────────┘
  │  es_equipo   │    │  status_id FK   │
  └──────────────┘    │  direction_id FK│    ┌──────────────────┐
                      │  talking_sec    ├────┤  dim_direction    │
  ┌──────────────┐    │  ringing_sec    │    │  direction_id PK  │
  │  dim_queue   │    │  sentiment      │    │  es_entrante      │
  │  queue_id PK │    │  summary        │    └──────────────────┘
  │  nombre      │    └─────────────────┘
  └──────────────┘
```

### Tablas de resumen

| Tabla | Fuente CSV | Descripción |
|---|---|---|
| `agent_login_history` | `agent_login_history_*.csv` | Sesiones por agente y día |
| `agents_in_queue_stats` | `agents_in_queue_statistics_*.csv` | Métricas de agente por cola |
| `team_queue_stats` | `team_queue_general_statistics_*.csv` | Resumen de cola por equipo |
| `detailed_queue_stats` | `detailed_queue_statistics_*.csv` | Totales: contestadas, abandonadas |
| `queue_performance` | `queue_performance_*.csv` | Respuesta de agente por cola |
| `queue_answered_calls` | `queue_answered_calls_by_wait_time_*.csv` | Llamadas con tiempo de espera |
| `extension_statistics` | `extension_statistics_by_group_*.csv` | Estadísticas por extensión |
| `user_activity` | `user_activity_*.csv` | Actividad general del sistema |

---

## Estructura del repositorio

```
3cx-dashboard/
├── .github/
│   └── workflows/
│       └── ingest.yml          # Trigger: push a data/incoming/**
├── scripts/
│   ├── ingest.py               # ETL: detección automática, transformación, upsert
│   └── requirements.txt
├── sql/
│   ├── schema.sql              # Schema completo (ejecutar una vez en Supabase)
│   └── functions.sql           # RPC functions para el dashboard
├── data/
│   ├── incoming/               # Depositar CSVs aquí → dispara el pipeline
│   └── processed/              # CSVs archivados tras ingesta exitosa
├── .env.example
└── README.md
```

---

## Convención de nombres de archivos CSV

| Archivo | Tabla destino |
|---|---|
| `call_reports_YYYY-MM-DD.csv` | `fact_calls` |
| `agent_login_history_YYYY-MM-DD.csv` | `agent_login_history` |
| `agents_in_queue_statistics_YYYY-MM-DD.csv` | `agents_in_queue_stats` |
| `team_queue_general_statistics_YYYY-MM-DD.csv` | `team_queue_stats` |
| `detailed_queue_statistics_YYYY-MM-DD.csv` | `detailed_queue_stats` |
| `queue_performance_YYYY-MM-DD.csv` | `queue_performance` |
| `queue_answered_calls_by_wait_time_YYYY-MM-DD.csv` | `queue_answered_calls` |
| `extension_statistics_by_group_YYYY-MM-DD.csv` | `extension_statistics` |
| `user_activity_YYYY-MM-DD.csv` | `user_activity` |

> El ETL detecta el tipo por nombre de archivo y por headers del CSV.  
> La fecha en el nombre es opcional pero recomendada.

---

## ETL — Transformaciones

`scripts/ingest.py` realiza las siguientes transformaciones antes de insertar:

| Transformación | Entrada | Salida |
|---|---|---|
| Parseo de agente | `"402 Maria Jimenez"` | `extension="402"`, `nombre="Maria Jimenez"` |
| Normalización de cola | `"835 - WH Financial"` | `queue_id="835"`, `nombre="WH Financial"` |
| Conversión de tiempo | `"01:23:45"` | `5025` segundos |
| Normalización de dirección | `"inbound queue"` | `"Inbound"` |
| Normalización de estado | `"no answer"` | `"No Answer"` |
| Filtro de totales | Fila `"Totals"` del CSV | Eliminada |
| Deduplicación | `call_id` duplicado | Upsert — no genera duplicados |
| Batch upsert | Miles de filas | 3 llamadas HTTP por lote |

---

## GitHub Actions

**Trigger:** push de archivos a `data/incoming/**`

**Flujo:**
1. Checkout del repositorio
2. Setup Python 3.11
3. `pip install -r scripts/requirements.txt`
4. `python scripts/ingest.py`
5. Mover CSVs a `data/processed/`
6. Commit automático `[skip ci]`

**Secrets requeridos:**

| Secret | Descripción |
|---|---|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_KEY` | Service role key (escritura) |

---

## Setup desde cero

### 1. Base de datos (Supabase)

```sql
-- Ejecutar en orden en Supabase → SQL Editor:
-- 1. sql/schema.sql    → crea todas las tablas e índices
-- 2. sql/functions.sql → crea las RPC functions del dashboard
```

### 2. Repositorio local

```bash
git clone https://github.com/TU_USUARIO/3cx-dashboard.git
cd 3cx-dashboard
cp .env.example .env
# Completar .env con las credenciales de Supabase
```

### 3. Secrets en GitHub

```
Repository → Settings → Secrets and variables → Actions

SUPABASE_URL = https://xxxxxxxx.supabase.co
SUPABASE_KEY = service_role_key_aqui
```

### 4. Primera ingesta

```bash
# Colocar CSVs exportados desde 3CX en data/incoming/
git add data/incoming/
git commit -m "feat: carga inicial de datos"
git push
# GitHub Actions ejecuta el ETL automáticamente
```

---

## Dashboard

Repositorio separado: [`3cx-dashboard-web`](https://github.com/TU_USUARIO/3cx-dashboard-web)  
Deploy: Vercel Pro

**Pestañas:**

| Pestaña | Contenido |
|---|---|
| **Llamadas** | KPIs globales · Rendimiento por agente · Mapa de calor hora/día |
| **Colas** | Contestadas · Colgó esperando · % Servicio · Promedio de habla |
| **Login Times** | Hora de entrada · Hora de salida · Tiempo conectado · % Ocupación |

**Filtros disponibles:** Departamento · Fecha · Estado de llamada · Agente  
**Drill-down:** Clic en agente o celda del heatmap → panel lateral con llamadas subyacentes y paginación

---

## Resultado de prueba — 2026-05-14

| Tabla | Filas ingestadas |
|---|---|
| `fact_calls` | 9,279 |
| `agent_login_history` | 856 |
| `agents_in_queue_stats` | 9 |
| `queue_answered_calls` | 2,135 |
| **Tiempo total de ejecución** | **~5 segundos (9 archivos)** |

---

## Próximos pasos

- [ ] Automatizar envío de CSVs con Power Automate (email → GitHub)
- [ ] Autenticación con Supabase Auth o Vercel Password Protection
- [ ] Conexión directa a la API REST de 3CX para ingesta en tiempo real
- [ ] Análisis de sentiment con IA sobre transcripciones de llamadas

---

## Variables de entorno

### Pipeline (`scripts/ingest.py`)

```env
SUPABASE_URL=https://xxxxxxxx.supabase.co
SUPABASE_KEY=service_role_key
```

### Dashboard (`3cx-dashboard-web`)

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxxxxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=anon_key
```

---

*Uso interno — WH Financial. Repositorio privado.*
