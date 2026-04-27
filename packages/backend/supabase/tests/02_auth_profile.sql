-- =============================================================================
-- Smoke tests for Phase 1.2 — Auth + Profile Creation
--
-- Tracer bullet: auth.users insert → profiles row with role = 'community'.
--
-- Fixed UUIDs (distinct from 01_smoke.sql):
--   community user : b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11
--   admin user     : b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12
--   region creator : b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12 (same as admin)
-- =============================================================================

BEGIN;
SELECT plan(13);

-- -----------------------------------------------------------------------
-- 1. Tracer bullet: signUp → profile auto-created with role = 'community'
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'community@phase12.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{"display_name": "Phase12 Community"}',
  now(), now()
);

SELECT results_eq(
  $$SELECT count(*)::int FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11'$$,
  ARRAY[1],
  'Profile auto-created on auth.users insert'
);

SELECT results_eq(
  $$SELECT role::text FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11'$$,
  ARRAY['community'],
  'New profile has role = community'
);

-- -----------------------------------------------------------------------
-- 2. display_name: uses raw_user_meta_data->>'display_name' when present
-- -----------------------------------------------------------------------

SELECT results_eq(
  $$SELECT display_name FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11'$$,
  ARRAY['Phase12 Community'::text],
  'display_name set from raw_user_meta_data display_name'
);

-- -----------------------------------------------------------------------
-- 3. display_name: falls back to full_name when display_name absent
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b13',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'fullname@phase12.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{"full_name": "Full Name User"}',
  now(), now()
);

SELECT results_eq(
  $$SELECT display_name FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b13'$$,
  ARRAY['Full Name User'::text],
  'display_name falls back to full_name when display_name absent'
);

-- -----------------------------------------------------------------------
-- 4. display_name: falls back to email prefix when no metadata
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b14',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'emailprefix@phase12.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{}',
  now(), now()
);

SELECT results_eq(
  $$SELECT display_name FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b14'$$,
  ARRAY['emailprefix'::text],
  'display_name falls back to email prefix when no metadata'
);

-- -----------------------------------------------------------------------
-- 5. platform_admin setup: create admin user + an unpublished region
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'admin@phase12.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{"display_name": "Phase12 Admin"}',
  now(), now()
);

-- Elevate to platform_admin (superuser, bypasses RLS).
UPDATE public.profiles
   SET role = 'platform_admin'
 WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12';

-- Insert published + unpublished regions (superuser, no RLS).
INSERT INTO public.regions (name, slug, boundary, created_by, published) VALUES
  (
    'Phase12 Published',
    'phase12-published',
    ST_GeomFromText('POLYGON((-116.5 51.0, -115.5 51.0, -115.5 51.5, -116.5 51.5, -116.5 51.0))', 4326),
    'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12',
    true
  ),
  (
    'Phase12 Unpublished',
    'phase12-unpublished',
    ST_GeomFromText('POLYGON((-117.5 51.0, -116.6 51.0, -116.6 51.5, -117.5 51.5, -117.5 51.0))', 4326),
    'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12',
    false
  );

-- -----------------------------------------------------------------------
-- 6. Community user cannot see the unpublished region
-- -----------------------------------------------------------------------

SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11","role":"authenticated"}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.regions WHERE slug LIKE ''phase12%''',
  ARRAY[1],
  'Community user sees only 1 published phase12 region'
);

SELECT results_eq(
  'SELECT name FROM public.regions WHERE slug LIKE ''phase12%''',
  ARRAY['Phase12 Published'::text],
  'Community user sees only the published region by name'
);

-- -----------------------------------------------------------------------
-- 7. Manual platform_admin elevation unlocks all regions
-- -----------------------------------------------------------------------

RESET role;

UPDATE public.profiles
   SET role = 'platform_admin'
 WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11';

SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11","role":"authenticated"}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.regions WHERE slug LIKE ''phase12%''',
  ARRAY[2],
  'platform_admin sees both published and unpublished phase12 regions'
);

-- -----------------------------------------------------------------------
-- 8. platform_admin can INSERT into organizations (RLS-gated to admin only)
-- -----------------------------------------------------------------------

INSERT INTO public.organizations (name, slug, type)
VALUES ('Phase12 Org', 'phase12-org', 'other');

SELECT results_eq(
  $$SELECT count(*)::int FROM public.organizations WHERE slug = 'phase12-org'$$,
  ARRAY[1],
  'platform_admin can insert into organizations'
);

-- -----------------------------------------------------------------------
-- 9. Community user cannot INSERT into organizations
-- -----------------------------------------------------------------------

RESET role;

UPDATE public.profiles
   SET role = 'community'
 WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11';

SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11","role":"authenticated"}';

SELECT throws_ok(
  $$INSERT INTO public.organizations (name, slug, type)
    VALUES ('Community Org Attempt', 'community-org-attempt', 'other')$$,
  'new row violates row-level security policy for table "organizations"',
  'Community user cannot insert into organizations'
);

-- -----------------------------------------------------------------------
-- 10. platform_admin can see all profiles (profiles_select_all is public)
-- -----------------------------------------------------------------------

RESET role;

SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12","role":"authenticated"}';

SELECT results_eq(
  $$SELECT count(*)::int FROM public.profiles
    WHERE id IN (
      'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b11',
      'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b12',
      'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b13',
      'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b14'
    )$$,
  ARRAY[4],
  'All 4 test profiles visible (profiles_select_all policy)'
);

-- -----------------------------------------------------------------------
-- 11. OAuth providers: Google and Apple enabled in config (config-level,
--     verified by confirming their presence in auth.providers view or by
--     checking that the auth schema accepts provider = 'google').
--     We assert the trigger fires for an OAuth-style insert (no password).
-- -----------------------------------------------------------------------

RESET role;

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b15',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'google.user@phase12.local',
  '',
  now(),
  '{"provider":"google","providers":["google"]}',
  '{"full_name": "Google OAuth User"}',
  now(), now()
);

RESET role;

SELECT results_eq(
  $$SELECT count(*)::int FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b15'$$,
  ARRAY[1],
  'Profile auto-created for OAuth (Google-style) user insert'
);

SELECT results_eq(
  $$SELECT display_name FROM public.profiles
    WHERE id = 'b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380b15'$$,
  ARRAY['Google OAuth User'::text],
  'OAuth user display_name set from full_name metadata'
);

SELECT * FROM finish();
ROLLBACK;
