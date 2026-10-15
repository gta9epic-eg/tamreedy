-- =====================================================================
--  fixes.sql  —  تحديثات أمان وأداء. شغّله مرة واحدة في SQL Editor
--  لو كنت شغّلت schema.sql قبل كده (آمن لو اتشغّل أكتر من مرة).
--  لازم تكون شغّلت squads.sql قبله لو الشلة مش موجودة عندك.
--  (لو لسه هتبدأ من الأول، schema.sql الجديد فيه كل ده خلاص)
-- =====================================================================

-- 1) المذاكرة المتتالية بتوقيت القاهرة (بدل UTC)
create or replace function public.my_stats()
returns table (answered_count bigint, correct_count bigint, total_points bigint, streak_days int)
language plpgsql stable security invoker set search_path = public as $$
declare
  d date := (now() at time zone 'Africa/Cairo')::date;
  n int := 0;
begin
  select count(*), count(*) filter (where a.correct)
    into answered_count, correct_count
  from public.answers a where a.user_id = auth.uid();

  total_points :=
      (select count(distinct x.question_id) from public.answers x where x.user_id = auth.uid() and x.correct) * 10
    + (select count(*) from public.studied s where s.user_id = auth.uid()) * 15;

  if not exists (select 1 from public.answers x where x.user_id = auth.uid() and (x.created_at at time zone 'Africa/Cairo')::date = d) then
    d := d - 1;
  end if;
  while exists (select 1 from public.answers x where x.user_id = auth.uid() and (x.created_at at time zone 'Africa/Cairo')::date = d) loop
    n := n + 1;
    d := d - 1;
  end loop;
  streak_days := n;
  return next;
end $$;

-- 2) اسم الطالب من التسجيل يتقص لـ 40 حرف (عشان القيود الجديدة ما توقفش التسجيل)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(left(btrim(coalesce(new.raw_user_meta_data->>'name', '')), 40), ''), 'طالب'))
  on conflict (id) do nothing;
  return new;
end $$;

-- 3) حدود منطقية للأطوال والقيم (NOT VALID: بتتطبق على أي إضافة/تعديل جديد من غير ما تفحص القديم)
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.profiles'::regclass and conname = 'profiles_name_len') then
    alter table public.profiles add constraint profiles_name_len check (char_length(name) between 1 and 40) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.profiles'::regclass and conname = 'profiles_college_len') then
    alter table public.profiles add constraint profiles_college_len check (char_length(college) <= 100) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.squad_members'::regclass and conname = 'squad_members_name_len') then
    alter table public.squad_members add constraint squad_members_name_len check (char_length(name) between 1 and 40) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.squad_sessions'::regclass and conname = 'squad_sessions_q_count') then
    alter table public.squad_sessions add constraint squad_sessions_q_count check (cardinality(question_ids) between 1 and 50) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.session_results'::regclass and conname = 'session_results_score_chk') then
    alter table public.session_results add constraint session_results_score_chk check (score <= total) not valid;
  end if;
end $$;

-- 4) فهارس للمفاتيح الأجنبية (بتسرّع المسح والاستعلامات)
create index if not exists answers_question_idx        on public.answers (question_id);
create index if not exists saved_question_idx          on public.saved_questions (question_id);
create index if not exists studied_lecture_idx         on public.studied (lecture_id);
create index if not exists squads_owner_idx            on public.squads (owner_id);
create index if not exists messages_user_idx           on public.messages (user_id);
create index if not exists squad_sessions_creator_idx  on public.squad_sessions (created_by);
create index if not exists session_results_user_idx    on public.session_results (user_id);
