"use client";

import { useEffect, useState, useCallback } from "react";
import Image from "next/image";
import { supabase } from "@/lib/supabase";

type Dept = "todos" | "Customer Service" | "Lender Review";
type Tab  = "llamadas" | "colas" | "login";

interface AgenteItem { agent_id: string; nombre: string; departamento: string; }

interface KpiLlamadas {
  avg_real_min: number;
  avg_real_mm_ss: string;
  llamadas_reales: number;
  total_answered: number;
  total_perdidas: number;
  total_unanswered: number;
  waiting_cola: number;
  waiting_agente: number;
}
interface Agente {
  agente: string;
  agent_id: string;
  departamento: string;
  avg_real_min: number;
  avg_real_mm_ss: string;
  llamadas_reales: number;
}
interface Cola {
  cola: string;
  mes: number;
  total_llamadas: number;
  contestadas: number;
  colgaron: number;
  pct_servicio: number;
  avg_min_habla: number;
}
interface ColaMensual {
  cola: string;
  mes: number;
  contestadas: number;
  avg_espera_sec: number;
}
interface ColaEspera {
  cola: string;
  max_espera_sec: number;
  agente: string;
  call_time: string;
}
interface ColaSla {
  cola: string;
  total_llamadas: number;
  dentro_sla: number;
  pct_sla: number;
  asa_avg_sec: number;
  asa_med_sec: number;
  asa_p90_sec: number;
}
interface LoginRow {
  agente: string;
  departamento: string;
  fecha: string;
  primer_login: string;
  ultimo_logout: string;
  total_logged_in_seconds: number;
  total_talking_seconds: number;
}
interface Perdida {
  categoria: string;
  status_id: string;
  total: number;
  pct: number;
}
interface HeatCell {
  hora: number;
  dia: number;
  total: number;
}
interface HeatCellStatus {
  hora: number;
  dia: number;
  status_id: string;
  total: number;
}
interface Llamada {
  call_id: string;
  call_time: string;
  agente: string;
  departamento: string;
  direction: string;
  status: string;
  ringing_seconds: number;
  talking_seconds: number;
  sentiment: string;
  summary: string;
}
interface DrillDown {
  titulo: string;
  agent_id?: string;
  hora?: number;
  dia?: number;
}

const MESES: Record<number, string> = {
  1:"Ene",2:"Feb",3:"Mar",4:"Abr",5:"May",6:"Jun",
  7:"Jul",8:"Ago",9:"Sep",10:"Oct",11:"Nov",12:"Dic"
};
const DIAS = ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"];
const HORAS = Array.from({length: 15}, (_, i) => i + 7); // 7am - 9pm

function fmtSec(s: number) {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function heatColor(val: number, max: number) {
  if (!val || !max) return "bg-gray-100 text-gray-300";
  const pct = val / max;
  if (pct >= 0.8) return "bg-red-600 text-white";
  if (pct >= 0.6) return "bg-red-400 text-white";
  if (pct >= 0.4) return "bg-yellow-400 text-gray-900";
  if (pct >= 0.2) return "bg-green-300 text-gray-900";
  return "bg-green-100 text-gray-600";
}

const RELATIVE_OPTIONS = [
  { value: "",         label: "Todo el período" },
  { value: "ayer",     label: "Ayer" },
  { value: "semana",   label: "Esta semana" },
  { value: "2semanas", label: "Últimas 2 semanas" },
  { value: "mes",      label: "Este mes" },
  { value: "3meses",   label: "Últimos 3 meses" },
  { value: "anio",     label: "Este año" },
];

function calcRelativeDates(option: string): { inicio: string; fin: string } {
  const today = new Date();
  const fmt   = (d: Date) => d.toISOString().split("T")[0];
  switch (option) {
    case "ayer": {
      const d = new Date(today); d.setDate(d.getDate() - 1);
      return { inicio: fmt(d), fin: fmt(d) };
    }
    case "semana": {
      const d = new Date(today);
      const dow = d.getDay();
      d.setDate(d.getDate() - (dow === 0 ? 6 : dow - 1)); // Monday
      return { inicio: fmt(d), fin: fmt(today) };
    }
    case "2semanas": {
      const d = new Date(today); d.setDate(d.getDate() - 13);
      return { inicio: fmt(d), fin: fmt(today) };
    }
    case "mes": {
      const d = new Date(today.getFullYear(), today.getMonth(), 1);
      return { inicio: fmt(d), fin: fmt(today) };
    }
    case "3meses": {
      const d = new Date(today); d.setMonth(d.getMonth() - 3);
      return { inicio: fmt(d), fin: fmt(today) };
    }
    case "anio": {
      const d = new Date(today.getFullYear(), 0, 1);
      return { inicio: fmt(d), fin: fmt(today) };
    }
    default: return { inicio: "", fin: "" };
  }
}

// Maps each queue name → the department that owns it
const QUEUE_DEPT: Record<string, Dept> = {
  "WH Financial - Calidad":            "Lender Review",
  "WH Financial - Servicio al Cliente": "Customer Service",
};

const DEPT_COLORS: Record<Dept, string> = {
  "todos":            "#0D36A6",
  "Customer Service": "#0D36A6",
  "Lender Review":    "#7C3AED",
};

export default function Dashboard() {
  const [tab,          setTab]          = useState<Tab>("llamadas");
  const [dept,         setDept]         = useState<Dept>("todos");
  const [fechaRelativa,setFechaRelativa]= useState("");
  const [fechaInicio,  setFechaInicio]  = useState("");
  const [fechaFin,     setFechaFin]     = useState("");

  function applyRelativa(val: string) {
    setFechaRelativa(val);
    const { inicio, fin } = calcRelativeDates(val);
    setFechaInicio(inicio);
    setFechaFin(fin);
  }
  const [status,     setStatus]     = useState("");
  const [agenteId,   setAgenteId]   = useState("");
  const [agentesLista, setAgentesLista] = useState<AgenteItem[]>([]);

  const [kpi,      setKpi]      = useState<KpiLlamadas | null>(null);
  const [agentes,  setAgentes]  = useState<Agente[]>([]);
  const [perdidas, setPerdidas] = useState<Perdida[]>([]);
  const [colas,    setColas]    = useState<Cola[]>([]);
  const [colasEspera,   setColasEspera]   = useState<ColaEspera[]>([]);
  const [colasMensual,  setColasMensual]  = useState<ColaMensual[]>([]);
  const [colasSla,      setColasSla]      = useState<ColaSla[]>([]);
  const [login,    setLogin]    = useState<LoginRow[]>([]);
  const [heat,       setHeat]       = useState<HeatCell[]>([]);
  const [heatStatus, setHeatStatus] = useState<HeatCellStatus[]>([]);
  const [loading,        setLoading]        = useState(true);
  const [drill,          setDrill]          = useState<DrillDown | null>(null);
  const [agentSchedules, setAgentSchedules] = useState<AgentSchedule[]>([]);

  const fi = fechaInicio || null;
  const ff = fechaFin    || null;
  const st = status      || null;
  const ai = agenteId    || null;

  useEffect(() => {
    supabase.rpc("get_equipo").then(({ data }) => setAgentesLista(data ?? []));
    supabase.rpc("get_agent_schedules").then(({ data }) => setAgentSchedules(data ?? []));
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    if (tab === "llamadas") {
      const [k, a, p, h, hs] = await Promise.all([
        supabase.rpc("kpi_llamadas",           { dept, fecha_inicio: fi, fecha_fin: ff, p_status: st, p_agent_id: ai }),
        supabase.rpc("kpi_agentes",            { dept, fecha_inicio: fi, fecha_fin: ff, p_status: st }),
        supabase.rpc("kpi_llamadas_perdidas"),
        supabase.rpc("kpi_heatmap_horas",      { dept, fecha_inicio: fi, fecha_fin: ff, p_agent_id: ai, p_status: st }),
        supabase.rpc("kpi_heatmap_por_status", { dept, fecha_inicio: fi, fecha_fin: ff, p_agent_id: ai }),
      ]);
      setKpi(k.data?.[0] ?? null);
      const todosAgentes: Agente[] = a.data ?? [];
      setAgentes(ai ? todosAgentes.filter(a => a.agent_id === ai) : todosAgentes);
      setPerdidas(p.data ?? []);
      setHeat(h.data ?? []);
      setHeatStatus(hs.data ?? []);
    } else if (tab === "colas") {
      const [{ data: colasData }, { data: esperaData }, { data: mensualData }, { data: slaData }] = await Promise.all([
        supabase.rpc("kpi_colas_detalle"),
        supabase.rpc("kpi_colas_espera",   { p_dept: dept }),
        supabase.rpc("kpi_colas_mensual",  { p_dept: dept }),
        supabase.rpc("kpi_sla_asa",        { p_dept: dept }),
      ]);
      setColas(colasData ?? []);
      setColasEspera(esperaData ?? []);
      setColasMensual(mensualData ?? []);
      setColasSla(slaData ?? []);
    } else {
      const { data } = await supabase.rpc("kpi_login_detalle", { dept, fecha_inicio: fi, fecha_fin: ff, p_agent_id: ai });
      setLogin(data ?? []);
    }
    setLoading(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, dept, fechaInicio, fechaFin, status, agenteId]);

  useEffect(() => { fetchData(); }, [fetchData]);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="px-8 pt-5 pb-4 transition-colors duration-300"
        style={{backgroundColor: DEPT_COLORS[dept]}}>

        {/* Fila 1: logo + selector de departamento */}
        <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
          <div className="flex items-center gap-4">
            <div className="bg-white rounded-lg px-3 py-1.5">
              <Image src="/logo.png" alt="WH Financial" width={110} height={44} className="object-contain" />
            </div>
            <div className="border-l border-white/30 pl-4">
              <p className="text-xs text-white/60 uppercase tracking-widest font-medium">Dashboard 3CX</p>
              <p className="text-sm text-white/85">Análisis de colas, agentes y experiencia del cliente</p>
            </div>
          </div>

          {/* Dept buttons prominentes */}
          <div className="flex items-center gap-3">
            {(["Customer Service","Lender Review"] as Dept[]).map(d => (
              <button key={d} onClick={() => { setDept(dept === d ? "todos" : d); setAgenteId(""); }}
                className={`px-6 py-2.5 rounded-lg text-sm font-semibold transition-all duration-200 ${
                  dept === d
                    ? "bg-white shadow-lg " + (d === "Customer Service" ? "text-[#0D36A6]" : "text-[#7C3AED]")
                    : "bg-white/15 text-white border border-white/30 hover:bg-white/25"
                }`}>
                {d}
              </button>
            ))}
            {dept !== "todos" && (
              <button onClick={() => { setDept("todos"); setAgenteId(""); }}
                className="text-white/50 hover:text-white text-xs underline transition-colors">
                Ver todo
              </button>
            )}
          </div>
        </div>

        {/* Fila 2: filtros */}
        <div className="flex flex-wrap items-center gap-3">
          {/* Fecha relativa */}
          <select value={fechaRelativa} onChange={e => applyRelativa(e.target.value)}
            className="border border-white/30 bg-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:outline-none focus:ring-2 focus:ring-white/50"
            style={{colorScheme:"dark"}}>
            {RELATIVE_OPTIONS.map(o => (
              <option key={o.value} value={o.value} style={{color:"#111",background:"#fff"}}>{o.label}</option>
            ))}
          </select>

          {/* Fecha manual */}
          <div className="flex items-center gap-2 text-sm">
            <label className="text-white/70 text-xs">Desde</label>
            <input type="date" value={fechaInicio}
              onChange={e => { setFechaRelativa(""); setFechaInicio(e.target.value); }}
              className="border border-white/30 bg-white/10 rounded-lg px-3 py-1.5 text-white focus:outline-none focus:ring-2 focus:ring-white/50" />
            <label className="text-white/70 text-xs">Hasta</label>
            <input type="date" value={fechaFin}
              onChange={e => { setFechaRelativa(""); setFechaFin(e.target.value); }}
              className="border border-white/30 bg-white/10 rounded-lg px-3 py-1.5 text-white focus:outline-none focus:ring-2 focus:ring-white/50" />
            {(fechaInicio || fechaFin) && (
              <button onClick={() => { applyRelativa(""); }}
                className="text-white/60 hover:text-white text-xs underline">Limpiar</button>
            )}
          </div>

          <select value={status} onChange={e => setStatus(e.target.value)}
            className="border border-white/30 bg-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:outline-none focus:ring-2 focus:ring-white/50"
            style={{colorScheme:"dark"}}>
            {[
              { value: "",            label: "Todos los estados" },
              { value: "Answered",    label: "Answered — Contestadas" },
              { value: "Unanswered",  label: "Unanswered — No contestadas" },
              { value: "Waiting",     label: "Waiting — Esperando" },
            ].map(s => (
              <option key={s.value} value={s.value} style={{color:"#111",background:"#fff"}}>
                {s.label}
              </option>
            ))}
          </select>

          <select value={agenteId} onChange={e => setAgenteId(e.target.value)}
            className="border border-white/30 bg-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:outline-none focus:ring-2 focus:ring-white/50"
            style={{colorScheme:"dark"}}>
            <option value="" style={{color:"#111",background:"#fff"}}>Todos los agentes</option>
            {agentesLista
              .filter(a => dept === "todos" || a.departamento === dept)
              .map(a => (
                <option key={a.agent_id} value={a.agent_id} style={{color:"#111",background:"#fff"}}>{a.nombre}</option>
              ))}
          </select>
        </div>
      </header>

      {/* Tabs */}
      <div className="bg-white border-b border-gray-200 px-8">
        <nav className="flex gap-6">
          {([["llamadas","Llamadas"],["colas","Colas"],["login","Login Times"]] as [Tab,string][]).map(([t, label]) => (
            <button key={t} onClick={() => setTab(t)}
              className={`py-3 text-sm font-medium border-b-2 transition-colors ${
                tab === t ? "border-[#0D36A6] text-[#0D36A6]" : "border-transparent text-gray-500 hover:text-[#0D36A6]"
              }`}>
              {label}
            </button>
          ))}
        </nav>
      </div>

      <main className="px-8 py-6 max-w-7xl mx-auto">
        {loading ? (
          <div className="flex items-center justify-center py-24">
            <p className="text-gray-400">Cargando datos...</p>
          </div>
        ) : (
          <>
            {tab === "llamadas" && <TabLlamadas kpi={kpi} agentes={agentes} perdidas={perdidas} heat={heat} heatStatus={heatStatus} dept={dept} onDrill={setDrill} />}
            {tab === "colas"    && <TabColas colas={colas} colasEspera={colasEspera} colasMensual={colasMensual} colasSla={colasSla} dept={dept} />}
            {tab === "login"    && <TabLogin login={login} schedules={agentSchedules} />}
          </>
        )}

        {drill && (
          <DrillModal
            titulo={drill.titulo}
            dept={dept}
            agentId={drill.agent_id}
            hora={drill.hora}
            dia={drill.dia}
            fechaInicio={fi ?? undefined}
            fechaFin={ff ?? undefined}
            pStatus={st ?? undefined}
            onClose={() => setDrill(null)}
          />
        )}
      </main>
    </div>
  );
}

/* ── Service Level Widget ─────────────────────────────────────────────── */
function ServiceLevelWidget({ kpi }: { kpi: KpiLlamadas | null }) {
  const answered = kpi?.total_answered ?? 0;
  const perdidas = kpi?.total_perdidas ?? 0;
  const total    = answered + perdidas;
  const pct      = total > 0 ? Math.round(answered * 100 / total) : 0;

  const color   = pct >= 80 ? "#16a34a" : pct >= 60 ? "#f59e0b" : "#ef4444";
  const label   = pct >= 80 ? "Excelente" : pct >= 60 ? "Regular"  : "Por mejorar";
  const bgLight = pct >= 80 ? "bg-green-50" : pct >= 60 ? "bg-yellow-50" : "bg-red-50";

  const R    = 46;
  const SW   = 10;
  const circ = 2 * Math.PI * R;
  const dash = (pct / 100) * circ;

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5 flex flex-col items-center justify-between min-w-[180px] w-[200px]">
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-widest text-center">
        Nivel de Servicio
      </p>

      {/* Donut SVG */}
      <div className="relative my-3">
        <svg width={112} height={112} className="-rotate-90">
          <circle cx={56} cy={56} r={R} fill="none" stroke="#f3f4f6" strokeWidth={SW} />
          <circle cx={56} cy={56} r={R} fill="none" stroke={color} strokeWidth={SW}
            strokeDasharray={`${dash} ${circ}`} strokeLinecap="round"
            style={{transition:"stroke-dasharray 0.6s ease"}} />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-extrabold leading-none" style={{color}}>{pct}%</span>
          <span className="text-[10px] text-gray-400 mt-0.5">contestadas</span>
        </div>
      </div>

      {/* Label */}
      <span className={`text-xs font-semibold px-3 py-1 rounded-full ${bgLight}`} style={{color}}>
        {label}
      </span>

      {/* Stats */}
      <div className="mt-3 w-full space-y-2 text-xs">
        <div className="flex items-center justify-between">
          <span className="text-gray-400 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-green-500 inline-block" /> Contestadas
          </span>
          <span className="font-semibold text-green-600">{answered.toLocaleString()}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-gray-400 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-red-400 inline-block" /> Perdidas
          </span>
          <span className="font-semibold text-red-500">{perdidas.toLocaleString()}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-gray-400 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-blue-400 inline-block" /> Promedio
          </span>
          <span className="font-semibold text-gray-700">{kpi?.avg_real_mm_ss ?? "—"}</span>
        </div>
      </div>
    </div>
  );
}

/* ── Multi-status heatmap ─────────────────────────────────────────────── */
const STATUS_META: Record<string, { label: string; color: string; bg: string }> = {
  "Answered":    { label: "Contestadas",  color: "#16a34a", bg: "#dcfce7" },
  "Transferred": { label: "Transferidas", color: "#2563eb", bg: "#dbeafe" },
  "No Answer":   { label: "Sin respuesta",color: "#ef4444", bg: "#fee2e2" },
  "Unanswered":  { label: "No contestada",color: "#f97316", bg: "#ffedd5" },
  "Waiting":     { label: "Esperando",    color: "#f59e0b", bg: "#fef3c7" },
  "Cancelled":   { label: "Canceladas",   color: "#6b7280", bg: "#f3f4f6" },
  "Busy":        { label: "Ocupado",      color: "#a855f7", bg: "#f3e8ff" },
  "Failed":      { label: "Fallidas",     color: "#991b1b", bg: "#fee2e2" },
};

function MultiStatusHeatmap({ data }: { data: HeatCellStatus[] }) {
  const totalGlobal = data.reduce((s, d) => s + d.total, 0);
  const minCalls    = Math.max(50, totalGlobal * 0.02); // at least 2% of total or 50 calls

  const statuses = [...new Set(data.map(d => d.status_id))]
    .filter(sid => data.filter(d => d.status_id === sid).reduce((s, d) => s + d.total, 0) >= minCalls)
    .sort((a, b) => {
      const order = ["Answered","Transferred","No Answer","Unanswered","Waiting","Cancelled","Busy","Failed"];
      return order.indexOf(a) - order.indexOf(b);
    });

  if (!statuses.length) return null;

  return (
    <div className="space-y-4">
      {statuses.map(sid => {
        const meta    = STATUS_META[sid] ?? { label: sid, color: "#6b7280", bg: "#f3f4f6" };
        const rows    = data.filter(d => d.status_id === sid);
        const maxVal  = Math.max(...rows.map(r => r.total), 1);
        const getCell = (dia: number, hora: number) =>
          rows.find(r => r.dia === dia && r.hora === hora)?.total ?? 0;

        return (
          <div key={sid} className="bg-white rounded-xl border border-gray-200 p-4">
            {/* Header */}
            <div className="flex items-center gap-2 mb-3">
              <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{backgroundColor: meta.color}} />
              <span className="text-xs font-semibold text-gray-700">{meta.label}</span>
              <span className="text-xs text-gray-400 ml-1">
                — {rows.reduce((s, r) => s + r.total, 0).toLocaleString()} llamadas
              </span>
            </div>

            {/* Grid */}
            <div className="inline-block">
              {/* Hours header */}
              <div className="flex mb-0.5 ml-10">
                {HORAS.map(h => (
                  <div key={h} className="w-8 text-center text-[10px] text-gray-400">{h}h</div>
                ))}
              </div>
              {[1,2,3,4,5,6,0].map(dia => (
                <div key={dia} className="flex items-center mb-0.5">
                  <span className="w-10 text-[10px] text-gray-400 font-medium">{DIAS[dia]}</span>
                  {HORAS.map(hora => {
                    const val = getCell(dia, hora);
                    const intensity = val > 0 ? Math.max(0.15, val / maxVal) : 0;
                    return (
                      <div key={hora}
                        title={`${DIAS[dia]} ${hora}h: ${val}`}
                        className="w-8 h-6 rounded text-[10px] flex items-center justify-center mx-px transition-opacity"
                        style={{
                          backgroundColor: val > 0 ? meta.color : "#f9fafb",
                          opacity: val > 0 ? 0.2 + intensity * 0.8 : 1,
                          color: val > 0 ? "#fff" : "#d1d5db",
                          fontWeight: 600,
                        }}>
                        {val > 0 ? val : ""}
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* ── Tab Llamadas ──────────────────────────────────────────────────────── */
function TabLlamadas({ kpi, agentes, perdidas, heat, heatStatus, dept, onDrill }: {
  kpi: KpiLlamadas | null; agentes: Agente[]; perdidas: Perdida[];
  heat: HeatCell[]; heatStatus: HeatCellStatus[]; dept: Dept;
  onDrill: (d: DrillDown) => void;
}) {
  const maxHeat = Math.max(...heat.map(h => h.total), 1);
  const getCell = (dia: number, hora: number) =>
    heat.find(h => h.dia === dia && h.hora === hora)?.total ?? 0;

  return (
    <div className="space-y-8">
      {/* KPI Cards */}
      <section>
        <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">
          Resumen — {dept === "todos" ? "Todos los equipos" : dept}
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
          <KpiCard label="Contestadas"      value={kpi?.total_answered?.toLocaleString() ?? "—"}    sub="Answered" color="#16a34a" />
          <KpiCard label="No Contestadas"   value={kpi?.total_unanswered?.toLocaleString() ?? "0"} sub="Unanswered" color="#ef4444" />
          <KpiCard label="Abandonos en Cola" value={kpi?.waiting_cola?.toLocaleString() ?? "0"}     sub="Colgaron esperando en queue" color="#f59e0b" />
          <KpiCard label="Sin Respuesta Agente" value={kpi?.waiting_agente?.toLocaleString() ?? "0"} sub="Waiting directo a agente" color="#a78bfa" />
          <KpiCard label="Tiempo Promedio"  value={kpi?.avg_real_mm_ss ?? "—"}                      sub="llamadas ≥ 12 seg" />
          <KpiCard label="Llamadas Reales"  value={kpi?.llamadas_reales?.toLocaleString() ?? "—"}   sub="duración ≥ 12 seg" />
        </div>
      </section>

      {/* Heatmap */}
      <section>
        <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">
          Mapa de Calor — Llamadas por Hora y Día
        </h2>
        <div className="flex gap-4">
        <div className="bg-white rounded-xl border border-gray-200 p-5 overflow-x-auto flex-1">
          <div className="inline-block min-w-full">
            {/* Horas header */}
            <div className="flex mb-1 ml-12">
              {HORAS.map(h => (
                <div key={h} className="w-10 text-center text-xs text-gray-400 font-medium">
                  {h}h
                </div>
              ))}
            </div>
            {/* Filas por día */}
            {[1,2,3,4,5,6,0].map(dia => (
              <div key={dia} className="flex items-center mb-1">
                <span className="w-12 text-xs text-gray-500 font-medium">{DIAS[dia]}</span>
                {HORAS.map(hora => {
                  const val = getCell(dia, hora);
                  return (
                    <div key={hora}
                      title={`${DIAS[dia]} ${hora}h: ${val} llamadas — clic para ver detalle`}
                      onClick={() => val > 0 && onDrill({ titulo: `${DIAS[dia]} ${hora}:00h — ${val} llamadas`, hora, dia })}
                      className={`w-10 h-8 rounded text-xs flex items-center justify-center mx-0.5 transition-opacity ${heatColor(val, maxHeat)} ${val > 0 ? "cursor-pointer hover:ring-2 hover:ring-gray-400" : "cursor-default"}`}>
                      {val > 0 ? val : ""}
                    </div>
                  );
                })}
              </div>
            ))}
            {/* Leyenda */}
            <div className="flex items-center gap-2 mt-4 ml-12">
              <span className="text-xs text-gray-400">Menor</span>
              {["bg-green-100","bg-green-300","bg-yellow-400","bg-red-400","bg-red-600"].map(c => (
                <div key={c} className={`w-6 h-4 rounded ${c}`} />
              ))}
              <span className="text-xs text-gray-400">Mayor</span>
            </div>
          </div>
        </div>

        {/* Widget nivel de servicio */}
        <ServiceLevelWidget kpi={kpi} />
      </div>
      </section>

      {/* Heatmap por status */}
      <section>
        <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">
          Distribución por Estado — Hora y Día
        </h2>
        <MultiStatusHeatmap data={heatStatus} />
      </section>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Agentes */}
        <section>
          <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">Rendimiento por Agente</h2>
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500">
                <tr>
                  <th className="text-left px-5 py-3 font-medium">Agente</th>
                  <th className="text-left px-5 py-3 font-medium">Equipo</th>
                  <th className="text-right px-5 py-3 font-medium">Llamadas</th>
                  <th className="text-right px-5 py-3 font-medium">Prom.</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {agentes.map(a => (
                  <tr key={a.agente} className="hover:bg-gray-50">
                    <td className="px-5 py-3 font-medium text-gray-900">{a.agente}</td>
                    <td className="px-5 py-3">
                      <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                        a.departamento === "Customer Service" ? "bg-blue-50 text-blue-700" : "bg-purple-50 text-purple-700"
                      }`}>{a.departamento === "Customer Service" ? "CS" : "LR"}</span>
                    </td>
                    <td className="px-5 py-3 text-right text-gray-600">{a.llamadas_reales?.toLocaleString()}</td>
                    <td className="px-5 py-3 text-right text-gray-600">{a.avg_real_mm_ss}</td>
                    <td className="px-5 py-3 text-right">
                      <button onClick={() => onDrill({ titulo: `Llamadas — ${a.agente}`, agent_id: a.agent_id })}
                        className="text-xs font-medium hover:underline whitespace-nowrap" style={{color:"#F48D14"}}>Ver →</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* Llamadas Perdidas */}
        <section>
          <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">Llamadas Perdidas</h2>
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500">
                <tr>
                  <th className="text-left px-5 py-3 font-medium">Estado</th>
                  <th className="text-right px-5 py-3 font-medium">Total</th>
                  <th className="text-right px-5 py-3 font-medium">%</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {perdidas.map(p => (
                  <tr key={p.status_id} className="hover:bg-gray-50">
                    <td className="px-5 py-3 text-gray-900">{p.status_id}</td>
                    <td className="px-5 py-3 text-right text-gray-600">{p.total?.toLocaleString()}</td>
                    <td className="px-5 py-3 text-right font-semibold text-red-500">{p.pct}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  );
}

/* ── SLA Gauge ────────────────────────────────────────────────────────── */
function SlaGauge({ sla }: { sla: ColaSla }) {
  const pct   = Number(sla.pct_sla) || 0;
  const color = pct >= 80 ? "#16a34a" : pct >= 60 ? "#f59e0b" : "#ef4444";
  const label = pct >= 80 ? "Meta alcanzada" : pct >= 60 ? "En riesgo" : "Por debajo";
  const R = 42, SW = 9;
  const circ = 2 * Math.PI * R;
  const dash = (pct / 100) * circ;

  function fmtSec(s: number) {
    if (s < 60) return `${s}s`;
    return `${Math.floor(s / 60)}m ${s % 60}s`;
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-5">
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">
        SLA &amp; Velocidad de Respuesta
      </p>
      <div className="flex items-center gap-5">
        {/* Donut */}
        <div className="relative flex-shrink-0">
          <svg width={100} height={100} className="-rotate-90">
            <circle cx={50} cy={50} r={R} fill="none" stroke="#f3f4f6" strokeWidth={SW} />
            <circle cx={50} cy={50} r={R} fill="none" stroke={color} strokeWidth={SW}
              strokeDasharray={`${dash} ${circ}`} strokeLinecap="round"
              style={{transition:"stroke-dasharray 0.6s ease"}} />
          </svg>
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span className="text-xl font-extrabold leading-none" style={{color}}>{pct}%</span>
            <span className="text-[9px] text-gray-400 mt-0.5">SLA</span>
          </div>
        </div>

        {/* Metrics */}
        <div className="flex-1 space-y-2.5">
          <div>
            <span className={`text-xs font-semibold px-2 py-0.5 rounded-full`}
              style={{color, backgroundColor: color + "15"}}>
              {label}
            </span>
            <p className="text-[10px] text-gray-400 mt-1">
              {sla.dentro_sla.toLocaleString()} de {sla.total_llamadas.toLocaleString()} contestadas ≤ 20s
            </p>
          </div>
          <div className="grid grid-cols-3 gap-2 text-center">
            <div className="bg-gray-50 rounded-lg py-1.5 px-1">
              <p className="text-sm font-bold text-gray-700">{fmtSec(Number(sla.asa_avg_sec))}</p>
              <p className="text-[9px] text-gray-400 uppercase">ASA Prom.</p>
            </div>
            <div className="bg-gray-50 rounded-lg py-1.5 px-1">
              <p className="text-sm font-bold text-gray-700">{fmtSec(Number(sla.asa_med_sec))}</p>
              <p className="text-[9px] text-gray-400 uppercase">Mediana</p>
            </div>
            <div className="bg-gray-50 rounded-lg py-1.5 px-1">
              <p className="text-sm font-bold text-gray-700">{fmtSec(Number(sla.asa_p90_sec))}</p>
              <p className="text-[9px] text-gray-400 uppercase">P90</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Bar chart llamadas contestadas MoM ──────────────────────────────── */
function MensualBarChart({ filas, barHeight = 140 }: { filas: ColaMensual[]; barHeight?: number }) {
  if (!filas.length) return null;
  const maxVal = Math.max(...filas.map(f => f.contestadas), 1);
  return (
    <div className="flex items-end gap-2 w-full" style={{height: barHeight + 52}}>
      {filas.map((f, i) => {
        const prev      = filas[i - 1];
        const delta     = prev ? f.contestadas - prev.contestadas : null;
        const color     = "#0D36A6";
        const h         = Math.max(6, Math.round((f.contestadas / maxVal) * barHeight));
        return (
          <div key={f.mes} className="flex flex-col items-center gap-1 flex-1 min-w-0">
            {delta !== null ? (
              <span className={`text-[10px] font-semibold leading-none ${delta >= 0 ? "text-green-600" : "text-red-500"}`}>
                {delta >= 0 ? "+" : ""}{delta}
              </span>
            ) : <span className="text-[10px] leading-none text-transparent">0</span>}
            <span className="text-xs font-bold" style={{color}}>{f.contestadas.toLocaleString()}</span>
            <div className="w-full rounded-t-md transition-all" style={{height: h, backgroundColor: color, opacity: 0.8}} />
            <span className="text-xs font-medium text-gray-500">{MESES[f.mes]}</span>
          </div>
        );
      })}
    </div>
  );
}

/* ── Tab Colas ─────────────────────────────────────────────────────────── */
function MoMBadge({ curr, prev }: { curr: number; prev: number | null }) {
  if (prev === null) return <span className="text-gray-300 text-xs">—</span>;
  const delta = +(curr - prev).toFixed(1);
  if (delta === 0) return <span className="text-gray-400 text-xs">=</span>;
  const up = delta > 0;
  return (
    <span className={`text-xs font-semibold ${up ? "text-green-600" : "text-red-500"}`}>
      {up ? "▲" : "▼"} {Math.abs(delta)}pp
    </span>
  );
}

function TabColas({ colas, colasEspera, colasMensual, colasSla, dept }: {
  colas: Cola[]; colasEspera: ColaEspera[]; colasMensual: ColaMensual[]; colasSla: ColaSla[]; dept: Dept;
}) {
  // exclude pseudo-queue "Totals" and filter by department when one is selected
  const colasUnicas = [...new Set(colas.map(c => c.cola))]
    .filter(n => !n.toLowerCase().startsWith("total"))
    .filter(n => dept === "todos" || QUEUE_DEPT[n] === dept);

  function fmtEspera(sec: number) {
    const m = Math.floor(sec / 60), s = sec % 60;
    return m > 0 ? `${m}m ${s}s` : `${s}s`;
  }
  function fmtFecha(ts: string) {
    return new Date(ts).toLocaleDateString("es-PR", { month: "short", day: "numeric", timeZone: "UTC" });
  }

  // Build per-queue summary for the header banner
  const resumen = colasUnicas.map(nombre => {
    const filas      = colas.filter(c => c.cola === nombre);
    const total      = filas.reduce((s, f) => s + f.total_llamadas, 0);
    const contestadas= filas.reduce((s, f) => s + f.contestadas, 0);
    const colgaron   = filas.reduce((s, f) => s + f.colgaron, 0);
    const pct        = total > 0 ? Math.round(contestadas * 100 / total) : 0;
    const sla        = colasSla.find(s => s.cola === nombre);
    const shortName  = nombre.replace(/WH Financial\s*[-–]\s*/i, "");
    return { nombre, shortName, total, contestadas, colgaron, pct, sla };
  });

  return (
    <div className="space-y-10">

      {/* ── Resumen por cola ── */}
      <section>
        <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-3">
          Resumen por Cola
        </h2>
        <div className="grid grid-cols-2 gap-4">
          {resumen.map(r => {
            const color = r.pct >= 80 ? "#16a34a" : r.pct >= 60 ? "#f59e0b" : "#ef4444";
            const R = 36, SW = 8;
            const circ = 2 * Math.PI * R;
            const dash  = (r.pct / 100) * circ;
            return (
              <div key={r.nombre} className="bg-white rounded-xl border border-gray-200 p-5 flex items-center gap-5">
                {/* Mini donut */}
                <div className="relative flex-shrink-0">
                  <svg width={84} height={84} className="-rotate-90">
                    <circle cx={42} cy={42} r={R} fill="none" stroke="#f3f4f6" strokeWidth={SW} />
                    <circle cx={42} cy={42} r={R} fill="none" stroke={color} strokeWidth={SW}
                      strokeDasharray={`${dash} ${circ}`} strokeLinecap="round" />
                  </svg>
                  <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-lg font-extrabold leading-none" style={{color}}>{r.pct}%</span>
                    <span className="text-[9px] text-gray-400">servicio</span>
                  </div>
                </div>
                {/* Stats */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-bold text-gray-800 truncate mb-2">{r.shortName}</p>
                  <div className="grid grid-cols-3 gap-2 text-center">
                    <div>
                      <p className="text-base font-bold text-gray-700">{r.total.toLocaleString()}</p>
                      <p className="text-[10px] text-gray-400">Total</p>
                    </div>
                    <div>
                      <p className="text-base font-bold text-green-600">{r.contestadas.toLocaleString()}</p>
                      <p className="text-[10px] text-gray-400">Contestadas</p>
                    </div>
                    <div>
                      <p className="text-base font-bold text-orange-500">{r.colgaron.toLocaleString()}</p>
                      <p className="text-[10px] text-gray-400">Colgaron</p>
                    </div>
                  </div>
                  {r.sla && (
                    <p className="text-[10px] text-gray-400 mt-2">
                      SLA ≤20s: <span className="font-semibold" style={{color: Number(r.sla.pct_sla) >= 80 ? "#16a34a" : "#ef4444"}}>{r.sla.pct_sla}%</span>
                      &nbsp;·&nbsp;ASA prom: <span className="font-semibold text-gray-600">{Number(r.sla.asa_avg_sec)}s</span>
                      &nbsp;·&nbsp;P90: <span className="font-semibold text-gray-600">{Number(r.sla.asa_p90_sec)}s</span>
                    </p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* ── Gráficas MoM — ambas en paralelo ── */}
      <section>
        <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-1">
          Llamadas Contestadas por Mes
        </h2>
        <p className="text-xs text-gray-400 mb-4">Fuente: registros individuales de cola · Δ vs mes anterior</p>
        <div className="grid grid-cols-2 gap-4">
          {colasUnicas.map(nombre => {
            const filasMes  = colasMensual.filter(f => f.cola === nombre);
            const totalAnio = filasMes.reduce((s, f) => s + f.contestadas, 0);
            const shortName = nombre.replace(/WH Financial\s*[-–]\s*/i, "");
            return (
              <div key={nombre} className="bg-white rounded-xl border border-gray-200 p-5">
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide truncate mb-0.5">{shortName}</p>
                <p className="text-sm font-bold text-[#0D36A6] mb-3">
                  {totalAnio.toLocaleString()} contestadas en el año
                </p>
                <MensualBarChart filas={filasMes} barHeight={140} />
              </div>
            );
          })}
        </div>
      </section>

      {/* ── Detalle por cola ── */}
      {colasUnicas.map(nombre => {
        const filas      = colas.filter(c => c.cola === nombre);
        const esperaInfo = colasEspera.find(e => e.cola === nombre);
        const slaInfo    = colasSla.find(s => s.cola === nombre);
        const totales = {
          total:       filas.reduce((s, f) => s + f.total_llamadas, 0),
          contestadas: filas.reduce((s, f) => s + f.contestadas, 0),
          colgaron:    filas.reduce((s, f) => s + f.colgaron, 0),
        };
        const pctGlobal = totales.total > 0
          ? Math.round(totales.contestadas * 100 / totales.total) : 0;
        const mejorMes  = filas.reduce((best, f) => f.pct_servicio > (best?.pct_servicio ?? -1) ? f : best, filas[0]);
        const avgHabla  = filas.length ? (filas.reduce((s, f) => s + Number(f.avg_min_habla), 0) / filas.length).toFixed(1) : "—";
        const shortName = nombre.replace(/WH Financial\s*[-–]\s*/i, "");
        return (
          <section key={nombre}>
            <div className="flex items-center gap-4 mb-3 flex-wrap">
              <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">{shortName}</h2>
              <span className={`text-sm font-bold ${pctGlobal >= 80 ? "text-green-600" : "text-red-500"}`}>
                {pctGlobal}% servicio global
              </span>
              {mejorMes && (
                <span className="text-xs text-gray-400">
                  Mejor mes: <b className="text-green-600">{MESES[mejorMes.mes]} ({mejorMes.pct_servicio}%)</b>
                </span>
              )}
            </div>

            {/* SLA gauge */}
            {slaInfo && <div className="mb-4"><SlaGauge sla={slaInfo} /></div>}

            {/* KPI cards */}
            <div className="grid grid-cols-3 gap-4 mb-4">
              <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
                <p className="text-xs text-gray-400 mb-1">Espera más larga</p>
                {esperaInfo ? (
                  <>
                    <p className="text-2xl font-bold text-red-500">{fmtEspera(esperaInfo.max_espera_sec)}</p>
                    <p className="text-xs text-gray-500 mt-1 truncate">{esperaInfo.agente}</p>
                    <p className="text-xs text-gray-400">{fmtFecha(esperaInfo.call_time)}</p>
                  </>
                ) : <p className="text-gray-300 text-sm">—</p>}
              </div>

              <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
                <p className="text-xs text-gray-400 mb-1">Promedio en llamada</p>
                <p className="text-2xl font-bold" style={{color:"#0D36A6"}}>{avgHabla} min</p>
                <p className="text-xs text-gray-400 mt-1">llamadas contestadas</p>
              </div>

              <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
                <p className="text-xs text-gray-400 mb-1">Total llamadas</p>
                <p className="text-2xl font-bold text-gray-700">{totales.total.toLocaleString()}</p>
                <p className="text-xs text-gray-400 mt-1">
                  <span className="text-orange-500 font-medium">{totales.colgaron.toLocaleString()}</span> colgaron esperando
                </p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500">
                  <tr>
                    <th className="text-left px-5 py-3 font-medium">Mes</th>
                    <th className="text-right px-5 py-3 font-medium">Total</th>
                    <th className="text-right px-5 py-3 font-medium">vs mes ant.</th>
                    <th className="text-right px-5 py-3 font-medium">Contestadas</th>
                    <th className="text-right px-5 py-3 font-medium">Colgó esperando</th>
                    <th className="text-right px-5 py-3 font-medium">% Servicio</th>
                    <th className="text-right px-5 py-3 font-medium">MoM</th>
                    <th className="text-right px-5 py-3 font-medium">Prom. Habla</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filas.map((f, i) => {
                    const prev = filas[i - 1] ?? null;
                    const deltaTotal = prev ? f.total_llamadas - prev.total_llamadas : null;
                    return (
                    <tr key={f.mes} className={`hover:bg-gray-50 ${f.mes === mejorMes?.mes ? "bg-green-50/40" : ""}`}>
                      <td className="px-5 py-3 font-medium text-gray-900">
                        {MESES[f.mes]}
                        {f.mes === mejorMes?.mes && <span className="ml-1 text-xs text-green-500">★</span>}
                      </td>
                      <td className="px-5 py-3 text-right text-gray-600">{f.total_llamadas?.toLocaleString()}</td>
                      <td className="px-5 py-3 text-right">
                        {deltaTotal === null ? <span className="text-gray-300 text-xs">—</span> : (
                          <span className={`text-xs font-semibold ${deltaTotal >= 0 ? "text-blue-500" : "text-orange-500"}`}>
                            {deltaTotal >= 0 ? "+" : ""}{deltaTotal.toLocaleString()}
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3 text-right text-green-600">{f.contestadas?.toLocaleString()}</td>
                      <td className="px-5 py-3 text-right text-orange-500">{f.colgaron?.toLocaleString()}</td>
                      <td className="px-5 py-3 text-right">
                        <span className={`font-semibold ${Number(f.pct_servicio) >= 80 ? "text-green-600" : "text-red-500"}`}>
                          {f.pct_servicio}%
                        </span>
                      </td>
                      <td className="px-5 py-3 text-right">
                        <MoMBadge curr={Number(f.pct_servicio)} prev={prev ? Number(prev.pct_servicio) : null} />
                      </td>
                      <td className="px-5 py-3 text-right text-gray-600">{f.avg_min_habla} min</td>
                    </tr>
                  );
                  })}
                  {/* Totales */}
                  <tr className="bg-gray-50 font-semibold border-t-2 border-gray-200">
                    <td className="px-5 py-3 text-gray-700">Total</td>
                    <td className="px-5 py-3 text-right text-gray-700">{totales.total.toLocaleString()}</td>
                    <td className="px-5 py-3" />
                    <td className="px-5 py-3 text-right text-green-700">{totales.contestadas.toLocaleString()}</td>
                    <td className="px-5 py-3 text-right text-orange-600">{totales.colgaron.toLocaleString()}</td>
                    <td className="px-5 py-3 text-right">
                      <span className={`font-bold ${pctGlobal >= 80 ? "text-green-700" : "text-red-600"}`}>{pctGlobal}%</span>
                    </td>
                    <td className="px-5 py-3" />
                    <td className="px-5 py-3" />
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        );
      })}
    </div>
  );
}

/* ── Tab Login ─────────────────────────────────────────────────────────── */

interface AgentSchedule { agent_id: string; nombre: string; start_hour: number; end_hour: number; }
const OVERTIME_GRACE = 15; // minutes

function getSchedule(agente: string, schedules: AgentSchedule[]) {
  const norm = agente.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  return schedules.find(s => {
    const sNorm = s.nombre.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    return norm === sNorm;
  }) ?? null;
}

function isWeekend(fecha: string) {
  const d = new Date(fecha + "T00:00:00Z");
  const dow = d.getUTCDay();
  return dow === 0 || dow === 6;
}

function isOutsideSchedule(agente: string, primerLogin: string, ultimoLogout: string, schedules: AgentSchedule[]): boolean {
  const sched = getSchedule(agente, schedules);
  if (!sched || !primerLogin || !ultimoLogout) return false;
  const loginDate  = new Date(primerLogin);
  const logoutDate = new Date(ultimoLogout);
  const loginMin   = loginDate.getUTCHours()  * 60 + loginDate.getUTCMinutes();
  const logoutMin  = logoutDate.getUTCHours() * 60 + logoutDate.getUTCMinutes();
  const schedStart = sched.start_hour * 60;
  const schedEnd   = sched.end_hour   * 60;
  return loginMin > schedStart + OVERTIME_GRACE || logoutMin > schedEnd + OVERTIME_GRACE;
}

function TabLogin({ login, schedules }: { login: LoginRow[]; schedules: AgentSchedule[] }) {
  const agentesUnicos = [...new Set(login.map(r => r.agente))];

  function fmtHora(ts: string) {
    if (!ts) return "—";
    return new Date(ts).toLocaleTimeString("es-PR", { hour: "2-digit", minute: "2-digit", hour12: true, timeZone: "UTC" });
  }

  return (
    <div className="space-y-8">
      {agentesUnicos.map(nombre => {
        const filas      = login.filter(r => r.agente === nombre);
        const dept       = filas[0]?.departamento;
        const totalLogin = filas.reduce((s, r) => s + r.total_logged_in_seconds, 0);
        const totalHabla = filas.reduce((s, r) => s + r.total_talking_seconds, 0);
        const pctTotal   = totalLogin > 0 ? Math.min(100, Math.round(totalHabla * 100 / totalLogin)) : 0;
        const sched      = getSchedule(nombre, schedules);

        return (
          <section key={nombre}>
            <div className="flex items-center gap-3 mb-3 flex-wrap">
              <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">{nombre}</h2>
              <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                dept === "Customer Service" ? "bg-blue-50 text-blue-700" : "bg-purple-50 text-purple-700"
              }`}>{dept}</span>
              {sched && (
                <span className="text-xs text-gray-400">
                  Horario: <b>{sched.start_hour}:00 – {sched.end_hour}:00</b>
                </span>
              )}
              <span className="text-xs text-gray-400">
                Login total: <b>{fmtSec(totalLogin)}</b> · Habla total: <b>{fmtSec(totalHabla)}</b> · Ocupación: <b className={pctTotal >= 50 ? "text-green-600" : "text-yellow-600"}>{pctTotal}%</b>
              </span>
            </div>
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500">
                  <tr>
                    <th className="text-left px-5 py-3 font-medium">Fecha</th>
                    <th className="text-center px-5 py-3 font-medium">Entrada</th>
                    <th className="text-center px-5 py-3 font-medium">Salida</th>
                    <th className="text-right px-5 py-3 font-medium">Conectado</th>
                    <th className="text-right px-5 py-3 font-medium">En Llamada</th>
                    <th className="text-right px-5 py-3 font-medium">% Ocupación</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filas.map(f => {
                    const pct      = f.total_logged_in_seconds > 0
                      ? Math.min(100, Math.round(f.total_talking_seconds * 100 / f.total_logged_in_seconds)) : 0;
                    const weekend  = isWeekend(f.fecha);
                    const overtime = isOutsideSchedule(nombre, f.primer_login, f.ultimo_logout, schedules);
                    return (
                      <tr key={f.fecha}
                        className={`hover:brightness-95 transition-colors ${weekend ? "bg-purple-50" : ""}`}>
                        <td className="px-5 py-3 font-medium text-gray-900">
                          <span className={`mr-2 text-xs font-semibold ${weekend ? "text-purple-500" : "text-gray-400"}`}>
                            {DIAS[new Date(f.fecha + "T00:00:00Z").getUTCDay()]}
                          </span>
                          {f.fecha}
                        </td>
                        <td className="px-5 py-3 text-center text-green-700 font-medium">
                          {fmtHora(f.primer_login)}
                          {overtime && <span className="ml-1" title="Fuera de horario (>15 min)">😔</span>}
                        </td>
                        <td className="px-5 py-3 text-center text-red-500 font-medium">
                          {fmtHora(f.ultimo_logout)}
                          {overtime && <span className="ml-1" title="Fuera de horario (>15 min)">😔</span>}
                        </td>
                        <td className="px-5 py-3 text-right text-gray-600">{fmtSec(f.total_logged_in_seconds)}</td>
                        <td className="px-5 py-3 text-right text-gray-600">{fmtSec(f.total_talking_seconds)}</td>
                        <td className="px-5 py-3 text-right">
                          <span className={`font-semibold ${pct >= 50 ? "text-green-600" : pct >= 30 ? "text-yellow-600" : "text-red-500"}`}>
                            {pct}%
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>
        );
      })}
    </div>
  );
}

/* ── Drill Modal ───────────────────────────────────────────────────────── */
function DrillModal({ titulo, dept, agentId, hora, dia, fechaInicio, fechaFin, pStatus, onClose }: {
  titulo: string; dept: Dept; agentId?: string; hora?: number; dia?: number;
  fechaInicio?: string; fechaFin?: string; pStatus?: string; onClose: () => void;
}) {
  const [rows,    setRows]    = useState<Llamada[]>([]);
  const [loading, setLoading] = useState(true);
  const [offset,  setOffset]  = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const LIMIT = 50;

  useEffect(() => {
    setRows([]); setOffset(0); setHasMore(true);
  }, [titulo]);

  useEffect(() => {
    async function load() {
      setLoading(true);
      const { data } = await supabase.rpc("get_llamadas_detalle", {
        dept,
        p_agent_id:   agentId    ?? null,
        fecha_inicio: fechaInicio ?? null,
        fecha_fin:    fechaFin   ?? null,
        p_limit:      LIMIT,
        p_offset:     offset,
        p_hora:       hora    ?? null,
        p_dia:        dia     ?? null,
        p_status:     pStatus ?? null,
      });
      const items = data ?? [];
      setRows(prev => offset === 0 ? items : [...prev, ...items]);
      setHasMore(items.length === LIMIT);
      setLoading(false);
    }
    load();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offset]);

  function fmtTime(ts: string) {
    return new Date(ts).toLocaleString("es-PR", { dateStyle: "short", timeStyle: "short", timeZone: "UTC" });
  }
  function fmtS(s: number) {
    const m = Math.floor(s / 60), sec = s % 60;
    return `${m}:${String(sec).padStart(2,"0")}`;
  }
  function statusColor(s: string) {
    if (s === "Answered")    return "text-green-600";
    if (s === "Transferred") return "text-blue-600";
    return "text-red-500";
  }
  function sentimentIcon(s: string) {
    if (!s) return "";
    if (s.toLowerCase().includes("positive")) return "😊";
    if (s.toLowerCase().includes("negative")) return "😞";
    return "😐";
  }

  return (
    <div className="fixed inset-0 z-50 flex">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />

      {/* Panel */}
      <div className="relative ml-auto h-full w-full max-w-4xl bg-white shadow-2xl flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200" style={{backgroundColor:"#0D36A6"}}>
          <div>
            <h2 className="font-semibold text-white">{titulo}</h2>
            <p className="text-xs text-blue-200 mt-0.5">{rows.length} registros cargados</p>
          </div>
          <button onClick={onClose} className="text-white/70 hover:text-white text-2xl leading-none">×</button>
        </div>

        {/* Table */}
        <div className="flex-1 overflow-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500 sticky top-0">
              <tr>
                <th className="text-left px-4 py-3 font-medium">Fecha</th>
                <th className="text-left px-4 py-3 font-medium">Agente</th>
                <th className="text-left px-4 py-3 font-medium">Dirección</th>
                <th className="text-left px-4 py-3 font-medium">Estado</th>
                <th className="text-right px-4 py-3 font-medium">Repique</th>
                <th className="text-right px-4 py-3 font-medium">Habla</th>
                <th className="text-center px-4 py-3 font-medium">Sentiment</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(r => (
                <tr key={r.call_id} className="hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-600 whitespace-nowrap">{fmtTime(r.call_time)}</td>
                  <td className="px-4 py-2.5 font-medium text-gray-900 whitespace-nowrap">{r.agente}</td>
                  <td className="px-4 py-2.5 text-gray-600">{r.direction}</td>
                  <td className={`px-4 py-2.5 font-medium ${statusColor(r.status)}`}>{r.status}</td>
                  <td className="px-4 py-2.5 text-right text-gray-500">{fmtS(r.ringing_seconds)}</td>
                  <td className="px-4 py-2.5 text-right text-gray-700 font-medium">{fmtS(r.talking_seconds)}</td>
                  <td className="px-4 py-2.5 text-center" title={r.sentiment}>{sentimentIcon(r.sentiment)}</td>
                </tr>
              ))}
              {loading && (
                <tr><td colSpan={7} className="px-4 py-6 text-center text-gray-400">Cargando...</td></tr>
              )}
            </tbody>
          </table>
        </div>

        {/* Load more */}
        {hasMore && !loading && (
          <div className="px-6 py-4 border-t border-gray-100">
            <button onClick={() => setOffset(o => o + LIMIT)}
              className="w-full py-2 text-sm font-medium rounded-lg transition-colors hover:bg-orange-50"
              style={{color:"#F48D14"}}>
              Cargar más registros
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

/* ── KPI Card ──────────────────────────────────────────────────────────── */
function KpiCard({ label, value, sub, color = "#0D36A6" }: { label: string; value: string; sub: string; color?: string }) {
  return (
    <div className="bg-white rounded-xl border-l-4 px-5 py-4 shadow-sm" style={{borderColor: color}}>
      <p className="text-xs text-gray-500 font-medium">{label}</p>
      <p className="text-2xl font-bold mt-1" style={{color}}>{value}</p>
      <p className="text-xs text-gray-400 mt-1">{sub}</p>
    </div>
  );
}
