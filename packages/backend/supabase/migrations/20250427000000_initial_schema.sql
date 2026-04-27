-- =============================================================================
-- Extensions
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- Enums
-- =============================================================================

CREATE TYPE public.user_role AS ENUM (
  'community',
  'authorized_mapper',
  'platform_admin'
);

CREATE TYPE public.org_role AS ENUM (
  'org_member',
  'org_admin'
);

CREATE TYPE public.organization_type AS ENUM (
  'park',
  'trail_association',
  'commercial',
  'other'
);

CREATE TYPE public.plan_tier AS ENUM (
  'small',
  'medium',
  'large'
);

CREATE TYPE public.billing_status AS ENUM (
  'trial',
  'active',
  'inactive'
);

CREATE TYPE public.tile_type AS ENUM (
  'elevation_raster',
  'vector_features',
  'point_cloud'
);

CREATE TYPE public.data_quality_tier AS ENUM (
  'community',
  'authoritative'
);

CREATE TYPE public.tile_format AS ENUM (
  'pmtiles',
  'mbtiles'
);

CREATE TYPE public.job_status AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE public.job_type AS ENUM (
  'geotiff',
  'lidar',
  'field_capture'
);

CREATE TYPE public.discovery_category AS ENUM (
  'flora',
  'fauna',
  'landmark',
  'trail_condition',
  'fungi',
  'geological',
  'other'
);

CREATE TYPE public.identification_source AS ENUM (
  'ai_confirmed',
  'ai_corrected',
  'manual'
);

CREATE TYPE public.decay_rate AS ENUM (
  'fast',
  'medium',
  'slow',
  'permanent'
);

CREATE TYPE public.visibility AS ENUM (
  'public',
  'private'
);

CREATE TYPE public.moderation_status AS ENUM (
  'pending',
  'approved',
  'flagged',
  'removed'
);

CREATE TYPE public.capture_status AS ENUM (
  'local',
  'submitted',
  'under_review',
  'approved',
  'rejected'
);

CREATE TYPE public.notification_event_type AS ENUM (
  'discovery_verification_request',
  'discovery_verified',
  'submission_approved',
  'submission_rejected',
  'lab_access_granted',
  'discovery_removed'
);

CREATE TYPE public.notification_channel AS ENUM (
  'push',
  'in_app'
);

-- =============================================================================
-- Tables (dependency order)
-- =============================================================================

-- profiles — extends auth.users, created via trigger on sign-up
CREATE TABLE public.profiles (
  id                       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name             text NOT NULL,
  avatar_url               text,
  bio                      text,
  role                     public.user_role NOT NULL DEFAULT 'community',
  mapper_trust_level       int NOT NULL DEFAULT 0,
  is_pro                   boolean NOT NULL DEFAULT false,
  xp                       int NOT NULL DEFAULT 0,
  level                    int NOT NULL DEFAULT 1,
  discovery_count          int NOT NULL DEFAULT 0,
  verified_discovery_count int NOT NULL DEFAULT 0,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

-- organizations
CREATE TABLE public.organizations (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    text NOT NULL,
  slug                    text NOT NULL UNIQUE,
  type                    public.organization_type NOT NULL DEFAULT 'other',
  plan_tier               public.plan_tier,
  billing_status          public.billing_status NOT NULL DEFAULT 'trial',
  stripe_customer_id      text,
  stripe_subscription_id  text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

-- organization_members
CREATE TABLE public.organization_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role            public.org_role NOT NULL DEFAULT 'org_member',
  created_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (organization_id, user_id)
);

-- regions
CREATE TABLE public.regions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  slug            text NOT NULL UNIQUE,
  description     text,
  boundary        geometry(Polygon, 4326) NOT NULL,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  created_by      uuid NOT NULL REFERENCES public.profiles(id),
  published       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- canonical_assets — one 3D asset per identified species
CREATE TABLE public.canonical_assets (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identified_species text NOT NULL UNIQUE,
  asset_url          text,
  asset_quality      text NOT NULL DEFAULT 'standard',
  generation_status  text NOT NULL DEFAULT 'pending',
  meshy_job_id       text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- tile_sets
CREATE TABLE public.tile_sets (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  region_id         uuid NOT NULL REFERENCES public.regions(id) ON DELETE CASCADE,
  type              public.tile_type NOT NULL,
  format            public.tile_format NOT NULL DEFAULT 'pmtiles',
  data_quality_tier public.data_quality_tier NOT NULL DEFAULT 'community',
  storage_path      text NOT NULL,
  cdn_url           text,
  source_license    text,
  zoom_min          int NOT NULL DEFAULT 0,
  zoom_max          int NOT NULL DEFAULT 14,
  bounds            geometry(Polygon, 4326),
  source_files      jsonb NOT NULL DEFAULT '[]',
  published         boolean NOT NULL DEFAULT false,
  supersedes_id     uuid REFERENCES public.tile_sets(id) ON DELETE SET NULL,
  created_by        uuid NOT NULL REFERENCES public.profiles(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- import_jobs
CREATE TABLE public.import_jobs (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  region_id          uuid NOT NULL REFERENCES public.regions(id) ON DELETE CASCADE,
  job_type           public.job_type NOT NULL,
  status             public.job_status NOT NULL DEFAULT 'pending',
  input_files        jsonb NOT NULL DEFAULT '[]',
  output_tile_set_id uuid REFERENCES public.tile_sets(id) ON DELETE SET NULL,
  error_message      text,
  retry_count        int NOT NULL DEFAULT 0,
  started_at         timestamptz,
  completed_at       timestamptz,
  created_by         uuid NOT NULL REFERENCES public.profiles(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- discoveries
CREATE TABLE public.discoveries (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  region_id            uuid REFERENCES public.regions(id) ON DELETE SET NULL,
  category             public.discovery_category NOT NULL,
  identified_species   text,
  ai_suggested_species text,
  ai_confidence        float,
  identification_source public.identification_source,
  canonical_asset_id   uuid REFERENCES public.canonical_assets(id) ON DELETE SET NULL,
  title                text,
  notes                text,
  location             geometry(Point, 4326) NOT NULL,
  elevation            float,
  decay_rate           public.decay_rate NOT NULL,
  decays_at            timestamptz,
  anchored             boolean NOT NULL DEFAULT false,
  visibility           public.visibility NOT NULL DEFAULT 'public',
  moderation_status    public.moderation_status NOT NULL DEFAULT 'pending',
  verification_count   int NOT NULL DEFAULT 0,
  captured_at          timestamptz NOT NULL,
  synced_at            timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

-- discovery_photos
CREATE TABLE public.discovery_photos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_id uuid NOT NULL REFERENCES public.discoveries(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  width        int,
  height       int,
  sort_order   int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- discovery_verifications
CREATE TABLE public.discovery_verifications (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_id       uuid NOT NULL REFERENCES public.discoveries(id) ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  verification_type  text,
  response_data      jsonb,
  photo_storage_path text,
  created_at         timestamptz NOT NULL DEFAULT now(),

  UNIQUE (discovery_id, user_id)
);

-- hike_tracks
CREATE TABLE public.hike_tracks (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  region_id        uuid REFERENCES public.regions(id) ON DELETE SET NULL,
  track            geometry(LineString, 4326) NOT NULL,
  distance_m       float,
  elevation_gain_m float,
  duration_s       int,
  storage_path     text,
  started_at       timestamptz NOT NULL,
  ended_at         timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- user_stats
CREATE TABLE public.user_stats (
  user_id                  uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  total_distance_m         float NOT NULL DEFAULT 0,
  total_elevation_gain_m   float NOT NULL DEFAULT 0,
  total_hike_count         int NOT NULL DEFAULT 0,
  total_discovery_count    int NOT NULL DEFAULT 0,
  total_verification_count int NOT NULL DEFAULT 0,
  current_streak_days      int NOT NULL DEFAULT 0,
  longest_streak_days      int NOT NULL DEFAULT 0,
  last_active_date         date,
  updated_at               timestamptz NOT NULL DEFAULT now()
);

-- badges
CREATE TABLE public.badges (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text NOT NULL,
  icon_url    text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- user_badges
CREATE TABLE public.user_badges (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_id   uuid NOT NULL REFERENCES public.badges(id) ON DELETE CASCADE,
  awarded_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, badge_id)
);

-- notifications
CREATE TABLE public.notifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type public.notification_event_type NOT NULL,
  title      text NOT NULL,
  body       text,
  data       jsonb NOT NULL DEFAULT '{}',
  read       boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- notification_preferences
CREATE TABLE public.notification_preferences (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type public.notification_event_type NOT NULL,
  channel    public.notification_channel NOT NULL DEFAULT 'in_app',
  enabled    boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, event_type)
);

-- field_captures
CREATE TABLE public.field_captures (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  organization_id          uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  region_id                uuid REFERENCES public.regions(id) ON DELETE SET NULL,
  area_tag                 text,
  status                   public.capture_status NOT NULL DEFAULT 'local',
  data_quality_tier        public.data_quality_tier NOT NULL DEFAULT 'community',
  gps_track                geometry(LineString, 4326),
  bounds                   geometry(Polygon, 4326),
  point_cloud_storage_path text,
  gps_track_storage_path   text,
  session_metadata         jsonb NOT NULL DEFAULT '{}',
  review_notes             text,
  reviewed_by              uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at              timestamptz,
  captured_at              timestamptz NOT NULL,
  submitted_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX regions_boundary_idx    ON public.regions     USING GIST (boundary);
CREATE INDEX regions_published_idx   ON public.regions     (published);

CREATE INDEX tile_sets_region_idx    ON public.tile_sets   (region_id, published);
CREATE INDEX tile_sets_bounds_idx    ON public.tile_sets   USING GIST (bounds);
CREATE INDEX tile_sets_quality_idx   ON public.tile_sets   (region_id, data_quality_tier, published);

CREATE INDEX import_jobs_region_idx       ON public.import_jobs (region_id);
CREATE INDEX import_jobs_status_idx       ON public.import_jobs (status);
CREATE INDEX import_jobs_started_at_idx   ON public.import_jobs (started_at) WHERE status = 'processing';

CREATE INDEX discoveries_location_idx    ON public.discoveries USING GIST (location);
CREATE INDEX discoveries_user_idx        ON public.discoveries (user_id);
CREATE INDEX discoveries_region_idx      ON public.discoveries (region_id);
CREATE INDEX discoveries_category_idx    ON public.discoveries (category);
CREATE INDEX discoveries_visibility_idx  ON public.discoveries (visibility);
CREATE INDEX discoveries_moderation_idx  ON public.discoveries (moderation_status)
  WHERE moderation_status = 'flagged';

CREATE INDEX discovery_photos_discovery_idx         ON public.discovery_photos        (discovery_id);
CREATE INDEX discovery_verifications_discovery_idx  ON public.discovery_verifications (discovery_id);
CREATE INDEX discovery_verifications_user_idx       ON public.discovery_verifications (user_id);

CREATE INDEX hike_tracks_user_idx    ON public.hike_tracks (user_id);
CREATE INDEX hike_tracks_region_idx  ON public.hike_tracks (region_id);
CREATE INDEX hike_tracks_track_idx   ON public.hike_tracks USING GIST (track);

CREATE INDEX user_badges_user_idx        ON public.user_badges (user_id);
CREATE INDEX canonical_assets_species_idx ON public.canonical_assets (identified_species);

CREATE INDEX notifications_user_idx ON public.notifications
  (user_id, read, created_at DESC);

CREATE INDEX field_captures_user_idx     ON public.field_captures (user_id);
CREATE INDEX field_captures_region_idx   ON public.field_captures (region_id);
CREATE INDEX field_captures_status_idx   ON public.field_captures (status);
CREATE INDEX field_captures_quality_idx  ON public.field_captures (data_quality_tier, status);
CREATE INDEX field_captures_gps_idx      ON public.field_captures USING GIST (gps_track);
CREATE INDEX field_captures_bounds_idx   ON public.field_captures USING GIST (bounds);

-- =============================================================================
-- Helper: current_user_role()
-- Stable function used inside RLS policies. SECURITY DEFINER so it can read
-- profiles regardless of the caller's RLS context.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- =============================================================================
-- Trigger: auto-create profile on auth.users insert
-- =============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'display_name',
      NEW.raw_user_meta_data->>'full_name',
      split_part(NEW.email, '@', 1)
    )
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
