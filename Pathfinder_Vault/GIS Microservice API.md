# GIS Microservice API

The Python GIS microservice processes raw geographic files (GeoTIFF, LiDAR) into map tiles. It exposes an HTTP API consumed exclusively by **Pathfinder Studio** (internal, not public-facing). It runs on `http://localhost:8000` in local dev.

---

## Design Principles

- **Async job model**: Processing large files takes seconds to minutes. All processing endpoints return a job ID immediately; progress is pushed to Studio via Supabase Realtime rather than polling.
- **Internal only**: No auth required — the service is not exposed outside the local network. Studio communicates with it directly over localhost (or Docker network). When deployed to cloud, this must be secured with a shared secret or mTLS before exposure.
- **Idempotent**: Submitting the same source file twice produces the same output and does not create duplicate jobs.
- **Timeout + retry**: Jobs that exceed their type-specific timeout are automatically marked `failed`. Studio surfaces a retry button for failed jobs without requiring the source file to be re-uploaded.

### Job Timeouts

| Job Type | Timeout |
|---|---|
| `geotiff` | 30 minutes |
| `lidar` | 60 minutes |
| `field_capture` | 20 minutes |

A watchdog process monitors `import_jobs` for records where `status = 'processing'` and `started_at` exceeds the timeout threshold, then sets `status = 'failed'` with an appropriate error message.

---

## Base URL

```
http://localhost:8000
```

---

## Endpoints

### `GET /health`

Liveness check.

**Response `200`**
```json
{ "status": "ok", "version": "0.1.0" }
```

---

### `POST /jobs`

Submit a processing job. Studio uploads source files to Supabase Storage first, then calls this endpoint with the storage paths. The service downloads the files, processes them, and uploads the output tile set back to Supabase Storage.

**Request body**
```json
{
  "region_id": "uuid",
  "job_type": "geotiff" | "lidar" | "field_capture",
  "data_quality_tier": "community" | "authoritative",
  "input_files": [
    {
      "storage_path": "raw/banff/elevation.tif",
      "format": "geotiff" | "las" | "laz" | "ply" | "gpx"
    }
  ],
  "options": {
    "zoom_min": 0,
    "zoom_max": 14,
    "output_format": "pmtiles" | "mbtiles",
    "output_crs": "EPSG:3857"
  }
}
```

**`job_type` values**

| Value | Input | Output |
|---|---|---|
| `geotiff` | GeoTIFF elevation raster | RGB elevation tiles (PMTiles/MBTiles) |
| `lidar` | LAS/LAZ point cloud | Vector feature tiles + web point cloud |
| `field_capture` | PLY point cloud + GPX track | Georeferenced point cloud, merged into existing terrain |

**Response `202 Accepted`**
```json
{
  "job_id": "uuid",
  "status": "pending",
  "created_at": "2026-04-27T12:00:00Z"
}
```

**Response `409 Conflict`** — if an identical job (same region + same input file hashes) is already in progress
```json
{
  "error": "duplicate_job",
  "existing_job_id": "uuid"
}
```

---

### `GET /jobs/{job_id}`

Poll for job status and results.

**Response `200`**
```json
{
  "job_id": "uuid",
  "region_id": "uuid",
  "status": "pending" | "processing" | "completed" | "failed",
  "progress": 0.72,
  "output": {
    "tile_set_id": "uuid",
    "storage_path": "tiles/banff/elevation.pmtiles",
    "tile_type": "elevation_raster",
    "zoom_min": 0,
    "zoom_max": 14,
    "bounds": [-116.5, 50.9, -114.5, 51.9]
  },
  "error": null,
  "started_at": "2026-04-27T12:00:05Z",
  "completed_at": "2026-04-27T12:01:43Z"
}
```

`output` is `null` while status is `pending` or `processing`.
`error` is a string message when status is `failed`.
`progress` is a float 0–1, updated during processing.

---

### `GET /jobs`

List recent jobs. Used by Studio to display job history.

**Query parameters**

| Param | Type | Default | Description |
|---|---|---|---|
| `region_id` | uuid | — | Filter by region |
| `status` | string | — | Filter by status |
| `limit` | int | 20 | Max results |
| `offset` | int | 0 | Pagination |

**Response `200`**
```json
{
  "jobs": [ /* array of job objects (same shape as GET /jobs/{id}) */ ],
  "total": 42
}
```

---

### `DELETE /jobs/{job_id}`

Cancel a pending or processing job. No-op if already completed or failed.

**Response `200`**
```json
{ "cancelled": true }
```

---

## Processing Pipeline Detail

### GeoTIFF → Elevation Tiles

```
1. Download input file(s) from Supabase Storage
2. Validate CRS; reproject to EPSG:4326 if needed (GDAL)
3. Merge multiple files if >1 input (gdal_merge)
4. Generate RGB-encoded elevation tiles (rio-tiler / rio-cogeo)
   - Elevation (m) = -10000 + ((R*65536 + G*256 + B) * 0.1)
5. Package as PMTiles (or MBTiles)
6. Upload output to Supabase Storage: tiles/{region_id}/elevation_{job_id}.pmtiles
7. Write tile_sets record to Supabase DB via service key
8. Update import_jobs record: status=completed, output_tile_set_id=...
```

### LiDAR → Vector Tiles + Point Cloud

```
1. Download .las / .laz from Supabase Storage
2. Filter noise points, classify ground returns (pdal)
3. Extract vector features:
   - Cliff edges (breaklines from steep slope analysis)
   - Water bodies (from classification + DEM)
   - Structures (buildings, bridges)
4. Generate vector tiles from features (tippecanoe → PMTiles)
5. Generate web-optimized point cloud viewer format (Potree/entwine) — Studio only
6. Upload all outputs to Supabase Storage
7. Write tile_sets records (one per output type)
```

### Field Capture (Pathfinder Lab)

```
1. Download .ply (point cloud) + .gpx (GPS track) from Supabase Storage
2. Parse GPS track timestamps + coordinates (gpxpy)
3. Georeference point cloud: align ARKit local coordinates to GPS world coordinates (pdal)
4. Transform to EPSG:4326
5. Merge with existing terrain tile set for the region (if one exists)
6. Re-tile affected zoom levels
7. Upload updated tile set
8. Update field_captures record: status=approved (triggered by admin in Studio)
```

---

## Error Handling

The service writes error details to the `import_jobs.error_message` column and sets `status = 'failed'`. Studio polls for this and surfaces the message to the admin.

Common failure modes:

| Error | Cause | Resolution |
|---|---|---|
| `invalid_crs` | Source file has unknown/unsupported CRS | Admin re-exports with explicit CRS set |
| `corrupt_file` | File is truncated or malformed | Re-download source file |
| `out_of_bounds` | Geometry falls outside expected region boundary | Check source data coverage |
| `merge_conflict` | Field capture overlaps incompatibly with existing terrain | Admin resolves manually via Studio |

---

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Monorepo And Tooling]]
- [[Data Pipeline]]
- [[Pathfinder Studio]]
