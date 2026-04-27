from __future__ import annotations
import threading
from datetime import datetime, timezone
from app.models import JobStatus
from app.job_store import JobStore

TIMEOUTS: dict[str, int] = {
    "geotiff": 30 * 60,
    "lidar": 60 * 60,
    "field_capture": 20 * 60,
}


def scan_once(store: JobStore) -> None:
    now = datetime.now(timezone.utc)
    for job in store.all():
        if job.status != JobStatus.processing:
            continue
        if job.started_at is None:
            continue
        limit = TIMEOUTS.get(job.job_type.value, 30 * 60)
        elapsed = (now - job.started_at).total_seconds()
        if elapsed > limit:
            job.status = JobStatus.failed
            job.error_message = "timeout"
            store.update(job)


def _loop(store: JobStore, interval: int) -> None:
    import time
    while True:
        time.sleep(interval)
        scan_once(store)


def start_watchdog(store: JobStore, interval: int = 5) -> threading.Thread:
    t = threading.Thread(target=_loop, args=(store, interval), daemon=True)
    t.start()
    return t
