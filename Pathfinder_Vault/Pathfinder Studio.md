# Pathfinder Studio

Pathfinder Studio is the desktop administration tool for the Pathfinder platform. It is the entry point for all geographic data — admins import raw map files here, trigger processing, and visually validate the output before it becomes available to mobile users.

## Platform

- **Framework**: Electron (Chromium + Node.js)
- **OS Support**: Windows, macOS
- **Users**: Platform admins only (not public-facing)

## Core Responsibilities

1. **Import geographic data** — accept GeoTIFF and LiDAR (.las / .laz) files from local disk or directory
2. **Trigger GIS processing** — send files to the Python GIS microservice for tile generation
3. **Validate output** — visualize processed terrain in the CesiumJS 3D viewer to confirm accuracy and coverage
4. **Publish to backend** — push approved tile sets and metadata to Supabase for mobile consumption
5. **Manage regions** — create, name, and tag geographic regions (e.g. "Banff National Park")

## 3D Terrain Viewer

Studio uses **CesiumJS** for terrain visualization, running inside the Electron webview.

CesiumJS provides:
- Interactive 3D globe / terrain flythrough
- Elevation layer rendering from processed raster tiles
- LiDAR point cloud overlay
- Layer toggling (hillshade, contours, satellite imagery)
- Camera controls (orbit, fly-to, zoom)

The viewer is a **QA tool**, not a public product. The goal is: "does this import look correct and cover the right area?" Photorealistic rendering is out of scope.

## Import Workflow

```
Admin selects files
       │
       ▼
Studio sends to Python GIS microservice
       │
       ▼
Microservice returns tile set (elevation raster + vector)
       │
       ▼
Studio renders tiles in CesiumJS viewer
       │
       ▼
Admin reviews → approves
       │
       ▼
Studio uploads tiles + metadata to Supabase
       │
       ▼
Tiles available to Pathfinder + Pathfinder Lab
```

## Supported Input Formats

| Format | Type | Notes |
|---|---|---|
| `.tif` / `.tiff` | Raster (GeoTIFF) | Elevation, imagery, multispectral |
| `.las` / `.laz` | LiDAR point cloud | Compressed LiDAR preferred |

Future formats (post-MVP): GeoJSON, Shapefile, DEM, XYZ grids.

## Tech Stack

| Layer | Technology |
|---|---|
| Desktop shell | Electron |
| UI | React + TypeScript |
| 3D viewer | CesiumJS (WebGL) |
| File I/O | Node.js (Electron main process) |
| GIS processing | Python microservice (internal HTTP API) |
| Backend sync | Supabase JS client |

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Data Pipeline]]
