-- =====================================================================
--  video_upgrade.sql — يضيف فيديوهات الشرح للمحاضرات. شغّله مرة واحدة.
--  (لو لسه هتشغّل upgrade.sql لأول مرة، الجزء ده فيه خلاص)
-- =====================================================================
alter table public.lectures add column if not exists videos jsonb not null default '[]'::jsonb;
notify pgrst, 'reload schema';
