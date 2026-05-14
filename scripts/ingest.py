"""
3CX → Supabase ingestion script.

Usage:
  python scripts/ingest.py                 # processes all CSVs in data/incoming/
  python scripts/ingest.py path/to/file.csv  # processes a single file

Naming your CSV files (for auto date detection):
  call_reports_2026-05-12.csv
  agent_login_history_2026-05-12.csv
  agents_in_queue_statistics_2026-05-12.csv
  team_queue_general_statistics_2026-05-12.csv
  detailed_queue_statistics_2026-05-12.csv
  queue_performance_2026-05-12.csv
  queue_answered_calls_by_wait_time_2026-05-12.csv
  extension_statistics_by_group_2026-05-12.csv
  user_activity_2026-05-12.csv

Environment variables required:
  SUPABASE_URL  — https://xxxx.supabase.co
  SUPABASE_KEY  — service_role key (not anon key)
"""

import csv
import logging
import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

INCOMING_DIR = Path(__file__).parent.parent / "data" / "incoming"

# ── helpers ────────────────────────────────────────────────────────────────

def dur_to_sec(s: str) -> int:
    """'HH:MM:SS' or '' → total seconds."""
    if not s or not s.strip():
        return 0
    parts = s.strip().split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(float(parts[2]))
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(float(parts[1]))
    except ValueError:
        pass
    return 0


def pct_to_float(s: str) -> float:
    """'80%' → 80.0"""
    if not s or not s.strip():
        return 0.0
    return float(s.strip().replace("%", ""))


def parse_agent(s: str):
    """'402 Maria Jimenez Fonseca' → ('402', 'Maria Jimenez Fonseca')"""
    s = s.strip()
    m = re.match(r"^(\d+)\s+(.+)$", s)
    return (m.group(1), m.group(2).strip()) if m else (s, s)


def parse_agent_parens(s: str):
    """'Rafael Silva Pulido (127)' → ('127', 'Rafael Silva Pulido')"""
    s = s.strip()
    m = re.match(r"^(.+?)\s+\((\d+)\)$", s)
    return (m.group(2), m.group(1).strip()) if m else parse_agent(s)


def norm_queue(s: str):
    """
    '835 - WH Financial - Calidad'  → ('835', 'WH Financial - Calidad')
    '835 WH Financial - Calidad'    → ('835', 'WH Financial - Calidad')
    """
    s = s.strip()
    m = re.match(r"^(\d+)\s*-\s*(.+)$", s)
    if m:
        return m.group(1), m.group(2).strip()
    m = re.match(r"^(\d+)\s+(.+)$", s)
    if m:
        return m.group(1), m.group(2).strip()
    return s, s


def queue_tipo(nombre: str) -> str:
    n = nombre.lower()
    if "calidad" in n:
        return "Calidad"
    if "sac" in n:
        return "SAC"
    return "General"


def date_from_filename(path: Path) -> str:
    """Extract YYYY-MM-DD from filename, else today."""
    m = re.search(r"(\d{4}-\d{2}-\d{2})", path.stem)
    return m.group(1) if m else date.today().isoformat()


def detect_type(path: Path, headers: list) -> str:
    """Detect report type from filename keywords and/or header names."""
    name = path.stem.lower()
    h = [x.strip().lower() for x in headers]

    if "call_report" in name or ("call id" in h and "from" in h and "to" in h):
        return "call_reports"
    if "agent_login" in name or ("logged in" in h and "logged out" in h):
        return "agent_login_history"
    if "agents_in_queue" in name or ("ring time total" in h and "agent" in h and "queue" in h):
        return "agents_in_queue_statistics"
    if "team_queue_general" in name or ("agents in team" in h):
        return "team_queue_general_statistics"
    if "detailed_queue" in name or ("calls abandoned" in h):
        return "detailed_queue_statistics"
    if "queue_performance" in name or ("extension polls" in h):
        return "queue_performance"
    if "queue_answered" in name or ("answer time" in h and "destination" in h):
        return "queue_answered_calls_by_wait_time"
    if "extension_stat" in name or ("inbound answered" in h and "agent extension" in h):
        return "extension_statistics_by_group"
    if "user_activity" in name or ("answered calls" in h and "unanswered calls" in h and len(h) == 3):
        return "user_activity"
    return "unknown"


def safe_int(v) -> int:
    try:
        return int(v) if v and str(v).strip() else 0
    except (ValueError, TypeError):
        return 0


def safe_float(v) -> float:
    try:
        return float(v) if v and str(v).strip() else 0.0
    except (ValueError, TypeError):
        return 0.0


# ── dim upserts ────────────────────────────────────────────────────────────

def upsert_agent(sb, agent_id: str, nombre: str):
    if not agent_id:
        return
    sb.table("dim_agent").upsert(
        {"agent_id": agent_id, "nombre": nombre, "extension": agent_id},
        on_conflict="agent_id",
    ).execute()


def upsert_queue(sb, queue_id: str, nombre: str):
    if not queue_id:
        return
    sb.table("dim_queue").upsert(
        {
            "queue_id": queue_id,
            "nombre": nombre,
            "codigo": queue_id,
            "tipo": queue_tipo(nombre),
        },
        on_conflict="queue_id",
    ).execute()


def upsert_date(sb, d: str):
    if not d:
        return
    try:
        dt = date.fromisoformat(d[:10])
    except ValueError:
        return
    sb.table("dim_date").upsert(
        {
            "date_key": dt.isoformat(),
            "anio": dt.year,
            "mes": dt.month,
            "dia": dt.day,
            "dia_semana": dt.strftime("%A"),
            "semana": dt.isocalendar()[1],
            "es_fin_semana": dt.weekday() >= 5,
        },
        on_conflict="date_key",
    ).execute()


# ── parsers / ingesters ────────────────────────────────────────────────────

def ingest_call_reports(sb, rows, report_date: str):
    records = []
    for r in rows:
        call_time = r.get("Call Time", "").strip()
        agent_id, agent_name = parse_agent_parens(r.get("From", ""))

        upsert_agent(sb, agent_id, agent_name)
        d = call_time[:10] if len(call_time) >= 10 else report_date
        upsert_date(sb, d)

        records.append({
            "call_id":               r.get("Call ID", "").strip(),
            "call_time":             call_time or None,
            "date_key":              d,
            "agent_id":              agent_id or None,
            "direction":             r.get("Direction", "").strip() or None,
            "status":                r.get("Status", "").strip() or None,
            "ringing_seconds":       dur_to_sec(r.get("Ringing", "")),
            "talking_seconds":       dur_to_sec(r.get("Talking", "")),
            "cost":                  safe_float(r.get("Cost", 0)),
            "call_activity_details": r.get("Call Activity Details", "").strip() or None,
            "sentiment":             r.get("Sentiment", "").strip() or None,
            "summary":               r.get("Summary", "").strip() or None,
            "transcription":         r.get("Transcription", "").strip() or None,
        })

    if records:
        sb.table("fact_calls").upsert(records, on_conflict="call_id").execute()
        log.info(f"  fact_calls: {len(records)} rows")


def ingest_agent_login(sb, rows, report_date: str):
    records = []
    for r in rows:
        agent_id, agent_name = parse_agent(r.get("Agent", ""))
        upsert_agent(sb, agent_id, agent_name)
        d = r.get("Day", report_date).strip()[:10]
        upsert_date(sb, d)
        records.append({
            "date_key":               d,
            "agent_id":               agent_id,
            "logged_in":              r.get("Logged In", "").strip() or None,
            "logged_out":             r.get("Logged Out", "").strip() or None,
            "total_logged_in_seconds": dur_to_sec(r.get("Total Logged In per day", "")),
            "total_talking_seconds":  dur_to_sec(r.get("Total Talking", "")),
        })
    if records:
        sb.table("agent_login_history").upsert(
            records, on_conflict="date_key,agent_id,logged_in"
        ).execute()
        log.info(f"  agent_login_history: {len(records)} rows")


def ingest_agents_in_queue(sb, rows, report_date: str):
    records = []
    upsert_date(sb, report_date)
    for r in rows:
        q_id, q_name = norm_queue(r.get("Queue", ""))
        agent_id, agent_name = parse_agent(r.get("Agent", ""))
        upsert_queue(sb, q_id, q_name)
        upsert_agent(sb, agent_id, agent_name)
        records.append({
            "queue_id":               q_id,
            "agent_id":               agent_id,
            "report_date":            report_date,
            "total_logged_in_seconds": dur_to_sec(r.get("Total Logged In Time", "")),
            "calls_answered":         safe_int(r.get("Calls Answered")),
            "pct_calls_serviced":     pct_to_float(r.get("% Calls Serviced", "")),
            "calls_answered_per_hour": safe_float(r.get("Calls Answered Per Hour")),
            "ring_time_total_seconds": dur_to_sec(r.get("Ring Time Total", "")),
            "ring_time_mean_seconds":  dur_to_sec(r.get("Ring Time Mean", "")),
            "talk_time_total_seconds": dur_to_sec(r.get("Talk Time Total", "")),
            "talk_time_mean_seconds":  dur_to_sec(r.get("Talk Time Mean", "")),
        })
    if records:
        sb.table("agents_in_queue_stats").upsert(
            records, on_conflict="queue_id,agent_id,report_date"
        ).execute()
        log.info(f"  agents_in_queue_stats: {len(records)} rows")


def ingest_team_queue(sb, rows, report_date: str):
    records = []
    upsert_date(sb, report_date)
    for r in rows:
        q_id, q_name = norm_queue(r.get("Queue", ""))
        upsert_queue(sb, q_id, q_name)
        records.append({
            "queue_id":         q_id,
            "report_date":      report_date,
            "agents_in_team":   safe_int(r.get("Agents in Team")),
            "calls_received":   safe_int(r.get("Number of Calls Received")),
            "calls_serviced":   safe_int(r.get("Number of Calls Serviced")),
            "calls_unanswered": safe_int(r.get("Number of Calls Unanswered")),
            "total_talk_seconds": dur_to_sec(r.get("Total Talk Time", "")),
            "avg_talk_seconds":   dur_to_sec(r.get("Average Talk Time", "")),
        })
    if records:
        sb.table("team_queue_stats").upsert(
            records, on_conflict="queue_id,report_date"
        ).execute()
        log.info(f"  team_queue_stats: {len(records)} rows")


def ingest_detailed_queue(sb, rows, report_date: str):
    records = []
    upsert_date(sb, report_date)
    for r in rows:
        q_id, q_name = norm_queue(r.get("Queue", ""))
        upsert_queue(sb, q_id, q_name)
        records.append({
            "queue_id":              q_id,
            "report_date":           report_date,
            "calls_total":           safe_int(r.get("Calls Total")),
            "calls_abandoned":       safe_int(r.get("Calls Abandoned")),
            "calls_answered":        safe_int(r.get("Calls Answered")),
            "pct_calls_serviced":    pct_to_float(r.get("% Calls Serviced", "")),
            "successful_callbacks":  safe_int(r.get("Successful Callbacks")),
            "talk_time_total_seconds": dur_to_sec(r.get("Talk Time Total", "")),
            "talk_time_mean_seconds":  dur_to_sec(r.get("Talk Time Mean", "")),
        })
    if records:
        sb.table("detailed_queue_stats").upsert(
            records, on_conflict="queue_id,report_date"
        ).execute()
        log.info(f"  detailed_queue_stats: {len(records)} rows")


def ingest_queue_performance(sb, rows, report_date: str):
    records = []
    upsert_date(sb, report_date)
    for r in rows:
        q_id, q_name = norm_queue(r.get("Queue", ""))
        ext = r.get("Extension", "").strip()
        agent_id, agent_name = parse_agent(ext) if ext else (None, None)
        upsert_queue(sb, q_id, q_name)
        if agent_id:
            upsert_agent(sb, agent_id, agent_name)
        records.append({
            "queue_id":               q_id,
            "agent_id":               agent_id or None,
            "report_date":            report_date,
            "queue_received_calls":   safe_int(r.get("Queue Received Calls")),
            "queue_serviced_calls":   safe_int(r.get("Queue Serviced Calls")),
            "queue_unanswered_calls": safe_int(r.get("Queue Unanswered Calls")),
            "extension_serviced_calls": safe_int(r.get("Extension Serviced Calls")),
            "extension_polls":        safe_int(r.get("Extension Polls")),
            "talk_time_seconds":      dur_to_sec(r.get("Talk Time", "")),
            "avg_talk_time_seconds":  dur_to_sec(r.get("Average Talk Time", "")),
        })
    if records:
        sb.table("queue_performance").upsert(
            records, on_conflict="queue_id,agent_id,report_date"
        ).execute()
        log.info(f"  queue_performance: {len(records)} rows")


def ingest_queue_answered_calls(sb, rows, report_date: str):
    records = []
    for r in rows:
        q_id, q_name = norm_queue(r.get("Queue", ""))
        dest_raw = r.get("Destination", "").strip()
        dest_id, dest_name = parse_agent(dest_raw) if dest_raw else (None, None)
        upsert_queue(sb, q_id, q_name)
        if dest_id:
            upsert_agent(sb, dest_id, dest_name)
        call_time = r.get("Call Time", "").strip()
        d = call_time[:10] if len(call_time) >= 10 else report_date
        upsert_date(sb, d)
        records.append({
            "queue_id":            q_id,
            "call_time":           call_time or None,
            "destination_agent_id": dest_id or None,
            "caller_id":           r.get("Caller ID", "").strip() or None,
            "ringing_seconds":     dur_to_sec(r.get("Ringing", "")),
            "answer_time":         r.get("Answer Time", "").strip() or None,
            "sentiment":           r.get("Sentiment", "").strip() or None,
        })
    if records:
        sb.table("queue_answered_calls").upsert(records).execute()
        log.info(f"  queue_answered_calls: {len(records)} rows")


def ingest_extension_stats(sb, rows, report_date: str):
    records = []
    upsert_date(sb, report_date)
    for r in rows:
        agent_id, agent_name = parse_agent(r.get("Agent Extension", ""))
        upsert_agent(sb, agent_id, agent_name)
        records.append({
            "agent_id":            agent_id,
            "report_date":         report_date,
            "inbound_answered":    safe_int(r.get("Inbound Answered")),
            "inbound_unanswered":  safe_int(r.get("Inbound Unanswered")),
            "outbound_answered":   safe_int(r.get("Outbound Answered")),
            "outbound_unanswered": safe_int(r.get("Outbound Unanswered")),
            "total_answered":      safe_int(r.get("Total Answered")),
            "total_unanswered":    safe_int(r.get("Total Unanswered")),
            "total_talking_seconds": dur_to_sec(r.get("Total Talking Time", "")),
            "sentiment":           r.get("Sentiment", "").strip() or None,
        })
    if records:
        sb.table("extension_statistics").upsert(
            records, on_conflict="agent_id,report_date"
        ).execute()
        log.info(f"  extension_statistics: {len(records)} rows")


def ingest_user_activity(sb, rows, report_date: str):
    records = []
    for r in rows:
        ts = r.get("Time Scale", "").strip()
        d = ts[:10] if len(ts) >= 10 else report_date
        upsert_date(sb, d)
        records.append({
            "time_scale":      ts or None,
            "answered_calls":  safe_int(r.get("Answered Calls")),
            "unanswered_calls": safe_int(r.get("Unanswered Calls")),
        })
    if records:
        sb.table("user_activity").upsert(records, on_conflict="time_scale").execute()
        log.info(f"  user_activity: {len(records)} rows")


INGESTERS = {
    "call_reports":                     ingest_call_reports,
    "agent_login_history":              ingest_agent_login,
    "agents_in_queue_statistics":       ingest_agents_in_queue,
    "team_queue_general_statistics":    ingest_team_queue,
    "detailed_queue_statistics":        ingest_detailed_queue,
    "queue_performance":                ingest_queue_performance,
    "queue_answered_calls_by_wait_time": ingest_queue_answered_calls,
    "extension_statistics_by_group":    ingest_extension_stats,
    "user_activity":                    ingest_user_activity,
}


# ── main ───────────────────────────────────────────────────────────────────

def process_file(sb, path: Path):
    log.info(f"► {path.name}")
    report_date = date_from_filename(path)

    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        log.warning("  Empty file — skipped")
        return

    report_type = detect_type(path, list(rows[0].keys()))
    log.info(f"  type={report_type}  date={report_date}  rows={len(rows)}")

    fn = INGESTERS.get(report_type)
    if fn:
        fn(sb, rows, report_date)
    else:
        log.warning("  Unknown report type — skipped. Rename file to match expected pattern.")


def main():
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")

    if not url or not key:
        log.error("Missing SUPABASE_URL or SUPABASE_KEY environment variables.")
        sys.exit(1)

    sb = create_client(url, key)

    # Single file mode
    if len(sys.argv) > 1:
        files = [Path(sys.argv[1])]
    else:
        files = sorted(INCOMING_DIR.glob("*.csv"))

    if not files:
        log.info("No CSV files found.")
        return

    log.info(f"Processing {len(files)} file(s)")
    for path in files:
        try:
            process_file(sb, path)
        except Exception as e:
            log.error(f"  Failed: {e}")

    log.info("Done.")


if __name__ == "__main__":
    main()
