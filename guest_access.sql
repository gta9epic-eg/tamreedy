-- =====================================================================
--  guest_access.sql  —  شغّله مرة واحدة لو كنت شغلت schema.sql القديم قبل كده
--  بيخلي أي زائر يتفرج على المواد والمحاضرات من غير حساب.
--  الأسئلة تفضل للمسجلين بس.
-- =====================================================================
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

