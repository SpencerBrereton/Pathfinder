FROM python:3.11-slim

WORKDIR /app

# --- placeholder for geospatial system deps (Phase 1.3 skeleton — not installed yet) ---
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     gdal-bin libgdal-dev libpdal-dev \
#  && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .

# Install runtime deps only (no dev extras in image)
RUN pip install --no-cache-dir "fastapi>=0.115" "uvicorn[standard]>=0.30" "pydantic>=2.0"

COPY app/ app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
