from __future__ import annotations
from threading import Lock
from typing import Dict, Optional
from uuid import UUID
from app.models import JobRecord


class JobStore:
    def __init__(self) -> None:
        self._jobs: Dict[UUID, JobRecord] = {}
        self._lock = Lock()

    def add(self, job: JobRecord) -> None:
        with self._lock:
            self._jobs[job.job_id] = job

    def get(self, job_id: UUID) -> Optional[JobRecord]:
        with self._lock:
            return self._jobs.get(job_id)

    def update(self, job: JobRecord) -> None:
        with self._lock:
            self._jobs[job.job_id] = job

    def all(self) -> list[JobRecord]:
        with self._lock:
            return list(self._jobs.values())


store = JobStore()
