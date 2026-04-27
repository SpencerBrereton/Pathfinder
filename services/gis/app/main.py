from contextlib import asynccontextmanager
from datetime import datetime, timezone
from uuid import uuid4, UUID
from fastapi import FastAPI, HTTPException
from app.models import JobRequest, JobRecord, JobResponse, JobStatus
from app.job_store import store
from app.watchdog import start_watchdog


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_watchdog(store)
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/jobs", status_code=201)
def create_job(req: JobRequest):
    job = JobRecord(
        job_id=uuid4(),
        job_type=req.job_type,
        input_files=req.input_files,
        region_id=req.region_id,
        created_at=datetime.now(timezone.utc),
    )
    store.add(job)
    return {"job_id": str(job.job_id)}


@app.get("/jobs/{job_id}", response_model=JobResponse)
def get_job(job_id: UUID):
    job = store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    return JobResponse(
        job_id=job.job_id,
        status=job.status,
        progress=job.progress,
        error_message=job.error_message,
    )
