-- =============================================================================
-- Row-Level Security
-- Enable RLS on every table, then add policies.
-- =============================================================================

ALTER TABLE public.profiles                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tile_sets                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_jobs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canonical_assets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discoveries              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_photos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_verifications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hike_tracks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_stats               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_captures           ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- profiles
-- =============================================================================

-- Anyone (including anon) can read any profile (display name, avatar, etc.)
CREATE POLICY "profiles_select_all"
  ON public.profiles FOR SELECT
  USING (true);

-- Users can only update their own profile row.
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- =============================================================================
-- organizations
-- =============================================================================

-- Any authenticated user can read organizations.
CREATE POLICY "organizations_select_authenticated"
  ON public.organizations FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Only platform_admin can write.
CREATE POLICY "organizations_insert_admin"
  ON public.organizations FOR INSERT
  WITH CHECK (public.current_user_role() = 'platform_admin');

CREATE POLICY "organizations_update_admin"
  ON public.organizations FOR UPDATE
  USING (public.current_user_role() = 'platform_admin');

CREATE POLICY "organizations_delete_admin"
  ON public.organizations FOR DELETE
  USING (public.current_user_role() = 'platform_admin');

-- =============================================================================
-- organization_members
-- =============================================================================

-- Org members see their own org's roster; platform_admin sees all.
CREATE POLICY "org_members_select"
  ON public.organization_members FOR SELECT
  USING (
    public.current_user_role() = 'platform_admin'
    OR organization_id IN (
      SELECT om.organization_id
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
    )
  );

-- Org_admin can manage their own org's members; platform_admin can manage all.
CREATE POLICY "org_members_insert"
  ON public.organization_members FOR INSERT
  WITH CHECK (
    public.current_user_role() = 'platform_admin'
    OR organization_id IN (
      SELECT om.organization_id
      FROM public.organization_members om
      WHERE om.user_id = auth.uid() AND om.role = 'org_admin'
    )
  );

CREATE POLICY "org_members_delete"
  ON public.organization_members FOR DELETE
  USING (
    public.current_user_role() = 'platform_admin'
    OR organization_id IN (
      SELECT om.organization_id
      FROM public.organization_members om
      WHERE om.user_id = auth.uid() AND om.role = 'org_admin'
    )
  );

-- =============================================================================
-- regions
-- =============================================================================

-- Unauthenticated and community users see only published regions.
-- platform_admin sees all.
CREATE POLICY "regions_select"
  ON public.regions FOR SELECT
  USING (
    published = true
    OR public.current_user_role() = 'platform_admin'
  );

CREATE POLICY "regions_insert_admin"
  ON public.regions FOR INSERT
  WITH CHECK (public.current_user_role() = 'platform_admin');

CREATE POLICY "regions_update_admin"
  ON public.regions FOR UPDATE
  USING (public.current_user_role() = 'platform_admin');

CREATE POLICY "regions_delete_admin"
  ON public.regions FOR DELETE
  USING (public.current_user_role() = 'platform_admin');

-- =============================================================================
-- tile_sets
-- =============================================================================

CREATE POLICY "tile_sets_select"
  ON public.tile_sets FOR SELECT
  USING (
    published = true
    OR public.current_user_role() = 'platform_admin'
  );

CREATE POLICY "tile_sets_insert_admin"
  ON public.tile_sets FOR INSERT
  WITH CHECK (public.current_user_role() = 'platform_admin');

CREATE POLICY "tile_sets_update_admin"
  ON public.tile_sets FOR UPDATE
  USING (public.current_user_role() = 'platform_admin');

CREATE POLICY "tile_sets_delete_admin"
  ON public.tile_sets FOR DELETE
  USING (public.current_user_role() = 'platform_admin');

-- =============================================================================
-- import_jobs
-- =============================================================================

CREATE POLICY "import_jobs_admin"
  ON public.import_jobs FOR ALL
  USING (public.current_user_role() = 'platform_admin')
  WITH CHECK (public.current_user_role() = 'platform_admin');

-- =============================================================================
-- canonical_assets
-- =============================================================================

-- Assets are public; writes are via service role (Meshy job runner).
CREATE POLICY "canonical_assets_select"
  ON public.canonical_assets FOR SELECT
  USING (true);

-- =============================================================================
-- discoveries
-- =============================================================================

-- Users see their own discoveries (any visibility) plus all approved public ones.
CREATE POLICY "discoveries_select"
  ON public.discoveries FOR SELECT
  USING (
    user_id = auth.uid()
    OR (visibility = 'public' AND moderation_status = 'approved')
  );

-- Authenticated users can only insert their own records.
CREATE POLICY "discoveries_insert_own"
  ON public.discoveries FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

-- Users can update their own; platform_admin can update any (e.g. moderation_status).
CREATE POLICY "discoveries_update"
  ON public.discoveries FOR UPDATE
  USING (
    user_id = auth.uid()
    OR public.current_user_role() = 'platform_admin'
  );

CREATE POLICY "discoveries_delete"
  ON public.discoveries FOR DELETE
  USING (
    user_id = auth.uid()
    OR public.current_user_role() = 'platform_admin'
  );

-- =============================================================================
-- discovery_photos
-- =============================================================================

-- Mirrors discoveries visibility: readable if the parent discovery is readable.
CREATE POLICY "discovery_photos_select"
  ON public.discovery_photos FOR SELECT
  USING (
    discovery_id IN (
      SELECT id FROM public.discoveries
      WHERE user_id = auth.uid()
         OR (visibility = 'public' AND moderation_status = 'approved')
    )
  );

CREATE POLICY "discovery_photos_insert_own"
  ON public.discovery_photos FOR INSERT
  WITH CHECK (
    discovery_id IN (
      SELECT id FROM public.discoveries WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "discovery_photos_delete_own"
  ON public.discovery_photos FOR DELETE
  USING (
    discovery_id IN (
      SELECT id FROM public.discoveries WHERE user_id = auth.uid()
    )
  );

-- =============================================================================
-- discovery_verifications
-- =============================================================================

-- Anyone can read verification data (counts are public).
CREATE POLICY "discovery_verifications_select"
  ON public.discovery_verifications FOR SELECT
  USING (true);

-- Authenticated users can verify; cannot verify their own discoveries.
CREATE POLICY "discovery_verifications_insert"
  ON public.discovery_verifications FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_id = auth.uid()
    AND discovery_id NOT IN (
      SELECT id FROM public.discoveries WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "discovery_verifications_delete_own"
  ON public.discovery_verifications FOR DELETE
  USING (user_id = auth.uid());

-- =============================================================================
-- hike_tracks
-- =============================================================================

CREATE POLICY "hike_tracks_own"
  ON public.hike_tracks FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- user_stats
-- =============================================================================

-- Users can read their own stats; writes are via SECURITY DEFINER triggers.
CREATE POLICY "user_stats_select_own"
  ON public.user_stats FOR SELECT
  USING (user_id = auth.uid());

-- =============================================================================
-- badges
-- =============================================================================

-- Badge catalog is public; seeded by the platform, no authenticated writes.
CREATE POLICY "badges_select_all"
  ON public.badges FOR SELECT
  USING (true);

-- =============================================================================
-- user_badges
-- =============================================================================

-- Users can read their own badge awards.
CREATE POLICY "user_badges_select_own"
  ON public.user_badges FOR SELECT
  USING (user_id = auth.uid());

-- =============================================================================
-- notifications
-- =============================================================================

-- Users read and mark their own notifications.
CREATE POLICY "notifications_select_own"
  ON public.notifications FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "notifications_update_own"
  ON public.notifications FOR UPDATE
  USING (user_id = auth.uid());

-- INSERT is via SECURITY DEFINER functions / service role only.

-- =============================================================================
-- notification_preferences
-- =============================================================================

CREATE POLICY "notification_preferences_own"
  ON public.notification_preferences FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- field_captures
-- =============================================================================

-- Users see own captures; org_admin sees their org's; platform_admin sees all.
CREATE POLICY "field_captures_select"
  ON public.field_captures FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.current_user_role() = 'platform_admin'
    OR (
      organization_id IS NOT NULL
      AND organization_id IN (
        SELECT om.organization_id
        FROM public.organization_members om
        WHERE om.user_id = auth.uid() AND om.role = 'org_admin'
      )
    )
  );

-- authorized_mapper, any org member, or platform_admin can insert.
CREATE POLICY "field_captures_insert"
  ON public.field_captures FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_id = auth.uid()
    AND (
      public.current_user_role() IN ('authorized_mapper', 'platform_admin')
      OR auth.uid() IN (SELECT user_id FROM public.organization_members)
    )
  );

-- Users can update their own captures while still local; platform_admin can update any.
CREATE POLICY "field_captures_update"
  ON public.field_captures FOR UPDATE
  USING (
    (user_id = auth.uid() AND status = 'local')
    OR public.current_user_role() = 'platform_admin'
  );

-- Users can delete their own local captures; platform_admin can delete any.
CREATE POLICY "field_captures_delete"
  ON public.field_captures FOR DELETE
  USING (
    (user_id = auth.uid() AND status = 'local')
    OR public.current_user_role() = 'platform_admin'
  );
