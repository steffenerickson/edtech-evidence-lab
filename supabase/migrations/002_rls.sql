-- Row-level security. Students (anon role) get NO direct table access; everything
-- they do goes through the security-definer functions in 003. The instructor
-- (authenticated, email on the allow-list) can read and write their own sessions.

create or replace function is_instructor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from instructor_emails
                 where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

alter table instructor_emails      enable row level security;
alter table studies                enable row level security;
alter table study_reveals          enable row level security;
alter table sessions               enable row level security;
alter table group_assignments      enable row level security;
alter table participants           enable row level security;
alter table definitions            enable row level security;
alter table ratings                enable row level security;
alter table standard_submissions   enable row level security;
alter table standards              enable row level security;
alter table standard_votes         enable row level security;

revoke all on all tables in schema public from anon;
grant usage on schema public to anon, authenticated;
grant select on studies to anon, authenticated;   -- titles only; no reveal text here

create policy studies_instructor_all on studies for all to authenticated
  using (is_instructor()) with check (is_instructor());
create policy studies_public_read on studies for select to anon using (true);

create policy reveals_instructor_read on study_reveals for select to authenticated using (is_instructor());
create policy reveals_instructor_write on study_reveals for all to authenticated
  using (is_instructor()) with check (is_instructor());

create policy sessions_owner on sessions for all to authenticated
  using (is_instructor() and owner = auth.uid()) with check (is_instructor() and owner = auth.uid());

create policy ga_owner on group_assignments for all to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()))
  with check (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));

create policy participants_owner on participants for select to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
create policy definitions_owner on definitions for select to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
create policy ratings_owner on ratings for select to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
create policy subs_owner on standard_submissions for all to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()))
  with check (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
create policy standards_owner on standards for all to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()))
  with check (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
create policy votes_owner on standard_votes for select to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
