# 3CX Dashboard — WH Financial

> Pipeline de datos automatizado que transforma los reportes CSV del sistema telefónico 3CX  
> en un dashboard interactivo de gerencia, desplegado en Vercel.

---

## Arquitectura

```
3CX PBX
   │
   │  Exportación semanal de CSVs (9 tipos de reporte)
   │  enviados automáticamente por email
   ▼
Outlook (correo corporativo)
   │
   │  Power Automate detecta el email con adjuntos
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

### Flujo detallado

| Paso | Tecnología | Descripción |
|---|---|---|
| 1 | **3CX PBX** | Genera y envía reportes CSV por email semanalmente |
| 2 | **Outlook** | Recibe el correo con los CSVs adjuntos |
| 3 | **Power Automate** | Detecta el email → sube cada adjunto a `data/incoming/` vía GitHub API |
| 4 | **GitHub Actions** | Trigger automático al detectar push en `data/incoming/**` |
| 5 | **Python ETL** | Transforma y carga los datos en Supabase (batch upsert) |
| 6 | **Supabase** | Almacena los datos en modelo estrella (PostgreSQL + RLS) |
| 7 | **Vercel** | Sirve el dashboard Next.js — consulta Supabase vía RPC functions |

---

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| Datos fuente | 3CX PBX — exportación CSV semanal |
| Automatización | Power Automate (Microsoft 365) |
| Versionado | GitHub |
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

### Departamentos

| Departamento | Agentes | Cola asociada |
|---|---|---|
| **Customer Service** | Rafael Silva Pulido · Lina Serna Jacome · Andres Felipe Torres Roa | WH Financial - Servicio al Cliente |
| **Lender Review** | David Santacruz · Laura Pinilla Salcedo · Maria Jimenez Fonseca · Yadira Angelica Cruz · Yeiman Manuel Jimenez Vargas · Yvessaint Loraint Amado Cubides | WH Financial - Calidad |

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
| `agent_schedules` | Supabase (edición manual) | Horarios por agente para alertas de overtime |

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
│   ├── incoming/               # Power Automate deposita CSVs aquí → dispara el pipeline
│   └── processed/              # CSVs archivados tras ingesta exitosa
├── .env.example
└── README.md
```

---

## Convención de nombres de archivos CSV

| Archivo | Tabla destino |
|---|---|
| `call_reports_*.csv` | `fact_calls` |
| `agent_login_history_*.csv` | `agent_login_history` |
| `agents_in_queue_statistics_*.csv` | `agents_in_queue_stats` |
| `team_queue_general_statistics_*.csv` | `team_queue_stats` |
| `detailed_queue_statistics_*.csv` | `detailed_queue_stats` |
| `queue_performance_*.csv` | `queue_performance` |
| `queue_answered_calls_by_wait_time_*.csv` | `queue_answered_calls` |
| `extension_statistics_by_group_*.csv` | `extension_statistics` |
| `user_activity_*.csv` | `user_activity` |

> El ETL detecta el tipo por **headers del CSV**, no por el nombre del archivo.  
> El nombre con fecha es opcional — Power Automate sube los archivos con el nombre original del adjunto.

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

## Power Automate — Configuración del flow

**Trigger:** Nuevo email en Outlook con adjuntos (filtrado por remitente o asunto de 3CX)

**Acciones:**
1. `Aplicar a cada uno` — itera sobre los adjuntos del email
2. `HTTP PUT` — sube cada CSV a `data/incoming/` vía GitHub API

```
PUT https://api.github.com/repos/{owner}/{repo}/contents/data/incoming/{nombre_archivo}
Authorization: Bearer {GITHUB_PAT}
Body: { "message": "auto: ingest {nombre}", "content": "{base64_content}" }
```

**Secrets requeridos en Power Automate:**
- `GITHUB_PAT` — Personal Access Token con scope `repo`

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

**Secrets requeridos en GitHub:**

| Secret | Descripción |
|---|---|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_KEY` | Service role key (escritura) |

---

## Supabase — RPC Functions

| Función | Descripción |
|---|---|
| `get_equipo()` | Lista de agentes del equipo |
| `get_agent_schedules()` | Horarios por agente (editable sin código) |
| `kpi_llamadas(dept, fechas, status, agent)` | KPIs globales de llamadas |
| `kpi_agentes(dept, fechas, status)` | Rendimiento por agente |
| `kpi_llamadas_perdidas()` | Desglose de llamadas no contestadas |
| `kpi_heatmap_horas(dept, fechas, agent)` | Mapa de calor hora × día |
| `kpi_heatmap_por_status(dept, fechas, agent)` | Heatmap desglosado por estado |
| `kpi_colas_detalle()` | Métricas de cola por mes |
| `kpi_colas_espera(dept)` | Llamada con mayor tiempo de espera |
| `kpi_colas_mensual(dept)` | Contestadas por mes (registros individuales) |
| `kpi_sla_asa(dept)` | SLA 80/20 + ASA + P90 por cola |
| `kpi_login_detalle(dept, fechas, agent)` | Login times + ocupación por agente/día |
| `get_llamadas_detalle(...)` | Drill-down de llamadas individuales |

---

## Gestión de horarios (sin código)

Para actualizar el horario de un agente, ejecutar en Supabase → SQL Editor:

```sql
UPDATE agent_schedules
SET start_hour = 9, end_hour = 18, updated_at = NOW()
WHERE agent_id = '127';  -- 127 = Rafael Silva Pulido
```

| agent_id | Agente | Horario actual |
|---|---|---|
| 127 | Rafael Silva Pulido | 7:00 – 16:00 |
| 595 | Lina Serna Jacome | 7:00 – 16:00 |
| 296 | Andres Felipe Torres Roa | 8:00 – 17:00 |

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

### 4. Power Automate

1. Crear Personal Access Token en GitHub (scope: `repo`)
2. Crear flow: Outlook trigger → HTTP PUT a GitHub API
3. Filtrar por remitente/asunto del email de 3CX

### 5. Primera ingesta manual (opcional)

```bash
# Colocar CSVs exportados desde 3CX en data/incoming/
git add data/incoming/
git commit -m "feat: carga inicial de datos"
git push
# GitHub Actions ejecuta el ETL automáticamente
```

---

## Dashboard

Repositorio: [`3cx-dashboard-web`](https://github.com/TU_USUARIO/3cx-dashboard-web)  
Deploy: Vercel Pro

### Pestañas

| Pestaña | Contenido |
|---|---|
| **Llamadas** | KPIs globales · Rendimiento por agente · Mapa de calor hora/día · Heatmap por estado |
| **Colas** | Resumen por cola · SLA 80/20 · ASA · Llamadas contestadas MoM · Detalle mensual |
| **Login Times** | Hora de entrada · Hora de salida · Tiempo conectado · % Ocupación · Alertas de overtime |

### Filtros disponibles

- **Departamento** — Customer Service / Lender Review (cambia color del header)
- **Período relativo** — Ayer · Esta semana · Últimas 2 semanas · Este mes · Últimos 3 meses · Este año
- **Fecha manual** — Desde / Hasta
- **Estado** — Answered · Unanswered · Waiting
- **Agente** — filtrado por departamento seleccionado

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
