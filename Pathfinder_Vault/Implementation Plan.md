# Implementation Plan

This document translates each phase of the [[Build Roadmap]] into a concrete build order. Work is organized into **vertical slices** — each slice delivers end-to-end working behavior, not a layer. Within each slice, modules are designed to be **deep**: small public interfaces that hide complex implementations.

Two structural principles run through every phase:

- **Tracer bullet first.** Each slice starts with a single test that proves the full path works. Implementation expands from there, one behavior at a time.
- **Seam discipline.** Ports are only introduced where two adapters are justified (production + test). A seam with one adapter is just indirection.

---

## Phase 1 — Backend Foundation

**Goal of the phase**: `supabase start` + `docker-compose up gis` brings up a fully functional local stack with passing smoke tests and a green CI pipeline.

### Vertical Slices

#### Slice 1.1 — Schema + RLS

**Tracer bullet**: A SQL smoke test connects to the local Supabase instance, creates a `community`-role user, and confirms that `SELECT` on `regions` only returns `published = true` rows.

**Build order**:
1. Write the initial Supabase migration — all enums, then tables, then indexes in dependency order (`auth.users` → `profiles` → `organizations` → … → `discoveries`)
2. Write the `profiles` auto-create trigger (fires on `auth.users` insert)
3. Write RLS policies table by table, each with a corresponding smoke test assertion
4. Seed badge definitions

**Deep module — `packages/backend/`**:
Interface: `supabase db push` applies all migrations idempotently; `supabase db reset` returns to clean state.
Implementation hides: migration ordering, enum-before-table dependency resolution, trigger body, RLS policy SQL. Callers (Studio, mobile) only see typed PostgREST responses — they never write raw SQL.

---

#### Slice 1.2 — Auth + Profile Creation

**Tracer bullet**: Sign up via `supabase.auth.signUp(email, password)` → a `profiles` row exists with `role = 'community'`.

**Build order**:
1. Enable email/password auth in Supabase config
2. Write profile creation trigger + test
3. Configure Google OAuth (dev credentials)
4. Configure Apple Sign-In (dev credentials)
5. Confirm `platform_admin` role can be manually set and unlocks all RLS policies

---

#### Slice 1.3 — GIS Microservice Skeleton

**Tracer bullet**: `docker-compose up gis` → `GET /health` returns `200 {"status": "ok"}`.

**Build order**:
1. Dockerfile with GDAL, rasterio, pdal, rio-cogeo, rio-tiler installed
2. FastAPI app with `/health`, `/jobs` (POST), `/jobs/{id}` (GET)
3. Job state machine: `pending → processing → completed | failed`
4. In-process watchdog enforces timeouts per `job_type` (30/60/20 min)

**Deep module — `services/gis/`**:
Interface (3 HTTP endpoints):
- `POST /jobs` — accepts `{ job_type, input_files[], region_id }`, returns `{ job_id }`
- `GET /jobs/{id}` — returns `{ status, progress, error_message }`
- `GET /health`

Implementation hides: GDAL reprojection, tile encoding, pdal filtering, watchdog thread, Supabase Storage upload, Realtime progress push. Callers (Studio) never call GDAL — they call `/jobs`.

**Port: `GISJobPort`** (introduced here because Studio needs it and tests need an in-memory substitute):
- Production adapter: HTTP client to Python service
- Test adapter: in-memory job runner (returns completed immediately with fixture tiles)

---

#### Slice 1.4 — Monorepo + Shared Types

**Tracer bullet**: `pnpm typecheck` passes across all packages with a stub `shared` module exporting the generated database types.

**Build order**:
1. `pnpm workspaces` root with `packages/` and `services/` layout
2. `packages/shared/` — TypeScript types generated from Supabase schema (via `supabase gen types`)
3. Lint config, TypeScript config, path aliases

---

#### Slice 1.5 — CI Pipeline

**Tracer bullet**: Open a PR with a trivial change → Actions runs lint + typecheck + `supabase db push --dry-run` (migration validation) → all green.

**Build order**:
1. GitHub Actions workflow: install → lint → typecheck → migration validation
2. Smoke test job: start local Supabase in CI, run SQL assertions from Slice 1.1

---

## Phase 2 — Pathfinder Studio

**Goal of the phase**: Import a Banff GeoTIFF, process it, see the terrain in CesiumJS, publish it. A failed job can be retried without re-uploading.

### Vertical Slices

#### Slice 2.1 — Electron Shell + Auth

**Tracer bullet**: Launch Studio → sign in as `platform_admin` → main window renders with no errors.

**Build order**:
1. Electron + React + TypeScript scaffold (Vite renderer, Electron Forge main)
2. Supabase client initialized with local credentials from env
3. Login screen → `supabase.auth.signInWithPassword` → store session
4. Auth guard: unauthenticated renders login; `platform_admin` role check gates app

---

#### Slice 2.2 — Region Management

**Tracer bullet**: Create a region named "Banff" with a bounding polygon → row appears in `regions` table → region shows in list UI.

**Build order**:
1. Region list page (read from `regions` where admin)
2. Create region modal: name, slug (auto-derived), bbox draw or coordinate entry, description
3. Publish / unpublish toggle (sets `published` flag)
4. Tag support

**Deep module — `RegionStore`**:
Interface: `createRegion(name, boundary)`, `publishRegion(id)`, `listRegions()`.
Implementation hides: PostGIS polygon validation, slug collision resolution, RLS-compliant Supabase calls.

---

#### Slice 2.3 — File Import + Job Submission

**Tracer bullet**: Drag a GeoTIFF onto the import zone → an `import_jobs` row is created with `status = 'pending'` → the GIS service receives the job.

**Build order**:
1. Drag-and-drop file zone (GeoTIFF only in Phase 2 MVP; LiDAR deferred to tech debt)
2. Upload source file to Supabase Storage
3. Create `import_jobs` row
4. Call `GISJobPort.submit(job)` → returns job ID

---

#### Slice 2.4 — Progress Tracking via Realtime (no polling)

**Tracer bullet**: Job starts → Studio UI shows live progress percentage → status transitions to `completed` without a page reload.

**Build order**:
1. Subscribe to `import_jobs` Realtime channel filtered by `id`
2. Progress bar updates on each status change
3. Job timeout watchdog in GIS service marks `failed` after threshold; Studio reflects this immediately
4. Retry button: calls `GISJobPort.retry(jobId)` → new job reuses `input_files` from original

**Deep module — `ImportJobManager`**:
Interface: `submit(file, regionId)` → `Observable<JobStatus>`, `retry(jobId)` → `Observable<JobStatus>`.
Implementation hides: Storage upload, `import_jobs` DB write, GIS HTTP call, Realtime subscription wiring, timeout enforcement, retry logic (preserves `input_files`, increments `retry_count`). Callers only observe a stream of status events.

---

#### Slice 2.5 — Tile Viewer (CesiumJS)

**Tracer bullet**: Job completes → tile set row exists in DB with `storage_path` → CesiumJS viewer renders terrain from local Supabase Storage PMTiles.

**Build order**:
1. CesiumJS installed in renderer
2. `TileViewer.load(tileSetId)` → fetches tile set metadata → constructs PMTiles URL → configures `CesiumTerrainProvider`
3. Camera centers on tile set bounds
4. Viewer only shown after job `status = 'completed'`

**Deep module — `TileViewer`**:
Interface: `load(tileSetId)`, `clear()`.
Implementation hides: PMTiles URL construction, CesiumJS provider configuration, camera animation, tile format fallback. Callers pass an ID; CesiumJS is an internal detail.

---

## Phase 3 — Pathfinder (Mobile Game)

**Goal of the phase**: App runs on real hardware. User logs a discovery offline, reconnects, discovery passes moderation, 3D asset is placed, second user verifies it, regional completion updates.

### Vertical Slices

#### Slice 3.1 — React Native Shell + Auth

**Tracer bullet**: App launches on a real iPhone and Android device → sign up with email → profile exists → user reaches home screen.

**Build order**:
1. Expo scaffold (managed workflow, TypeScript)
2. Supabase client with dev credentials
3. Sign up / log in screens
4. Google Sign-In, Apple Sign-In
5. Auth context: session persisted via SecureStore

---

#### Slice 3.2 — Map Load + GPS

**Tracer bullet**: Home screen renders a MapLibre map centered on user GPS position with terrain tiles from a published region.

**Build order**:
1. MapLibre GL React Native installed
2. `TileCacheManager.resolveUrl(regionId)` returns the correct tile URL (Supabase Storage in dev)
3. GPS location tracked via `expo-location`; user marker on map
4. 2.5D pitch enabled; elevation tiles drive terrain shading

**Deep module — `TileCacheManager`**:
Interface: `ensureRegion(regionId)` → `TileSource`, `checkFreshness(regionId)` → `FreshnessStatus`.
Implementation hides: tile URL construction, MBTiles download, local tile server, version comparison against server, stale badge emission. Callers ask for tiles by region ID — they never see a URL.

---

#### Slice 3.3 — Offline Tile Download

**Tracer bullet**: User downloads Banff region → disable network → map still renders terrain → stale indicator appears when tiles are outdated on reconnect.

**Build order**:
1. Region download screen: shows size estimate, progress bar
2. MBTiles download to device storage
3. Local tile server serves MBTiles when offline
4. On reconnect: `checkFreshness` detects newer tile set version → UI shows "out of date" badge
5. Free user cap: 1 offline region enforced in `TileCacheManager`

---

#### Slice 3.4 — Discovery Submit (Offline-First)

**Tracer bullet**: Snap a photo while offline → AI species suggestion shown → player confirms → placeholder dot appears on map immediately → discovery is in local SQLite.

**Build order**:
1. SQLite database via `expo-sqlite` for local discovery storage
2. Camera capture via `expo-camera`
3. AI species ID — on-device model first, API fallback when online
4. Confirm / override / manual entry flow
5. Write to SQLite; return `localId`
6. `DiscoveryEngine.submit()` places placeholder dot on map layer immediately
7. Rate limit check: max 20/hour enforced locally (and later at API)

**Deep module — `DiscoveryEngine`**:
Interface: `submit(photo, location, notes)` → `Discovery`, `getLocalDiscoveries()` → `Discovery[]`.
Implementation hides: SQLite schema and queries, AI ID call, optimistic map update, rate limit state, sync queue enqueue. Callers never import `expo-sqlite`.

---

#### Slice 3.5 — Sync + Moderation

**Tracer bullet**: Reconnect after offline discovery → discovery uploads to Supabase → automated moderation passes → `moderation_status = 'approved'` → canonical asset placed → in-app notification sent.

**Build order**:
1. `SyncEngine.syncWhenOnline()` — detects connectivity, batches pending local discoveries, uploads via REST
2. Supabase Edge Function runs text + vision moderation on sync
3. Failed moderation → `flagged` → enters manual queue
4. Passed moderation → canonical asset lookup: exists → place on map; missing → enqueue Meshy generation job
5. Meshy job completes → `canonical_assets` row updated → Realtime push to mobile → asset placed → in-app notification

**Port: `ModerationPort`**:
- Production adapter: Supabase Edge Function (text + vision model)
- Test adapter: in-memory pass-through (always approves) and always-rejects variant

**Deep module — `SyncEngine`**:
Interface: `syncWhenOnline()`, `pendingCount()` → `number`.
Implementation hides: connectivity detection (NetInfo), ordered upload batching, discovery → server ID mapping, Realtime subscription for asset placement, notification dispatch. Callers call `syncWhenOnline()` — they never see HTTP requests.

---

#### Slice 3.6 — Discovery Verification

**Tracer bullet**: Second user walks within 100m of an approved discovery → proximity prompt appears → user confirms → `discovery_verifications` row created → `verification_count` increments.

**Build order**:
1. Background location monitor compares user position against nearby approved discoveries (spatial query)
2. Category-aware prompt: proximity confirm for landmarks, structured questions for trail conditions, photo re-submission for flora/fauna
3. Write to `discovery_verifications`; constrained by `UNIQUE (discovery_id, user_id)` — no double-counting
4. `verified_discovery_count` on `profiles` increments (trigger)

---

#### Slice 3.7 — Gamification + Lab Access Progress

**Tracer bullet**: Discovery approved → XP awarded → if level threshold crossed, level-up notification fires → Lab access progress bar advances.

**Build order**:
1. `GamificationEngine.onDiscoveryApproved(discovery)` — XP math, level threshold check, badge award checks
2. Streak tracking: `user_stats.current_streak_days` updated on first daily discovery
3. Lab access progress bar: `(verified_discovery_count / 100)` capped at 100%
4. Regional milestone badges (first discovery in a region, 10% completion, etc.)

**Deep module — `GamificationEngine`**:
Interface: `onDiscoveryApproved(discovery)` → `GamificationResult`, `onVerificationSubmitted(verification)` → `GamificationResult`.
Implementation hides: all XP tables, level thresholds, badge award predicates, streak logic, Lab access threshold. If the numbers change, callers don't change.

---

#### Slice 3.8 — Discovery Decay

**Tracer bullet**: Seed a discovery with `decays_at = yesterday` → background job runs → discovery removed from active map layer → regional completion percentage decreases.

**Build order**:
1. Supabase scheduled Edge Function (cron): scan `discoveries WHERE decays_at < now()` → mark inactive
2. Mobile Realtime subscription removes decayed discoveries from map layer
3. Re-verification resets `decays_at` clock (trigger on `discovery_verifications` insert)
4. Pro `anchored` flag skips decay

---

#### Slice 3.9 — Community Map Layer + Friends

**Tracer bullet**: Second user's approved discovery appears on first user's map; friend's discovery is highlighted.

**Build order**:
1. Community layer: approved public discoveries fetched via spatial query (ST_DWithin bounding box)
2. Friend list: follow/unfollow, stored as a simple junction table
3. Friends' discoveries rendered with distinct highlight style
4. GDPR deletion flow: "delete my account" button → flags account for manual deletion within 30 days

---

#### Slice 3.10 — Moderation Pipeline + Content Quality

**Tracer bullet**: Submit a discovery with flagged text → `moderation_status = 'flagged'` → manual review queue entry appears in Studio → admin removes it → contributor receives in-app notification.

**Build order**:
1. Manual review queue in Studio (simple table of `flagged` discoveries, approve/remove actions)
2. `discovery_removed` notification dispatched on admin removal
3. Map data quality overlay: community-tier vs. authoritative-tier coverage cells, onboarding disclaimer

---

## Phase 4 — Pathfinder Lab + Notifications

**Goal of the phase**: Authorized mapper captures a trail segment, submits it, admin approves in Studio, updated terrain appears in Pathfinder app. Pro user records a hike and views stats.

### Vertical Slices

#### Slice 4.1 — Lab App Shell + Auth Gate

**Tracer bullet**: Open Lab app → `authorized_mapper` check passes → main screen renders; non-authorized user sees a clear access-denied screen.

**Build order**:
1. Separate React Native app (Expo bare workflow, iOS-first)
2. Auth reused from `packages/shared` — same Supabase instance
3. Authorization check: `profiles.role = 'authorized_mapper'` OR `organization_members` row exists
4. Access-denied screen with "Learn how to become an authorized mapper" CTA

---

#### Slice 4.2 — LiDAR Capture Session

**Tracer bullet**: Tap "Start Capture" → ARKit session opens → walk 10 meters → tap "Stop" → point cloud and GPS track are stored locally.

**Build order**:
1. Native Swift module: wraps ARKit LiDAR session, exports `startCapture()` / `stopCapture()` → PLY + pose data
2. CoreLocation GPS track recorded in parallel, stored as GPX
3. `CaptureSessionManager.startCapture()` orchestrates both; stops both atomically
4. Preview screen: renders point cloud thumbnail before submit decision

**Deep module — `CaptureSessionManager`**:
Interface: `startCapture()`, `stopCapture()` → `CaptureSession`, `preview(session)`, `submit(session)`.
Implementation hides: ARKit frame accumulation, point cloud buffering, GPS track interpolation, PLY serialization, storage, Supabase upload, `field_captures` row creation. Callers see a three-method lifecycle — ARKit is an internal detail.

---

#### Slice 4.3 — QA Queue in Studio

**Tracer bullet**: Submitted field capture appears in Studio QA queue → admin clicks "Approve" → GIS pipeline merges it into the region's terrain → updated tile set published.

**Build order**:
1. QA queue tab in Studio: lists `field_captures WHERE status = 'submitted'`
2. Point cloud preview (Potree-based viewer in Studio)
3. Approve → triggers `ImportJobManager.submit()` with `job_type = 'field_capture'`; `field_captures.status = 'under_review'`
4. GIS pipeline extension: `field_capture` job type; pdal georeferencing + merge + re-tile affected zoom levels
5. Job completes → `status = 'approved'`; new tile set published → submitter notified via `submission_approved` event
6. Reject → `status = 'rejected'`; `review_notes` written; submitter notified via `submission_rejected`

---

#### Slice 4.4 — Pro Features

**Tracer bullet**: Pro-flagged user starts hike recording → GPX track saved → stats dashboard shows distance and elevation gain.

**Build order**:
1. Hike track recording: background GPS → `hike_tracks` row on end
2. Field Journal: personal discovery history by date, region, category
3. Stats dashboard (Pro gate): total distance, elevation gain, streak; reads from `user_stats`
4. Multi-device sync: hike tracks and preferences sync via Supabase Realtime
5. Unlimited offline regions (remove 1-region cap in `TileCacheManager` for Pro users)
6. Pro upgrade prompts at each feature gate

---

#### Slice 4.5 — Push Notifications

**Tracer bullet**: Discovery approved → push notification received on the contributor's device with the correct title and body.

**Build order**:
1. Expo Notifications: request permissions, store push token on `profiles` (add `push_token` column)
2. Supabase Edge Function `dispatch-notification`: reads preferences, selects channel, sends push (Expo SDK → APNs/FCM) and writes `notifications` row for in-app inbox
3. Per-event-type preference toggles (push vs in-app per `notification_event_type`)

**Port: `NotificationPort`**:
- Push adapter: Expo Notifications SDK → APNs/FCM
- In-app adapter: `notifications` DB insert
- Test adapter: in-memory event collector

**Deep module — `NotificationRouter`**:
Interface: `dispatch(event, userId, payload)`.
Implementation hides: preference table lookup, channel selection, Expo push call, in-app DB write, deduplication. Callers fire one method — they don't know if it sent a push or wrote a row.

---

#### Slice 4.6 — Professional Capture Path (Studio)

**Tracer bullet**: Admin uploads a Mosaic Xplor `.las` file in Studio with `data_quality_tier = 'authoritative'` → job processes → tile set tagged authoritative → appears on mobile map quality overlay.

**Build order**:
1. LiDAR (`.las`/`.laz`) file type enabled in Studio import (previously GeoTIFF-only MVP)
2. `data_quality_tier` selector in import UI
3. GIS pipeline handles `.las` via pdal
4. Mobile quality overlay distinguishes authoritative vs. community tiles visually

---

## Phase 5 — Cloud Migration + Commercial Launch

**Goal of the phase**: Move off local Docker, launch publicly, onboard first paying B2B clients.

### Vertical Slices

#### Slice 5.1 — CDN Migration

**Tracer bullet**: PMTiles file published → `tile_sets.cdn_url` set to Cloudflare R2 URL → mobile app resolves to CDN URL without a code change.

**Build order**:
1. Cloudflare R2 bucket + public domain (`tiles.pathfinder.app`)
2. Studio publish action: after Supabase Storage upload → sync to R2 → set `cdn_url`
3. `TileCacheManager.resolveUrl()` returns `cdn_url` when present, falls back to `storage_path`
4. No mobile code change required (URL structure is stable by design from Phase 2)

---

#### Slice 5.2 — Supabase Cloud Migration

**Tracer bullet**: `supabase db push` to cloud instance → all migrations apply cleanly → mobile app and Studio connect to cloud with only env var changes.

**Build order**:
1. Export local project, push to Supabase Cloud (or self-hosted)
2. Update all `SUPABASE_URL` / `SUPABASE_ANON_KEY` env vars
3. Run smoke tests from Phase 1 against cloud instance
4. GIS microservice security: shared secret or mTLS before cloud exposure (previously internal-only)

---

#### Slice 5.3 — Stripe Billing

**Tracer bullet**: Community user taps "Upgrade to Pro" → Stripe checkout session opens → payment complete → `profiles.is_pro = true` → Pro feature gates unlock without app restart.

**Build order**:
1. Stripe customer created on first Pro intent (`stripe_customer_id` on `profiles`)
2. Checkout session created via Supabase Edge Function
3. Stripe webhook handler: `customer.subscription.created` / `updated` / `deleted` → update `profiles.is_pro`, `organizations.billing_status`, `organizations.stripe_subscription_id`
4. Org subscriptions: same flow with `organizations` table

**Port: `BillingPort`** (Stripe is a true external — mock in tests):
- Production adapter: Stripe SDK
- Test adapter: in-memory checkout that fires webhook events synchronously

**Deep module — `BillingService`**:
Interface: `createCheckout(userId, plan)` → `CheckoutUrl`, `handleWebhook(event)`.
Implementation hides: Stripe customer lifecycle, idempotency keys, subscription state machine, DB updates. Callers never import Stripe SDK.

---

#### Slice 5.4 — Org Account Management UI

**Tracer bullet**: Platform admin creates an org → assigns a plan tier → invites a member by email → member receives invite → signs up → `organization_members` row created.

**Build order**:
1. Org management section in Studio (or lightweight web dashboard — build after first B2B client is closed)
2. Create org form: name, type, plan tier
3. Invite member: creates invite token, sends email, redeems on sign-up
4. Org admin panel: view members, manage roles

---

#### Slice 5.5 — App Store Submissions

**Tracer bullet**: Pathfinder app submitted to App Store and Play Store; Pathfinder Lab submitted to TestFlight.

**Build order**:
1. Electron auto-update for Studio (Electron Forge + update server)
2. Expo EAS Build + EAS Submit configured for Pathfinder
3. Privacy policy, App Store metadata, screenshots
4. CI/CD: automated build + deploy pipelines for all components
5. Lab: internal TestFlight distribution (not public App Store yet)

---

#### Slice 5.6 — Discovery Analytics (Org Accounts)

**Tracer bullet**: Org account with sufficient regional coverage → analytics dashboard shows visitor heatmap and top species sightings by trail.

**Build order**:
1. Coverage threshold check: only surface analytics once regional coverage exceeds a meaningful threshold
2. Heatmap: aggregate approved discovery locations by tile cell, return as GeoJSON
3. Species sightings by trail: join discoveries with hike tracks spatial proximity
4. Trail condition trends: category-filtered time series

---

## Cross-Cutting Seams Summary

| Port | Production Adapter | Test Adapter | Introduced |
|---|---|---|---|
| `GISJobPort` | HTTP → Python GIS service | In-memory instant job | Phase 2 |
| `TileStoragePort` | Supabase Storage / R2 | In-memory FS | Phase 2 |
| `ModerationPort` | Supabase Edge Function | Pass-through / always-flag | Phase 3 |
| `NotificationPort` | Expo Notifications (APNs/FCM) + DB | In-memory event collector | Phase 4 |
| `BillingPort` | Stripe SDK | In-memory checkout | Phase 5 |

Ports are not introduced speculatively — each one earns its seam by having both a production adapter and a test adapter from day one.

---

## Deep Module Inventory

| Module | Interface surface | What it hides |
|---|---|---|
| `packages/backend/` | `supabase db push / reset` | Migrations, triggers, RLS, enums |
| `services/gis/` | 3 HTTP endpoints | GDAL, pdal, rasterio, tile encoding, watchdog |
| `ImportJobManager` | `submit()`, `retry()` → Observable | Storage upload, DB write, GIS call, Realtime, timeout |
| `TileViewer` | `load(tileSetId)`, `clear()` | PMTiles URL, CesiumJS provider, camera |
| `RegionStore` | `createRegion()`, `publishRegion()`, `listRegions()` | PostGIS validation, slug collision |
| `TileCacheManager` | `ensureRegion()`, `checkFreshness()` | MBTiles download, local server, version comparison |
| `DiscoveryEngine` | `submit()`, `getLocalDiscoveries()` | SQLite, AI call, optimistic map update, rate limit |
| `SyncEngine` | `syncWhenOnline()`, `pendingCount()` | HTTP batch, ID mapping, Realtime subscription |
| `GamificationEngine` | `onDiscoveryApproved()`, `onVerificationSubmitted()` | XP tables, level thresholds, badge predicates, Lab access |
| `CaptureSessionManager` | `startCapture()`, `stopCapture()`, `submit()` | ARKit, GPS, PLY, upload, DB row |
| `NotificationRouter` | `dispatch(event, userId, payload)` | Preference lookup, push vs in-app, deduplication |
| `BillingService` | `createCheckout()`, `handleWebhook()` | Stripe lifecycle, idempotency, DB updates |

---

## Related

- [[Build Roadmap]]
- [[Architecture]]
- [[Data Pipeline]]
- [[Database Schema]]
- [[Pathfinder Studio]]
- [[Pathfinder]]
- [[Pathfinder Lab]]
