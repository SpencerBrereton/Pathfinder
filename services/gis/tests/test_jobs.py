import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

VALID_JOB = {
    "job_type": "geotiff",
    "input_files": ["s3://bucket/dem.tif"],
    "region_id": str(uuid.uuid4()),
}


def test_post_job_returns_201_with_job_id():
    response = client.post("/jobs", json=VALID_JOB)
    assert response.status_code == 201
    body = response.json()
    assert "job_id" in body
    uuid.UUID(body["job_id"])  # raises if not a valid UUID


def test_get_job_returns_pending_status():
    post = client.post("/jobs", json=VALID_JOB)
    job_id = post.json()["job_id"]

    response = client.get(f"/jobs/{job_id}")
    assert response.status_code == 200
    body = response.json()
    assert body["job_id"] == job_id
    assert body["status"] == "pending"
    assert body["progress"] == 0.0
    assert body["error_message"] is None


def test_get_job_unknown_id_returns_404():
    response = client.get(f"/jobs/{uuid.uuid4()}")
    assert response.status_code == 404


def test_post_job_invalid_job_type_returns_422():
    bad = {**VALID_JOB, "job_type": "satellite"}
    response = client.post("/jobs", json=bad)
    assert response.status_code == 422


def test_post_job_missing_fields_returns_422():
    response = client.post("/jobs", json={"job_type": "geotiff"})
    assert response.status_code == 422
