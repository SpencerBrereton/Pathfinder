# Pathfinder Lab

Pathfinder Lab is the professional-grade field mapping application. Authorized users carry an iPhone Pro into the field and use its built-in LiDAR scanner combined with GPS to capture terrain data for trails and natural areas. This data enriches the terrain layer and is the foundation of Pathfinder's B2B commercial offering.

## Platform

- **Framework**: React Native + native Swift (iOS)
- **Primary target**: iPhone Pro (iPhone 12 Pro and later — LiDAR required)
- **Android**: Future consideration (LiDAR hardware is rare on Android)
- **Users**: Authorized only (see User Tiers below)

## Why iPhone Pro

Apple's iPhone Pro lineup has included a LiDAR Scanner since the iPhone 12 Pro (2020). It is the most accessible consumer LiDAR hardware available. The LiDAR Scanner is exposed via **ARKit** and **RealityKit**, which are native iOS frameworks — this is the primary reason Lab requires a native Swift layer.

## Data Quality Tiers

Pathfinder Lab supports two capture quality tiers:

| Tier | Hardware | Accuracy | Who uses it |
|---|---|---|---|
| **Community** | iPhone Pro LiDAR + iPhone GPS | 5–10m (GPS-limited) | Authorized mappers, community volunteers |
| **Authoritative** | Mosaic Xplor (or equiv.) + high-precision GPS | Sub-10cm | Org accounts with professional equipment, Pathfinder survey service |

Both tiers flow through the same processing pipeline in the GIS microservice. The `data_quality_tier` field on `field_captures` and the resulting `tile_sets` distinguishes them.

Community-tier captures are valuable for coverage and change detection. Authoritative-tier captures are the commercially sellable product. A cluster of community iPhone captures on a trail is a strong signal to prioritize a professional survey of that segment.

**Important accuracy caveat:** iPhone GPS under heavy tree cover is ±5–15m. ARKit drift also accumulates over longer capture sessions. Community-tier captures should not be represented as survey-grade data. Controlled accuracy testing against reference government LiDAR datasets is required before Phase 5 to establish real-world error bounds.

## User Tiers

Access to Pathfinder Lab is gated. A user gains access if **any** of the following apply:

| Tier | Who | Access Level | Publish Mode |
|---|---|---|---|
| **Authorized Mapper** | Vetted community volunteers | `profiles.role = 'authorized_mapper'` | After QA review |
| **Org Account** | Trail associations, park staff, paid clients | Member of any organization | Direct publish |
| **Platform Admin** | Pathfinder team | `profiles.role = 'platform_admin'` | Direct publish |

Authorized mapper access requires 100 verified discoveries in the Pathfinder app + platform admin approval. Progress is visible in-app with a progress bar and milestone badges.

## Core Workflow

```
User selects area / trail to map
       │
       ▼
App loads existing terrain context (for reference)
       │
       ▼
User walks the area with iPhone (or with Mosaic Xplor)
       │
       ▼
ARKit LiDAR scanner captures point cloud continuously
GPS records position track
       │
       ▼
Data stored locally (offline-first)
       │
       ▼
User completes session, reviews capture in-app
       │
       ▼
User tags the capture (area name, notes) and submits for upload
       │
       ▼
Syncs to Supabase when connected, tagged with data_quality_tier
       │
       ▼
Authorized mapper → QA review queue in Studio
Org account / Admin → direct publish
```

## LiDAR Capture (iPhone)

The native Swift layer uses **ARKit** (`ARWorldTrackingConfiguration` with scene depth) to capture:

- Dense point cloud from LiDAR sensor
- Mesh reconstruction (ARMeshAnchor)
- Camera pose per frame (for georeferencing)

GPS coordinates from **CoreLocation** are fused with the ARKit session to georeference the captured point cloud.

**Capture output per session:**
- Raw point cloud (.ply or .las)
- GPS track (.gpx)
- Session metadata (device, timestamp, area tag, user, capture method)

## Professional Capture Support (Mosaic Xplor)

For authoritative-tier captures, Studio supports direct upload of professional survey data:

- `.las` / `.laz` point cloud from Mosaic Xplor or equivalent
- `.gpx` GPS track (high-precision GPS)
- Session metadata including equipment model and operator

These uploads are tagged `data_quality_tier = 'authoritative'` and bypass the QA review queue for org accounts.

## Offline-First

Field conditions mean no cell service is the norm:

- All capture data stored locally in full
- Reference terrain tiles pre-downloaded before heading out
- Upload queue drains automatically when connectivity is restored
- Sessions can be reviewed and annotated offline before submission

## QA Review (Authorized Mappers)

Community mapper submissions enter a review workflow in Pathfinder Studio:

1. Submission appears in the admin QA queue
2. Admin reviews the point cloud against existing terrain data
3. Admin approves → data is merged into the terrain layer via the GIS pipeline
4. Admin rejects → contributor notified in-app with feedback

The QA review step protects data quality. For B2B clients, knowing submissions are validated before publication is part of the product's value.

## Tech Stack

| Layer | Technology |
|---|---|
| App framework | React Native (Expo bare workflow) |
| LiDAR / AR capture | ARKit + RealityKit (native Swift module) |
| GPS | CoreLocation (native Swift) |
| RN ↔ Swift bridge | React Native Native Modules |
| Map reference layer | MapLibre GL |
| Offline storage | SQLite + file system |
| Push notifications | Expo Notifications (APNs) |
| Auth | Supabase Auth |
| Data sync | Supabase REST + Storage |

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Data Pipeline]]
- [[User And Auth Model]]
