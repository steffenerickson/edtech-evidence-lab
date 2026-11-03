-- "Delete all sessions" on the dashboard. Deletes every session the signed-in
-- instructor owns, including closed ones the session picker hides; every
-- response table cascades from sessions. Returns the number deleted.
create or replace function purge_all_sessions()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_instructor() then raise exception 'Instructors only'; end if;
  with gone as (delete from sessions where owner = auth.uid() returning 1)
  select count(*) into n from gone;
  return n;
end $$;
revoke all on function purge_all_sessions() from public;
grant execute on function purge_all_sessions() to authenticated;
