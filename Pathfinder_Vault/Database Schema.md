# Database Schema

The Pathfinder database runs on PostgreSQL with the PostGIS extension. It is hosted by Supabase, which auto-generates a REST API from this schema and enforces Row-Level Security (RLS) policies at the database level.

All tables use `uuid` primary keys and `timestamptz` for timestamps. Spatial columns use `EPSG:4326` (WGS84) as the stored CRS.

---

## Enums

```sql
CREATE TYPE user_role AS ENUM (
  'community',
  'authorized_mapper',
  'platform_admin'
);

CREATE TYPE org_role AS ENUM (
  'org_member',
  'org_admin'
);

CREATE TYPE organization_type AS ENUM (
  'park',
  'trail_association',
  'commercial',
  'other'
);

CREATE TYPE plan_tier AS ENUM (
  'small',    -- up to 500 sq km
  'medium',   -- 500–2,000 sq km
  'large'     -- 2,000+ sq km
);

CREATE TYPE billing_status AS ENUM (
  'trial',
  'active',
  'inactive'
);

CREATE TYPE tile_type AS ENUM (
  'elevation_raster',
  'vector_features',
  'point_cloud'
);

CREATE TYPE data_quality_tier AS ENUM (
  'community',      -- iPhone LiDAR / community capture (5–10m accuracy)
  'authoritative'   -- professional survey / government LiDAR (sub-10cm)
);

CREATE TYPE tile_format AS ENUM (
  'pmtiles',
  'mbtiles'
);

CREATE TYPE job_status AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE job_type AS ENUM (
  'geotiff',
  'lidar',
  'field_capture'
);

CREATE TYPE discovery_category AS ENUM (
  'flora',
  'fauna',
  'landmark',
  'trail_condition',
  'fungi',
  'geological',
  'other'
);

CREATE TYPE identification_source AS ENUM (
  'ai_confirmed',   -- player confirmed AI suggestion
  'ai_corrected',   -- player overrode AI suggestion
  'manual'          -- player entered text without AI suggestion
);

CREATE TYPE decay_rate AS ENUM (
  'fast',       -- weeks (trail conditions)
  'medium',     -- months (flora/fauna)
  'slow',       -- years (landmarks/geological)
  'permanent'   -- terrain captures
);

CREATE TYPE visibility AS ENUM (
  'public',
  'private'
);

CREATE TYPE moderation_status AS ENUM (
  'pending',    -- awaiting automated review
  'approved',   -- passed automated + manual review
  'flagged',    -- failed automated review, in manual queue
  'removed'     -- removed by moderator
);

CREATE TYPE capture_status AS ENUM (
  'local',        -- not yet uploaded
  'submitted',    -- uploaded, awaiting review
  'under_review', -- admin is actively reviewing
  'approved',     -- merged into terrain
  'rejected'      -- returned with feedback
);

CREATE TYPE notification_event_type AS ENUM (
  'discovery_verification_request',
  'discovery_verified',
  'submission_approved',
  'submission_rejected',
  'lab_access_granted',
  'discovery_removed'
);

CREATE TYPE notification_channel AS ENUM (
  'push',
  'in_app'
);
```

---

## Tables

### profiles

Extends Supabase's `auth.users`. Created automatically via trigger on user sign-up.

```sql
CREATE TABLE profiles (
  id               uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name     text NOT NULL,
  avatar_url       text,
  bio              text,
  role             user_role NOT NULL DEFAULT 'community',
  mapper_trust_level int NOT NULL DEFAULT 0,         -- 0=new, 1=light review, 2=auto-approved
  is_pro           boolean NOT NULL DEFAULT false,  -- Pathfinder Pro subscription
  xp               int NOT NULL DEFAULT 0,
  level            int NOT NULL DEFAULT 1,
  discovery_count  int NOT NULL DEFAULT 0,   -- denormalized, updated via trigger
  verified_discovery_count int NOT NULL DEFAULT 0,  -- discoveries confirmed by others
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
```

---

### organizations

Organizational accounts — trail associations, regional park authorities, commercial clients.

```sql
CREATE TABLE organizations (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                  text NOT NULL,
  slug                  text NOT NULL UNIQUE,
  type                  organization_type NOT NULL DEFAULT 'other',
  plan_tier             plan_tier,                         -- null until subscribed
  billing_status        billing_status NOT NULL DEFAULT 'trial',
  stripe_customer_id    text,                              -- set on Stripe customer creation
  stripe_subscription_id text,                            -- set on active subscription
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
```

---

### organization_members

Junction table linking users to organizations. Org membership grants Pathfinder Lab access independently of `profiles.role`.

```sql
CREATE TABLE organization_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role            org_role NOT NULL DEFAULT 'org_member',
  created_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (organization_id, user_id)
);
```

---

### regions

A named geographic area that has been imported and published.

```sql
CREATE TABLE regions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  slug            text NOT NULL UNIQUE,
  description     text,
  boundary        geometry(Polygon, 4326) NOT NULL,  -- required at creation (rough bbox is fine)
  organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
  created_by      uuid NOT NULL REFERENCES profiles(id),
  published       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX regions_boundary_idx ON regions USING GIST (boundary);
CREATE INDEX regions_published_idx ON regions (published);
```

---

### tile_sets

A processed tile package associated with a region. Tile sets carry a `data_quality_tier` to distinguish community captures from authoritative professional data.

```sql
CREATE TABLE tile_sets (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  region_id         uuid NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
  type              tile_type NOT NULL,
  format            tile_format NOT NULL DEFAULT 'pmtiles',
  data_quality_tier data_quality_tier NOT NULL DEFAULT 'community',
  storage_path      text NOT NULL,  -- path in Supabase Storage (or CDN key)
  cdn_url           text,           -- public CDN URL once published (Cloudflare R2 or equivalent)
  source_license    text,           -- license identifier for source data (e.g. 'OGL-Canada', 'USGS-Public-Domain')
  zoom_min          int NOT NULL DEFAULT 0,
  zoom_max          int NOT NULL DEFAULT 14,
  bounds            geometry(Polygon, 4326),
  source_files      jsonb NOT NULL DEFAULT '[]',  -- [{ path, format, size_bytes }]
  published         boolean NOT NULL DEFAULT false,
  supersedes_id     uuid REFERENCES tile_sets(id) ON DELETE SET NULL,  -- previous version this replaces
  created_by        uuid NOT NULL REFERENCES profiles(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX tile_sets_region_idx ON tile_sets (region_id, published);
CREATE INDEX tile_sets_bounds_idx ON tile_sets USING GIST (bounds);
CREATE INDEX tile_sets_quality_idx ON tile_sets (region_id, data_quality_tier, published);
```

---

### import_jobs

Tracks GIS processing jobs submitted from Pathfinder Studio to the Python microservice.

Job timeouts by type (enforced by a watchdog process):
- `geotiff`: 30 minutes
- `lidar`: 60 minutes
- `field_capture`: 20 minutes

After timeout, status is set to `failed` with an appropriate error message. Failed jobs can be retried from Studio.

```sql
CREATE TABLE import_jobs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  region_id           uuid NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
  job_type            job_type NOT NULL,
  status              job_status NOT NULL DEFAULT 'pending',
  input_files         jsonb NOT NULL DEFAULT '[]',  -- [{ storage_path, format, size_bytes }]
  output_tile_set_id  uuid REFERENCES tile_sets(id) ON DELETE SET NULL,
  error_message       text,
  retry_count         int NOT NULL DEFAULT 0,
  started_at          timestamptz,
  completed_at        timestamptz,
  created_by          uuid NOT NULL REFERENCES profiles(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX import_jobs_region_idx ON import_jobs (region_id);
CREATE INDEX import_jobs_status_idx ON import_jobs (status);
CREATE INDEX import_jobs_started_at_idx ON import_jobs (started_at) WHERE status = 'processing';
```

---

### discoveries

Community discovery logs from the Pathfinder mobile game. Append-only — records are never updated after sync, only soft-deleted via `visibility = 'private'`.

```sql
CREATE TABLE discoveries (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  region_id             uuid REFERENCES regions(id) ON DELETE SET NULL,  -- auto-detected on sync
  category              discovery_category NOT NULL,
  identified_species    text,                        -- player-confirmed common or scientific name
  ai_suggested_species  text,                        -- raw model output (retained for accuracy tracking)
  ai_confidence         float,                       -- model confidence score 0–1
  identification_source identification_source,       -- how the identification was provided
  canonical_asset_id    uuid REFERENCES canonical_assets(id) ON DELETE SET NULL,
  title                 text,
  notes                 text,
  location              geometry(Point, 4326) NOT NULL,
  elevation             float,  -- metres, derived from terrain data on sync
  decay_rate            decay_rate NOT NULL,          -- derived from category at insert
  decays_at             timestamptz,                  -- computed from decay_rate + last verification
  anchored              boolean NOT NULL DEFAULT false,  -- Pro: resists decay
  visibility            visibility NOT NULL DEFAULT 'public',
  moderation_status     moderation_status NOT NULL DEFAULT 'pending',
  verification_count    int NOT NULL DEFAULT 0,  -- number of independent confirmations
  captured_at           timestamptz NOT NULL,  -- device time of discovery
  synced_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX discoveries_location_idx ON discoveries USING GIST (location);
CREATE INDEX discoveries_user_idx ON discoveries (user_id);
CREATE INDEX discoveries_region_idx ON discoveries (region_id);
CREATE INDEX discoveries_category_idx ON discoveries (category);
CREATE INDEX discoveries_visibility_idx ON discoveries (visibility);
CREATE INDEX discoveries_moderation_idx ON discoveries (moderation_status) WHERE moderation_status = 'flagged';
```

---

### canonical_assets

One canonical 3D asset per identified species. Generated via Meshy on first submission of a new species; reused for all subsequent discoveries of the same species.

```sql
CREATE TABLE canonical_assets (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identified_species text NOT NULL UNIQUE,   -- common or scientific name used as lookup key
  asset_url         text,                    -- URL to the 3D model once generated
  asset_quality     text NOT NULL DEFAULT 'standard',  -- 'standard' | 'pro' (higher fidelity)
  generation_status text NOT NULL DEFAULT 'pending',   -- 'pending' | 'generating' | 'ready' | 'failed'
  meshy_job_id      text,                   -- external job reference for polling
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX canonical_assets_species_idx ON canonical_assets (identified_species);
```

---

### discovery_photos

Photos attached to a discovery.

```sql
CREATE TABLE discovery_photos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_id  uuid NOT NULL REFERENCES discoveries(id) ON DELETE CASCADE,
  storage_path  text NOT NULL,
  width         int,
  height        int,
  sort_order    int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX discovery_photos_discovery_idx ON discovery_photos (discovery_id);
```

---

### discovery_verifications

Records each user confirmation of a discovery. Prevents double-counting if the same user walks past the same discovery multiple times.

```sql
CREATE TABLE discovery_verifications (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_id         uuid NOT NULL REFERENCES discoveries(id) ON DELETE CASCADE,
  user_id              uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  verification_type    text,         -- 'proximity_confirm', 'structured_question', 'photo_resubmission'
  response_data        jsonb,        -- structured question answers or re-identification data
  photo_storage_path   text,         -- set if verification included a photo re-submission
  created_at           timestamptz NOT NULL DEFAULT now(),

  UNIQUE (discovery_id, user_id)
);

CREATE INDEX discovery_verifications_discovery_idx ON discovery_verifications (discovery_id);
CREATE INDEX discovery_verifications_user_idx ON discovery_verifications (user_id);
```

---

### hike_tracks

GPS tracks recorded by Pro users during hikes.

```sql
CREATE TABLE hike_tracks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  region_id    uuid REFERENCES regions(id) ON DELETE SET NULL,
  track        geometry(LineString, 4326) NOT NULL,
  distance_m   float,    -- total distance in metres
  elevation_gain_m float, -- total elevation gain in metres
  duration_s   int,      -- duration in seconds
  storage_path text,     -- .gpx file in Supabase Storage
  started_at   timestamptz NOT NULL,
  ended_at     timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX hike_tracks_user_idx ON hike_tracks (user_id);
CREATE INDEX hike_tracks_region_idx ON hike_tracks (region_id);
CREATE INDEX hike_tracks_track_idx ON hike_tracks USING GIST (track);
```

---

### user_stats

Aggregated stats per user. Updated via trigger on discoveries, verifications, and hike_tracks. Stored for all users; surfaced in-app only for Pro users.

```sql
CREATE TABLE user_stats (
  user_id              uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  total_distance_m     float NOT NULL DEFAULT 0,
  total_elevation_gain_m float NOT NULL DEFAULT 0,
  total_hike_count     int NOT NULL DEFAULT 0,
  total_discovery_count int NOT NULL DEFAULT 0,
  total_verification_count int NOT NULL DEFAULT 0,
  current_streak_days  int NOT NULL DEFAULT 0,
  longest_streak_days  int NOT NULL DEFAULT 0,
  last_active_date     date,
  updated_at           timestamptz NOT NULL DEFAULT now()
);
```

---

### badges

Badge definitions. Seeded by the platform.

```sql
CREATE TABLE badges (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text NOT NULL,
  icon_url    text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
```

---

### user_badges

Awards junction table.

```sql
CREATE TABLE user_badges (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  badge_id   uuid NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  awarded_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, badge_id)
);

CREATE INDEX user_badges_user_idx ON user_badges (user_id);
```

---

### notifications

In-app notifications for all users. Push notifications are sent via Expo Notifications at event time; this table stores the in-app inbox record.

```sql
CREATE TABLE notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type  notification_event_type NOT NULL,
  title       text NOT NULL,
  body        text,
  data        jsonb NOT NULL DEFAULT '{}',  -- event-specific payload (discovery_id, etc.)
  read        boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx ON notifications (user_id, read, created_at DESC);
```

---

### notification_preferences

Per-user, per-event-type channel preferences.

```sql
CREATE TABLE notification_preferences (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type  notification_event_type NOT NULL,
  channel     notification_channel NOT NULL DEFAULT 'in_app',
  enabled     boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, event_type)
);
```

---

### field_captures

LiDAR field capture sessions from Pathfinder Lab.

```sql
CREATE TABLE field_captures (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  organization_id          uuid REFERENCES organizations(id) ON DELETE SET NULL,
  region_id                uuid REFERENCES regions(id) ON DELETE SET NULL,
  area_tag                 text,
  status                   capture_status NOT NULL DEFAULT 'local',
  data_quality_tier        data_quality_tier NOT NULL DEFAULT 'community',
  gps_track                geometry(LineString, 4326),
  bounds                   geometry(Polygon, 4326),
  point_cloud_storage_path text,
  gps_track_storage_path   text,
  session_metadata         jsonb NOT NULL DEFAULT '{}',  -- device model, capture method, equipment, etc.
  review_notes             text,
  reviewed_by              uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at              timestamptz,
  captured_at              timestamptz NOT NULL,
  submitted_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX field_captures_user_idx ON field_captures (user_id);
CREATE INDEX field_captures_region_idx ON field_captures (region_id);
CREATE INDEX field_captures_status_idx ON field_captures (status);
CREATE INDEX field_captures_quality_idx ON field_captures (data_quality_tier, status);
CREATE INDEX field_captures_gps_track_idx ON field_captures USING GIST (gps_track);
CREATE INDEX field_captures_bounds_idx ON field_captures USING GIST (bounds);
```

---

## Entity Relationship Diagram

```
auth.users
    │
    └──► profiles ◄──────────────────────────────┐
              │                                   │
              ├──► user_stats                     │
              ├──► user_badges ◄── badges         │
              ├──► notifications                  │
              ├──► notification_preferences       │
              ├──► hike_tracks                    │
              │                                   │
              ├──► organization_members           │
              │         │                         │
              │    organizations                  │
              │                                   │
              ├──► regions ◄── tile_sets          │
              │         │           │             │
              │         └── import_jobs ──────────┘
              │
              ├──► discoveries
              │         │
              │    discovery_photos
              │    discovery_verifications
              │
              └──► field_captures
```

---

## Row-Level Security Policies

RLS is enabled on all tables. Supabase enforces these at the database level.

### profiles
- **SELECT**: anyone can read any profile
- **UPDATE**: users can update their own profile only

### organizations
- **SELECT**: authenticated users can read all organizations
- **INSERT / UPDATE / DELETE**: `platform_admin` only

### organization_members
- **SELECT**: org members can see their own org's membership; platform_admin sees all
- **INSERT / DELETE**: `org_admin` for their org; `platform_admin` for all

### regions
- **SELECT**: anyone can read `published = true` regions; `platform_admin` sees all
- **INSERT / UPDATE / DELETE**: `platform_admin` only

### tile_sets
- **SELECT**: anyone can read `published = true` tile sets; `platform_admin` sees all
- **INSERT / UPDATE / DELETE**: `platform_admin` only

### import_jobs
- **SELECT / INSERT / UPDATE**: `platform_admin` only

### discoveries
- **SELECT**: users can read their own (any visibility) + all `approved` public discoveries
- **INSERT**: authenticated users (own records only)
- **UPDATE**: users can update their own (e.g. visibility); `platform_admin` can update moderation_status
- **DELETE**: users can delete their own; `platform_admin` can delete any

### discovery_verifications
- **SELECT**: anyone can read verification counts
- **INSERT**: authenticated users (cannot verify own discoveries)
- **DELETE**: own verifications only

### hike_tracks
- **SELECT**: users can read their own tracks only
- **INSERT / UPDATE / DELETE**: own records only

### notifications
- **SELECT / UPDATE**: users can read and mark their own notifications
- **INSERT**: service role only (created by backend triggers)

### field_captures
- **SELECT**: users can read their own; org_admin can read their org's; platform_admin sees all
- **INSERT**: `authorized_mapper`, org members, `platform_admin`
- **UPDATE**: users can update their own (until submitted); platform_admin can update any
- **DELETE**: users can delete own `local` captures only; platform_admin can delete any

---

## Key Spatial Queries

```sql
-- Find all approved public discoveries within 5km of a point
SELECT * FROM discoveries
WHERE visibility = 'public'
  AND moderation_status = 'approved'
  AND ST_DWithin(
    location::geography,
    ST_MakePoint(-115.5708, 51.1784)::geography,
    5000
  );

-- Find unverified public discoveries within 100m of a user's location (verification prompts)
SELECT d.* FROM discoveries d
WHERE d.visibility = 'public'
  AND d.moderation_status = 'approved'
  AND ST_DWithin(
    d.location::geography,
    ST_MakePoint(-115.5708, 51.1784)::geography,
    100
  )
  AND NOT EXISTS (
    SELECT 1 FROM discovery_verifications dv
    WHERE dv.discovery_id = d.id AND dv.user_id = '<current_user_id>'
  );

-- Find all published regions that contain a GPS coordinate
SELECT * FROM regions
WHERE published = true
  AND ST_Contains(boundary, ST_MakePoint(-115.5708, 51.1784));

-- Find all field captures overlapping a region's boundary
SELECT fc.* FROM field_captures fc
JOIN regions r ON r.id = fc.region_id
WHERE r.slug = 'banff-national-park'
  AND fc.status = 'submitted'
  AND ST_Intersects(fc.bounds, r.boundary);
```

---

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Data Pipeline]]
- [[User And Auth Model]]
- [[Build Roadmap]]
