-- =====================================================================
--  schema.sql  —  شغّله مرة واحدة في Supabase: SQL Editor > New query > Run
-- =====================================================================

-- ---------- الجداول ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default 'طالب' check (char_length(name) between 1 and 40),
  college    text check (char_length(college) <= 100),
  year       smallint check (year between 1 and 4),
  term       smallint check (term in (1, 2)),
  created_at timestamptz not null default now()
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.subjects (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  year       smallint not null check (year between 1 and 4),
  term       smallint not null check (term in (1, 2)),
  icon       text not null default 'book',
  created_at timestamptz not null default now()
);

create table if not exists public.lectures (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid not null references public.subjects(id) on delete cascade,
  title        text not null,
  lecture_date date not null default current_date,
  explained    boolean not null default true,
  summary      text[] not null default '{}',
  created_at   timestamptz not null default now()
);

create table if not exists public.questions (
  id          uuid primary key default gen_random_uuid(),
  lecture_id  uuid not null references public.lectures(id) on delete cascade,
  body        text not null,
  options     jsonb not null,
  answer      smallint not null check (answer >= 0),
  explanation text not null default '',
  created_at  timestamptz not null default now()
);

create table if not exists public.answers (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  correct     boolean not null,
  created_at  timestamptz not null default now()
);
create index if not exists answers_user_idx on public.answers (user_id, created_at desc);

create table if not exists public.saved_questions (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  primary key (user_id, question_id)
);

create table if not exists public.studied (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  lecture_id uuid not null references public.lectures(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, lecture_id)
);

create index if not exists lectures_subject_idx on public.lectures (subject_id);
create index if not exists questions_lecture_idx on public.questions (lecture_id);
-- فهارس للمفاتيح الأجنبية (بتسرّع مسح المواد والمحاضرات والأسئلة)
create index if not exists answers_question_idx on public.answers (question_id);
create index if not exists saved_question_idx on public.saved_questions (question_id);
create index if not exists studied_lecture_idx on public.studied (lecture_id);

-- ---------- إنشاء ملف الطالب تلقائيا عند التسجيل ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(left(btrim(coalesce(new.raw_user_meta_data->>'name', '')), 40), ''), 'طالب'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- هل المستخدم أدمن؟ ----------
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- الأمان (Row Level Security) ----------
alter table public.profiles        enable row level security;
alter table public.admins          enable row level security;
alter table public.subjects        enable row level security;
alter table public.lectures        enable row level security;
alter table public.questions       enable row level security;
alter table public.answers         enable row level security;
alter table public.saved_questions enable row level security;
alter table public.studied         enable row level security;

-- الملف الشخصي: كل طالب يشوف ويعدل بياناته بس
drop policy if exists "profiles read own"   on public.profiles;
drop policy if exists "profiles insert own" on public.profiles;
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles read own"   on public.profiles for select to authenticated using (id = auth.uid());
create policy "profiles insert own" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles update own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- الأدمن: المستخدم يقدر يعرف هو أدمن ولا لأ (والإضافة بتتم من SQL Editor بس)
drop policy if exists "admins read own" on public.admins;
create policy "admins read own" on public.admins for select to authenticated using (user_id = auth.uid());

-- المحتوى: المواد والمحاضرات يتشافوا من أي زائر (من غير حساب)،
-- والأسئلة للمسجلين بس، والأدمن بس اللي يضيف ويعدل ويمسح
do $$
declare t text; r text;
begin
  foreach t in array array['subjects', 'lectures', 'questions'] loop
    r := case when t = 'questions' then 'authenticated' else 'anon, authenticated' end;
    execute format('drop policy if exists "%1$s read" on public.%1$s', t);
    execute format('drop policy if exists "%1$s admin write" on public.%1$s', t);
    execute format('create policy "%1$s read" on public.%1$s for select to %2$s using (true)', t, r);
    execute format('create policy "%1$s admin write" on public.%1$s for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- تقدم الطالب: خاص بيه هو بس
drop policy if exists "answers read own"   on public.answers;
drop policy if exists "answers insert own" on public.answers;
create policy "answers read own"   on public.answers for select to authenticated using (user_id = auth.uid());
create policy "answers insert own" on public.answers for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "saved read own"   on public.saved_questions;
drop policy if exists "saved insert own" on public.saved_questions;
drop policy if exists "saved delete own" on public.saved_questions;
create policy "saved read own"   on public.saved_questions for select to authenticated using (user_id = auth.uid());
create policy "saved insert own" on public.saved_questions for insert to authenticated with check (user_id = auth.uid());
create policy "saved delete own" on public.saved_questions for delete to authenticated using (user_id = auth.uid());

drop policy if exists "studied read own"   on public.studied;
drop policy if exists "studied insert own" on public.studied;
create policy "studied read own"   on public.studied for select to authenticated using (user_id = auth.uid());
create policy "studied insert own" on public.studied for insert to authenticated with check (user_id = auth.uid());

-- ---------- بنك الأخطاء: آخر إجابة لكل سؤال ----------
create or replace view public.my_mistakes with (security_invoker = true) as
  select distinct on (a.question_id) a.question_id, a.correct
  from public.answers a
  where a.user_id = auth.uid()
  order by a.question_id, a.created_at desc, a.id desc;

-- ---------- إحصائيات الطالب ----------
-- المذاكرة المتتالية بتتحسب بتوقيت القاهرة
-- النقاط: 10 لكل سؤال اتجاوب صح (مرة واحدة لكل سؤال) + 15 لكل محاضرة اتذاكرت
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

-- ---------- لوحة الأوائل ----------
create or replace function public.leaderboard(lim int default 20)
returns table (name text, points bigint, is_me boolean)
language sql stable security definer set search_path = public as $$
  select p.name,
         (coalesce(a.c, 0) * 10 + coalesce(s.c, 0) * 15)::bigint as points,
         (p.id = auth.uid()) as is_me
  from public.profiles p
  left join (select user_id, count(distinct question_id) c from public.answers where correct group by user_id) a on a.user_id = p.id
  left join (select user_id, count(*) c from public.studied group by user_id) s on s.user_id = p.id
  order by points desc, p.created_at
  limit least(greatest(lim, 1), 100);
$$;

-- الدوال تتنفذ من المسجلين بس
revoke execute on function public.leaderboard(int) from public, anon;
revoke execute on function public.my_stats()       from public, anon;
revoke execute on function public.is_admin()       from public, anon;
grant  execute on function public.leaderboard(int) to authenticated;
grant  execute on function public.my_stats()       to authenticated;
grant  execute on function public.is_admin()       to authenticated;

-- =====================================================================
--  الشلة: أصحاب، جلسات حل جماعي، وشات
-- =====================================================================
create table if not exists public.squads (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 2 and 40),
  code       text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.squad_members (
  squad_id  uuid not null references public.squads(id) on delete cascade,
  user_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name      text not null default 'طالب' check (char_length(name) between 1 and 40),
  joined_at timestamptz not null default now(),
  primary key (squad_id, user_id)
);
create index if not exists squad_members_user_idx on public.squad_members (user_id);

create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  squad_id   uuid not null references public.squads(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null default 'طالب',
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists messages_squad_idx on public.messages (squad_id, id desc);

create table if not exists public.squad_sessions (
  id           uuid primary key default gen_random_uuid(),
  squad_id     uuid not null references public.squads(id) on delete cascade,
  title        text not null,
  question_ids uuid[] not null check (cardinality(question_ids) between 1 and 50),
  created_by   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now()
);
create index if not exists squad_sessions_squad_idx on public.squad_sessions (squad_id, created_at desc);

create table if not exists public.session_results (
  session_id  uuid not null references public.squad_sessions(id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  score       int not null check (score >= 0),
  total       int not null check (total > 0),
  finished_at timestamptz not null default now(),
  primary key (session_id, user_id),
  check (score <= total)
);

create index if not exists squads_owner_idx on public.squads (owner_id);
create index if not exists messages_user_idx on public.messages (user_id);
create index if not exists squad_sessions_creator_idx on public.squad_sessions (created_by);
create index if not exists session_results_user_idx on public.session_results (user_id);

-- دوال مساعدة للصلاحيات
create or replace function public.is_squad_member(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.squad_members where squad_id = sid and user_id = auth.uid());
$$;

create or replace function public.is_session_member(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.squad_sessions s
    join public.squad_members m on m.squad_id = s.squad_id
    where s.id = sid and m.user_id = auth.uid());
$$;

-- اسم المرسل في الشات بيتحدد من السيرفر (مش من الطالب)
create or replace function public.set_message_name()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  select m.name into new.name from public.squad_members m where m.squad_id = new.squad_id and m.user_id = auth.uid();
  if new.name is null then new.name := 'طالب'; end if;
  return new;
end $$;
drop trigger if exists messages_set_name on public.messages;
create trigger messages_set_name before insert on public.messages
  for each row execute function public.set_message_name();

-- إنشاء شلة / انضمام بكود / خروج
create or replace function public.create_squad(p_name text)
returns public.squads language plpgsql security definer set search_path = public as $$
declare s public.squads; nm text; tries int := 0;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  p_name := btrim(coalesce(p_name, ''));
  if char_length(p_name) < 2 or char_length(p_name) > 40 then raise exception 'invalid_name'; end if;
  if (select count(*) from public.squads where owner_id = auth.uid()) >= 10 then raise exception 'too_many_squads'; end if;
  select p.name into nm from public.profiles p where p.id = auth.uid();
  loop
    begin
      insert into public.squads (name, owner_id) values (p_name, auth.uid()) returning * into s;
      exit;
    exception when unique_violation then
      tries := tries + 1;
      if tries > 5 then raise; end if;
    end;
  end loop;
  insert into public.squad_members (squad_id, user_id, name) values (s.id, auth.uid(), coalesce(nm, 'طالب'));
  return s;
end $$;

create or replace function public.join_squad(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid; nm text; cnt int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select id into sid from public.squads where code = upper(btrim(coalesce(p_code, '')));
  if sid is null then raise exception 'invalid_code'; end if;
  select count(*) into cnt from public.squad_members where squad_id = sid;
  if cnt >= 30 and not exists (select 1 from public.squad_members where squad_id = sid and user_id = auth.uid()) then
    raise exception 'squad_full';
  end if;
  select p.name into nm from public.profiles p where p.id = auth.uid();
  insert into public.squad_members (squad_id, user_id, name) values (sid, auth.uid(), coalesce(nm, 'طالب'))
  on conflict do nothing;
  return sid;
end $$;

create or replace function public.leave_squad(p_squad uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.squad_members where squad_id = p_squad and user_id = auth.uid();
  if not exists (select 1 from public.squad_members where squad_id = p_squad) then
    delete from public.squads where id = p_squad;
  end if;
end $$;

-- الأمان
alter table public.squads          enable row level security;
alter table public.squad_members   enable row level security;
alter table public.messages        enable row level security;
alter table public.squad_sessions  enable row level security;
alter table public.session_results enable row level security;

drop policy if exists "squads read member"   on public.squads;
drop policy if exists "squads delete owner"  on public.squads;
create policy "squads read member"  on public.squads for select to authenticated using (public.is_squad_member(id));
create policy "squads delete owner" on public.squads for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "members read"        on public.squad_members;
drop policy if exists "members update own"  on public.squad_members;
create policy "members read"       on public.squad_members for select to authenticated using (public.is_squad_member(squad_id));
create policy "members update own" on public.squad_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- العضو يقدر يغير اسمه بس (مش الشلة اللي هو فيها)
revoke update on public.squad_members from authenticated;
grant  update (name) on public.squad_members to authenticated;

drop policy if exists "messages read"   on public.messages;
drop policy if exists "messages insert" on public.messages;
create policy "messages read"   on public.messages for select to authenticated using (public.is_squad_member(squad_id));
create policy "messages insert" on public.messages for insert to authenticated with check (public.is_squad_member(squad_id) and user_id = auth.uid());

drop policy if exists "sessions read"   on public.squad_sessions;
drop policy if exists "sessions insert" on public.squad_sessions;
create policy "sessions read"   on public.squad_sessions for select to authenticated using (public.is_squad_member(squad_id));
create policy "sessions insert" on public.squad_sessions for insert to authenticated with check (public.is_squad_member(squad_id) and created_by = auth.uid());

drop policy if exists "results read"   on public.session_results;
drop policy if exists "results insert" on public.session_results;
drop policy if exists "results update" on public.session_results;
create policy "results read"   on public.session_results for select to authenticated using (public.is_session_member(session_id));
create policy "results insert" on public.session_results for insert to authenticated with check (user_id = auth.uid() and public.is_session_member(session_id));
create policy "results update" on public.session_results for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_session_member(session_id));

revoke execute on function public.is_squad_member(uuid)   from public, anon;
revoke execute on function public.is_session_member(uuid) from public, anon;
revoke execute on function public.create_squad(text)      from public, anon;
revoke execute on function public.join_squad(text)        from public, anon;
revoke execute on function public.leave_squad(uuid)       from public, anon;
grant  execute on function public.is_squad_member(uuid)   to authenticated;
grant  execute on function public.is_session_member(uuid) to authenticated;
grant  execute on function public.create_squad(text)      to authenticated;
grant  execute on function public.join_squad(text)        to authenticated;
grant  execute on function public.leave_squad(uuid)       to authenticated;

-- الشات والنتايج لحظيا (Realtime). لو فشل، الموقع بيحدّث نفسه كل 10 ثواني
do $$
begin
  begin alter publication supabase_realtime add table public.messages;        exception when others then null; end;
  begin alter publication supabase_realtime add table public.squad_sessions;  exception when others then null; end;
  begin alter publication supabase_realtime add table public.session_results; exception when others then null; end;
end $$;
