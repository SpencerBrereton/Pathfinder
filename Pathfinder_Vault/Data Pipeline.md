# Data Pipeline

The Pathfinder data pipeline describes how raw geographic source files (GeoTIFF, LiDAR) are transformed into map tiles served to mobile apps, and how community data flows back from mobile clients into the platform.

## Two Data Streams

| Stream | Source | Destination | Quality Gate |
|---|---|---|---|
| **Authoritative Terrain** | Pathfinder Studio (admin import) + Pathfinder Lab (field capture) | PostGIS + Supabase Storage / CDN | Admin approval required |
| **Community Discoveries** | Pathfinder mobile game | PostGIS | Automated moderation + manual queue |

---

## Stream 1: Authoritative Terrain

### Data Quality Tiers

All terrain data is tagged with one of two quality tiers:

| Tier | Source | Accuracy | `data_quality_tier` value |
|---|---|---|---|
| **Community** | iPhone Pro LiDAR via Pathfinder Lab | 5–10m (GPS-limited) | `community` |
| **Authoritative** | Mosaic Xplor, drone photogrammetry, government LiDAR | Sub-10cm | `authoritative` |

Both tiers flow through the same processing pipeline. Community-tier data fills coverage gaps and serves as a signal for where authoritative surveys are most needed. Authoritative-tier data is the commercially sellable product layer.

### Input Formats

- **GeoTIFF** (`.tif`, `.tiff`) — elevation models (DEM/DTM), satellite imagery, multispectral rasters
- **LiDAR** (`.las`, `.laz`) — point cloud data from airborne or professional ground sensors
- **Field Captures** — point clouds from Pathfinder Lab (ARKit LiDAR + GPS track, or Mosaic Xplor + GPS)

### Processing: Python GIS Microservice

Raw files are processed by the Python GIS microservice. Pathfinder Studio submits jobs; progress is pushed to Studio via Supabase Realtime.

#### GeoTIFF → Elevation Tiles

```
GeoTIFF (elevation DEM)
       │
       ▼  GDAL / rasterio
Reproject to EPSG:3857 (Web Mercator)
       │
       ▼  rio-cogeo / rio-tiler
Generate RGB-encoded elevation tiles
(Mapbox Terrain RGB: elevation = -10000 + ((R*65536 + G*256 + B) * 0.1))
       │
       ▼
Output: PMTiles (production) or MBTiles (offline packages)
```

#### LiDAR → Vector + Point Cloud Tiles

```
LiDAR (.las / .laz)
       │
       ▼  pdal
Filter noise, classify ground points
       │
       ▼  pdal + GDAL
Extract vector features (cliff edges, water bodies, structures)
       │
       ▼  tippecanoe
Generate vector tiles (PMTiles)
       │
       ▼  Potree / entwine
Generate web-optimized point cloud (for Studio viewer)
```

#### Field Captures (Pathfinder Lab)

```
ARKit point cloud (.ply) + GPS track (.gpx)        [community tier]
  OR
Mosaic Xplor point cloud (.las) + GPS track (.gpx)  [authoritative tier]
       │
       ▼  pdal
Georeference point cloud using GPS track
       │
       ▼
Merge into existing terrain dataset for the region
       │
       ▼
Re-tile affected area (affected zoom levels only)
       │
       ▼
Output tile set tagged with appropriate data_quality_tier
```

### Storage

- **Supabase Storage** — tile packages (PMTiles / MBTiles), raw source files, GPX tracks, photos
- **PostGIS** — region boundaries, tile set metadata, feature geometries, discovery points
- **Cloudflare R2 + CDN** (Phase 5+) — published PMTiles files, served globally at edge

### Publication

Admins review output in Pathfinder Studio (CesiumJS viewer) before publishing. Approved tile sets are flagged `published = true` and their `cdn_url` is set. Mobile apps use the CDN URL for published tile sets and fall back to Supabase Storage in development.

---

## Stream 2: Community Discoveries

```
Player submits photo in Pathfinder app
       │
       ▼  AI species identification (on-device or API)
Suggested species + confidence score shown to player
Player confirms, corrects, or enters manual text
       │
       ▼  stored locally (moderation_status = 'pending')
Placeholder dot appears on map immediately
       │
       ▼  on reconnect
Sync to Supabase via REST API
       │
       ▼  automated moderation (Edge Function or external API)
Text moderation (inappropriate content)
Image-description mismatch detection (vision model)
       │
       ├─ fails → moderation_status = 'flagged' → enters manual review queue
       │               │
       │          ├─ admin approves → moderation_status = 'approved'
       │          └─ admin removes  → moderation_status = 'removed'
       │                              → contributor notified
       │
       └─ passes → moderation_status = 'approved'
                       │
                       ▼  canonical asset lookup
              Does asset exist for identified_species?
                       │
              ├─ yes → place existing asset at discovery location
              │
              └─ no  → queue Meshy generation job
                            │
                            ▼  async (seconds to minutes)
                       Asset generated → stored in canonical_assets
                            │
                            ▼
                       Asset placed at discovery location on map
                       In-app notification sent to contributor
```

Discovery data is append-only — no conflicts. Each discovery is an immutable record attributed to its contributor under CC BY.

### Discovery Decay

Active discoveries decay over time at category-specific rates. When `decays_at` passes, the discovery is removed from the active map. Re-verification resets the `decays_at` clock. Anchored discoveries (Pro feature) resist decay.

A background job periodically scans for discoveries where `decays_at < now()` and marks them inactive. Regional completion percentages are recalculated accordingly.

### Discovery Verification

When a user is within proximity of an approved public discovery, the app prompts them to confirm it. Confirmations are recorded in `discovery_verifications` (one per user per discovery). The `verification_count` on the discovery increments accordingly.

Verified discoveries carry more weight as data quality signals. A user's `verified_discovery_count` counts toward the 100-discovery threshold for Pathfinder Lab access.

---

## Tile Serving

### Development (Phase 1–4)

Mobile apps request tiles directly from Supabase Storage using HTTP range requests against PMTiles files:

```
https://<supabase>/storage/v1/object/public/tiles/{region_id}/{tile_set_id}.pmtiles
```

### Production (Phase 5+)

Published tile sets are served from Cloudflare CDN via their `cdn_url`:

```
https://tiles.pathfinder.app/{region_slug}/{tile_set_id}/{z}/{x}/{y}
```

The tile URL structure is stable. The domain resolves to Supabase Storage in development and Cloudflare CDN in production — no client code changes required at migration.

### Offline Packages

For offline use, mobile apps download a region's full tile package as **MBTiles** and serve tiles locally via a bundled tile server. MBTiles is retained only for this purpose; PMTiles is the format for all cloud-served tiles.

---

## Coordinate Reference Systems

| Context | CRS |
|---|---|
| Source data (government GeoTIFF) | Varies — EPSG:4326, NAD83, etc. |
| Processing intermediate | EPSG:4326 (WGS84) |
| Tile output | EPSG:3857 (Web Mercator) |
| PostGIS storage | EPSG:4326 |
| GPS (mobile) | EPSG:4326 |

All source data is reprojected to Web Mercator during tile generation.

---

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Pathfinder Studio]]
- [[Pathfinder Lab]]
- [[Pathfinder]]
