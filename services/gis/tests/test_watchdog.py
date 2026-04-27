"""
Watchdog tests call the scan function directly with a manipulated store
so we never have to sleep. The public contract: jobs stuck in `processing`
beyond their timeout become `failed`; all other states are untouched.
"""
from datetime import datetime, timezone, timedelta
from uuid import uuid4
from app.models import JobRecord, JobStatus, JobType
from app.job_store import JobStore
from app.watchdog import scan_once, TIMEOUTS


def _make_job(job_type: JobType, status: JobStatus, started_at=None) -> JobRecord:
    return JobRecord(
        job_id=uuid4(),
        job_type=job_type,
        input_files=[],
        region_id=uuid4(),
        status=status,
        created_at=datetime.now(timezone.utc),
        started_at=started_at,
    )


def test_watchdog_times_out_processing_job():
    s = JobStore()
    past = datetime.now(timezone.utc) - timedelta(seconds=TIMEOUTS["geotiff"] + 1)
    job = _make_job(JobType.geotiff, JobStatus.processing, started_at=past)
    s.add(job)

    scan_once(s)

    updated = s.get(job.job_id)
    assert updated.status == JobStatus.failed
    assert updated.error_message == "timeout"


def test_watchdog_ignores_pending_jobs():
    s = JobStore()
    job = _make_job(JobType.geotiff, JobStatus.pending)
    s.add(job)

    scan_once(s)

    assert s.get(job.job_id).status == JobStatus.pending


def test_watchdog_ignores_completed_jobs():
    s = JobStore()
    past = datetime.now(timezone.utc) - timedelta(seconds=TIMEOUTS["geotiff"] + 1)
    job = _make_job(JobType.geotiff, JobStatus.completed, started_at=past)
    s.add(job)

    scan_once(s)

    assert s.get(job.job_id).status == JobStatus.completed


def test_watchdog_ignores_failed_jobs():
    s = JobStore()
    past = datetime.now(timezone.utc) - timedelta(seconds=TIMEOUTS["geotiff"] + 1)
    job = _make_job(JobType.geotiff, JobStatus.failed, started_at=past)
    s.add(job)

    scan_once(s)

    assert s.get(job.job_id).status == JobStatus.failed


def test_watchdog_does_not_timeout_job_within_window():
    s = JobStore()
    recent = datetime.now(timezone.utc) - timedelta(seconds=10)
    job = _make_job(JobType.geotiff, JobStatus.processing, started_at=recent)
    s.add(job)

    scan_once(s)

    assert s.get(job.job_id).status == JobStatus.processing


def test_watchdog_uses_correct_timeout_per_job_type():
    """lidar gets 60 min; a job 31 min old should still be processing."""
    s = JobStore()
    past = datetime.now(timezone.utc) - timedelta(seconds=TIMEOUTS["geotiff"] + 1)
    job = _make_job(JobType.lidar, JobStatus.processing, started_at=past)
    s.add(job)

    scan_once(s)

    assert s.get(job.job_id).status == JobStatus.processing
