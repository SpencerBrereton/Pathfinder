# Build Roadmap

The platform is built in phases, ordered so each phase produces working, testable software and the next phase has a solid foundation to build on. The data pipeline is central — everything depends on it working before building the applications that consume it.

## Phase 1 — Backend Foundation

**Goal**: A working local backend that all future components will connect to.

**Deliverables:**
- Supabase running locally via Docker (`docker-compose up`)
- PostgreSQL + PostGIS schema: regions, tile sets, users/profiles, discoveries, gamification tables, notifications, hike tracks
- Supabase Auth configured (email/password, Google OAuth, Apple Sign-In)
- Row-Level Security policies for all user tiers (platform role + org membership model)
- Python GIS microservice skeleton (HTTP API, GDAL/rasterio/pdal installed, Docker container)
- Monorepo scaffolding: `packages/`, `services/gis/`, shared TypeScript types
- **CI/CD**: GitHub Actions pipeline (lint, TypeScript type-check, migration validation) on every PR

**Definition of done**: `supabase start` + `docker-compose up gis` brings up a fully functional local stack with passing smoke tests and a green CI pipeline.

---

## Phase 2 — Pathfinder Studio

**Goal**: An admin can import real GeoTIFF files, process them, and see a 3D terrain model.

**Deliverables:**
- Electron app scaffolded (React + TypeScript + CesiumJS)
- File import UI (drag-and-drop GeoTIFF / LiDAR)
- GIS microservice integration: submit files, receive progress via Supabase Realtime (no polling)
- Job timeout enforcement: GeoTIFF (30 min), LiDAR (60 min), Field capture (20 min)
- Retry button for failed jobs
- Tile generation pipeline: GeoTIFF → RGB elevation tiles → PMTiles
- CesiumJS viewer: renders processed terrain tiles
- Supabase integration: upload tiles to Storage, write metadata to PostGIS
- Region management: create, name, tag, publish/unpublish regions

**Definition of done**: Import a Banff National Park GeoTIFF, process it, see the terrain in the CesiumJS viewer, publish it to the local backend. A failed job can be retried without re-uploading the source file.

---

## Phase 3 — Pathfinder (Mobile Game)

**Goal**: A player can load a published region, walk around, log a discovery that syncs and gets verified, and see their progress toward Pathfinder Lab access.

**Deliverables:**
- React Native app scaffolded (iOS + Android, Expo)
- Auth flow (sign up, log in, sign in with Google / Apple)
- Customizable player character on 2.5D terrain map
- MapLibre GL integration: render terrain tiles in 2.5D
- GPS location tracking: user position on map
- Offline tile download: select a region, download tiles for offline use (1 region cap for free users)
- Tile freshness indicator: "out of date" badge on cached tiles when newer version is published
- Map data quality indicator: community-tier vs. authoritative-tier coverage overlay + onboarding disclaimer
- Discovery logging: AI species identification (suggest + confirm/override), photo, GPS, notes — stored locally in SQLite
- Placeholder dot on map immediately on submission; canonical 3D asset placed on approval + asset generation
- Canonical asset library: Meshy generation job queue; reuse existing assets per species
- Discovery decay: category-aware decay rates; decayed discoveries removed from active map
- Category-aware verification: structured questions for trail conditions, photo re-submission for flora/fauna, proximity confirm for landmarks
- Regional completion percentage: weighted aggregate of active discoveries + terrain coverage; mechanical unlock thresholds
- Content moderation pipeline: automated text + vision model review on sync; manual queue for flagged items; notification to contributor on removal
- Sync engine: upload discoveries and verifications to Supabase when connected
- Gamification: XP, levels, badges, streak tracking, Lab access progress bar, regional milestone badges
- Field Journal: personal history of discoveries organized by date, region, category
- Community map layer: approved public discoveries from other users
- Friend lists + friends' discovery highlighting on map
- Notification preferences: per-event-type push vs in-app toggle (in-app only in this phase)
- **Rate limiting**: per-user discovery submission rate limit (e.g. max 20/hour) enforced at API layer — ships with Phase 3, not deferred
- **GDPR deletion flow**: "delete my account" button triggering manual deletion process within 30 days — ships with Phase 3 public launch
- **Pro tier UI**: upgrade prompts at feature gates

**Definition of done**: App runs on a real iPhone and Android device; user logs a discovery while offline, reconnects, discovery passes moderation, canonical 3D asset is placed in the world and player is notified; a second user walking past receives a category-appropriate verification prompt and confirms the discovery; regional completion percentage updates accordingly.

---

## Phase 4 — Pathfinder Lab + Notifications

**Goal**: An authorized mapper can do a field capture and submit it for QA review. Pro features are fully live. Push notifications are working.

**Deliverables:**
- React Native app scaffolded (iOS-first, Expo bare workflow)
- Auth flow + authorization gate (Lab access check: `authorized_mapper` role or org membership)
- Native Swift module: ARKit LiDAR capture (point cloud + camera poses)
- CoreLocation GPS track recording
- Point cloud + GPS track stored locally
- Capture session review UI (preview point cloud before submit)
- Upload + submission flow: sync to Supabase Storage with `data_quality_tier = 'community'`
- QA queue in Pathfinder Studio: admin reviews, approves, or rejects submissions
- GIS pipeline extension: merge approved Lab captures into existing terrain
- **Pathfinder Pro features**: hike track recording (GPX), Field Journal stats dashboard, enhanced map layers, multi-device sync, unlimited offline regions
- **Push notifications** (Expo Notifications / APNs + FCM): submission approved/rejected, Lab access granted, discovery verification requests, user-configurable per event type
- **Professional capture support**: Mosaic Xplor / external LiDAR upload path in Studio with `data_quality_tier = 'authoritative'`

**Definition of done**: An authorized mapper captures a trail segment with iPhone Pro LiDAR, submits it, admin reviews and approves in Studio, updated terrain tiles publish and appear in the Pathfinder app. A Pro user records a full hike track, views their stats dashboard, and exports their journal as GPX.

---

## Phase 5 — Cloud Migration + Commercial Launch

**Goal**: Move off local Docker, launch publicly, onboard first paying B2B clients (trail associations and regional park authorities).

**Deliverables:**
- Migrate Supabase to cloud (Supabase Cloud or self-hosted VPS)
- **CDN migration**: publish PMTiles to Cloudflare R2; mobile apps switch to `cdn_url` for tile requests
- CI/CD pipelines extended: automated deployment for all components
- Electron auto-update mechanism (Studio)
- App Store + Play Store submissions (Pathfinder game)
- App Store submission (Pathfinder Lab — internal/TestFlight initially)
- **Org account management UI**: platform admin creates org, assigns plan tier, invites members
- **Stripe integration**: subscription billing for Pro and org accounts; webhooks update `profiles.is_pro`, `organizations.billing_status`, `organizations.stripe_subscription_id`
- Discovery analytics dashboard for org accounts (visitor traffic heatmaps, species sightings by trail, trail condition trends by region — only surfaced once regional coverage exceeds a meaningful threshold)
- **Lightweight web dashboard**: for org accounts to view analytics and manage their account; built after first B2B client is closed, not speculatively
- First paying B2B client: validate ICP assumptions with real trail association or park authority before building further B2B infrastructure
- **Survey service**: post-Phase 5 operational consideration — platform supports professional survey data upload; Pathfinder acting as the surveyor is deferred until B2B demand justifies it

---

## Tech Debt to Address Before Phase 5

- Performance testing of tile pipeline with large datasets (full national park scale)
- Pathfinder Studio: LiDAR (.las/.laz) import support (Phase 2 may be GeoTIFF-only MVP)
- Pathfinder Lab: Android LiDAR support assessment
- ARKit accuracy validation: controlled test comparing iPhone LiDAR captures against a reference government LiDAR dataset to establish real-world error bounds before selling community-tier data
- GDPR automated flow: Phase 3 ships a manual deletion process; automated right-to-deletion, data export, and consent tracking must be production-ready before Phase 5 public scale
- Moderation pipeline scaling: assess automated moderation accuracy and tune thresholds before public launch
- GIS microservice security: secure with shared secret or mTLS before cloud deployment (currently internal-only, no auth)
- Mapper trust tier system: implement `mapper_trust_level` graduation thresholds before QA queue becomes a bottleneck
- Source data licensing audit: verify commercial use rights for all government LiDAR/GeoTIFF datasets used as source material; add `source_license` provenance field to `tile_sets` before any B2B transaction
- B2B ICP validation: conduct real conversations with trail associations and park authorities to validate pricing unit, willingness to pay, and feature priorities before Phase 5 B2B build-out

---

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Pathfinder Studio]]
- [[Pathfinder]]
- [[Pathfinder Lab]]
- [[Data Pipeline]]
- [[User And Auth Model]]
