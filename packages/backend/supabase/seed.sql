-- =============================================================================
-- Seed: badge catalog
-- Seeded once; never deleted by application logic.
-- =============================================================================

INSERT INTO public.badges (slug, name, description) VALUES
  -- Discovery milestones
  ('first_discovery',        'First Discovery',          'Logged your first discovery.'),
  ('ten_discoveries',        'Ten Discoveries',          'Logged 10 discoveries.'),
  ('fifty_discoveries',      'Fifty Discoveries',        'Logged 50 discoveries.'),
  ('century_explorer',       'Century Explorer',         'Logged 100 discoveries.'),

  -- Verification milestones
  ('first_verification',     'First Verification',       'Confirmed your first community discovery.'),
  ('trusted_verifier',       'Trusted Verifier',         'Confirmed 50 community discoveries.'),

  -- Streak badges
  ('seven_day_streak',       '7-Day Streak',             'Logged discoveries 7 days in a row.'),
  ('thirty_day_streak',      '30-Day Streak',            'Logged discoveries 30 days in a row.'),

  -- Category badges
  ('flora_finder',           'Flora Finder',             'Discovered 10 plant species.'),
  ('fauna_finder',           'Fauna Finder',             'Discovered 10 animal species.'),
  ('fungi_finder',           'Fungi Finder',             'Discovered 10 fungal species.'),
  ('landmark_spotter',       'Landmark Spotter',         'Discovered 10 landmarks.'),
  ('trail_reporter',         'Trail Reporter',           'Logged 10 trail condition reports.'),
  ('geologist',              'Geologist',                'Discovered 10 geological features.'),

  -- Regional badges
  ('region_pioneer',         'Region Pioneer',           'First to log a discovery in a region.'),
  ('region_contributor',     'Region Contributor',       'Reached 10% completion in a region.'),
  ('region_champion',        'Region Champion',          'Reached 50% completion in a region.'),

  -- Lab access
  ('lab_access',             'Pathfinder Lab Access',    'Earned access to Pathfinder Lab by reaching 100 verified discoveries.')
ON CONFLICT (slug) DO NOTHING;
