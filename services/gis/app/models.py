from __future__ import annotations
from enum import Enum
from uuid import UUID
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel


class JobType(str, Enum):
    geotiff = "geotiff"
    lidar = "lidar"
    field_capture = "field_capture"


class JobStatus(str, Enum):
    pending = "pending"
    processing = "processing"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"


class JobRequest(BaseModel):
    job_type: JobType
    input_files: List[str]
    region_id: UUID


class JobRecord(BaseModel):
    job_id: UUID
    job_type: JobType
    input_files: List[str]
    region_id: UUID
    status: JobStatus = JobStatus.pending
    progress: float = 0.0
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    created_at: datetime


class JobResponse(BaseModel):
    job_id: UUID
    status: JobStatus
    progress: float
    error_message: Optional[str]
