-- =============================================================================
-- Smoke tests for Phase 1.1 — Schema + RLS
--
-- Tracer bullet: a community user can only SELECT published regions.
--
-- Fixed UUIDs make the JWT claim literal static (no dynamic SET workarounds).
--   community user : a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11
--   admin user     : a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12
-- =============================================================================

BEGIN;
SELECT plan(21);

-- -----------------------------------------------------------------------
-- 1. All 17 tables exist
-- -----------------------------------------------------------------------

SELECT has_table('public', 'profiles',                 'profiles table exists');
SELECT has_table('public', 'organizations',            'organizations table exists');
SELECT has_table('public', 'organization_members',     'organization_members table exists');
SELECT has_table('public', 'regions',                  'regions table exists');
SELECT has_table('public', 'tile_sets',                'tile_sets table exists');
SELECT has_table('public', 'import_jobs',              'import_jobs table exists');
SELECT has_table('public', 'canonical_assets',         'canonical_assets table exists');
SELECT has_table('public', 'discoveries',              'discoveries table exists');
SELECT has_table('public', 'discovery_photos',         'discovery_photos table exists');
SELECT has_table('public', 'discovery_verifications',  'discovery_verifications table exists');
SELECT has_table('public', 'hike_tracks',              'hike_tracks table exists');
SELECT has_table('public', 'user_stats',               'user_stats table exists');
SELECT has_table('public', 'badges',                   'badges table exists');
SELECT has_table('public', 'user_badges',              'user_badges table exists');
SELECT has_table('public', 'notifications',            'notifications table exists');
SELECT has_table('public', 'notification_preferences', 'notification_preferences table exists');
SELECT has_table('public', 'field_captures',           'field_captures table exists');

-- -----------------------------------------------------------------------
-- 2. Profile trigger: fires on auth.users insert
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'community@test.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{"display_name": "Community Tester"}',
  now(), now()
);

SELECT results_eq(
  $$SELECT count(*)::int FROM public.profiles
    WHERE id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'$$,
  ARRAY[1],
  'Profile auto-created on auth.users insert'
);

SELECT results_eq(
  $$SELECT display_name FROM public.profiles
    WHERE id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'$$,
  ARRAY['Community Tester'::text],
  'Profile display_name populated from user metadata'
);

-- -----------------------------------------------------------------------
-- 3. RLS: community user only sees published regions
-- Set up admin + regions as postgres superuser (bypasses RLS).
-- -----------------------------------------------------------------------

INSERT INTO auth.users (
  id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) VALUES (
  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'admin@test.local',
  crypt('password', gen_salt('bf')),
  now(),
  '{"display_name": "Admin Tester"}',
  now(), now()
);

-- Elevate to platform_admin so the foreign-key constraint on regions.created_by
-- references a valid profile that also satisfies the admin RLS check later.
UPDATE public.profiles
   SET role = 'platform_admin'
 WHERE id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12';

-- Insert one published region and one unpublished region (superuser, no RLS).
INSERT INTO public.regions (name, slug, boundary, created_by, published) VALUES
  (
    'Banff National Park',
    'banff',
    ST_GeomFromText('POLYGON((-116.5 51.0, -115.5 51.0, -115.5 51.5, -116.5 51.5, -116.5 51.0))', 4326),
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12',
    true
  ),
  (
    'Unpublished Region',
    'unpublished',
    ST_GeomFromText('POLYGON((-117.5 51.0, -116.6 51.0, -116.6 51.5, -117.5 51.5, -117.5 51.0))', 4326),
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12',
    false
  );

-- Switch to authenticated role and impersonate the community user.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11","role":"authenticated"}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.regions',
  ARRAY[1],
  'Community user sees only the 1 published region'
);

SELECT results_eq(
  'SELECT name FROM public.regions',
  ARRAY['Banff National Park'::text],
  'Community user sees the correct published region by name'
);

-- Reset role so finish() can run cleanly.
RESET role;

SELECT * FROM finish();
ROLLBACK;
