-- Gosu's own request pays 500 points every 24 hours coded, not 1,000. Hours
-- already coded towards the next bonus count towards this one.

update public.coder_settings set bonus_points = 500;
