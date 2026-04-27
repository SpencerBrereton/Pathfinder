# Architecture

Pathfinder is an integrated platform with a shared backend serving three client applications. All components share a single data model, user account system, and API.

## Overview

```
┌─────────────────────────────────────────────────────┐
│                   Shared Backend                    │
│         Supabase (PostgreSQL + PostGIS)             │
│         REST + Realtime API                         │
│         Supabase Auth                               │
└──────────┬──────────────────┬───────────────────────┘
           │                  │                  │
    ┌──────▼──────┐   ┌───────▼──────┐   ┌──────▼──────┐
    │  Pathfinder │   │  Pathfinder  │   │  Pathfinder │
    │   Studio    │   │  (Mobile)    │   │    Lab      │
    │  (Electron) │   │(React Native)│   │(RN + Swift) │
    └─────────────┘   └──────────────┘   └─────────────┘
           │
    ┌──────▼──────┐
    │  Python GIS │
    │ Microservice│
    │ (GDAL/pdal) │
    └──────┬──────┘
           │
    ┌──────▼──────┐
    │  CDN Layer  │
    │ (Cloudflare │
    │  R2 + CDN)  │
    └─────────────┘
           │ (tile requests — mobile apps)
```

## Backend: Supabase

[Supabase](https://supabase.com) is the backend foundation. It bundles:

- **PostgreSQL + PostGIS** — geospatial data storage and spatial queries
- **Auth** — email/password, Google OAuth, Apple Sign-In
- **REST & Realtime API** — auto-generated from the database schema
- **Storage** — raw file storage for GeoTIFF, LiDAR, photos, GPX tracks

### Local Development

The backend runs locally via Docker during development:

```bash
supabase start   # spins up local Supabase stack
```

All services are containerized so the eventual migration to a cloud host is a configuration change, not a rewrite.

### Cloud Migration Path

1. Export local Supabase project
2. Push schema + data to Supabase Cloud (or self-hosted instance)
3. Update environment variables in all clients
4. No application code changes required

## Tile Freshness

When online, mobile apps always serve live tiles from the CDN — players see the current world state in real time. Downloaded offline tiles are served from the local MBTiles cache when disconnected.

On reconnect, the app compares cached tile set versions against the server. Stale cached tiles are marked **"out of date"** with a visible in-app indicator. Terrain elevation tiles used for navigation show a prominent warning; discovery overlay tiles show a subtle badge.

No client code changes are required at the development-to-production CDN migration — the tile URL structure is stable and the domain resolves differently per environment.

## Tile Serving Architecture

Tile serving is designed for two phases:

### Phase 1–4 (Development): Supabase Storage

During development and early testing, tiles are served directly from Supabase Storage. This is simple and sufficient for low traffic.

```
Mobile app → Supabase Storage (PMTiles file) → HTTP range request → tile bytes
```

### Phase 5+ (Production): CDN Layer

Before commercial launch, a CDN layer is introduced in front of tile assets. PMTiles is the chosen format for production serving because it supports HTTP range requests — a single PMTiles file per region can be served from a CDN with no tile server process required.

```
Mobile app → Cloudflare CDN → Cloudflare R2 (PMTiles file) → tile bytes (cached at edge)
```

**Implementation:**
- Processed PMTiles files are uploaded to Cloudflare R2 (S3-compatible)
- Cloudflare CDN serves tile requests with global edge caching
- `tile_sets.cdn_url` stores the public CDN URL for each published tile set
- Mobile apps use `cdn_url` when available, falling back to `storage_path` in development

**Tile URL structure (stable from day one):**
```
https://tiles.pathfinder.app/{region_slug}/{tile_set_id}/{z}/{x}/{y}
```

This URL structure is stable across both phases. In Phase 1–4 the domain resolves to Supabase Storage; in Phase 5 it resolves to the Cloudflare CDN. No client code changes required at migration.

**MBTiles** is retained as the format for offline packages only — mobile apps download a region's full MBTiles file for offline use, served locally via a bundled tile server.

## Python GIS Microservice

Heavy geospatial processing is handled by a separate Python service.

**Responsibilities:**
- Ingest GeoTIFF files → generate RGB-encoded elevation raster tiles
- Ingest LiDAR (.las / .laz) files → generate point clouds + vector feature tiles
- Process field captures (PLY + GPX) → georeference, merge into existing terrain

**Communication:** The microservice exposes an internal HTTP API. Pathfinder Studio calls it when an admin triggers an import job.

**Job reliability:**
- All jobs have type-specific timeouts enforced by a watchdog: GeoTIFF (30 min), LiDAR (60 min), Field capture (20 min)
- Jobs stuck in `processing` beyond timeout are automatically marked `failed`
- Failed jobs can be retried from Studio with a single click
- Progress updates are pushed via Supabase Realtime so Studio does not need to poll

**Key libraries:**
- `GDAL` — raster/vector format conversion
- `rasterio` — raster processing
- `pdal` — LiDAR point cloud processing
- `rio-cogeo` / `rio-tiler` — cloud-optimized GeoTIFF + tile generation

## Data Quality Tiers

The platform maintains two terrain data quality tiers that coexist in the same pipeline:

| Tier | Source | Accuracy | Notes |
|---|---|---|---|
| **Community** | iPhone Pro LiDAR (Pathfinder Lab) | 5–10m (GPS-limited) | Useful for coverage, feature ID, change detection |
| **Authoritative** | Professional equipment (Mosaic Xplor, drone, government LiDAR) | Sub-10cm | The sellable B2B product layer |

Both tiers flow through the same GIS microservice. `tile_sets.data_quality_tier` and `field_captures.data_quality_tier` distinguish them in the database. Mobile apps can render both tiers simultaneously — community data fills coverage gaps where authoritative data doesn't yet exist.

Community captures are valuable as a signal for where to prioritize professional surveys. A dense cluster of community iPhone captures on a trail segment is a strong indicator that a professional Mosaic Xplor survey of that segment would be commercially useful.

## Monorepo Structure

```
pathfinder/
├── packages/
│   ├── backend/          # Supabase config, migrations, edge functions
│   ├── studio/           # Electron desktop app
│   ├── mobile/           # React Native app (Pathfinder game)
│   ├── lab/              # React Native app (Pathfinder Lab)
│   └── shared/           # Shared TypeScript types, validation, utilities
├── services/
│   └── gis/              # Python GIS microservice
├── docker-compose.yml    # Local dev: Supabase + GIS service
└── package.json          # Monorepo root (pnpm workspaces)
```

## Data Flow Summary

1. Admin imports GeoTIFF/LiDAR in **Pathfinder Studio**
2. Studio calls the **Python GIS microservice** to process files into PMTiles
3. Tiles and metadata are stored in **Supabase** (PostGIS + Storage)
4. On Phase 5 launch, published tiles are mirrored to **Cloudflare R2** and served via CDN
5. **Pathfinder** and **Pathfinder Lab** fetch tiles from the CDN (or Supabase Storage in dev) and cache locally for offline use
6. Community discoveries, hike tracks, and field captures sync back to Supabase when connected

## Related

- [[Pathfinder Overview]]
- [[Data Pipeline]]
- [[Pathfinder Studio]]
- [[Pathfinder]]
- [[Pathfinder Lab]]
