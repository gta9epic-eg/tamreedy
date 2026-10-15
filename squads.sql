-- =====================================================================
--  squads.sql — شغّله مرة واحدة لو كنت شغّلت schema.sql قبل إضافة الشلة
--  (لو لسه هتبدأ من الأول، schema.sql الجديد فيه الجزء ده خلاص)
-- =====================================================================
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
  name      text not null default 'طالب',
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
  question_ids uuid[] not null,
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
  primary key (session_id, user_id)
);

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
