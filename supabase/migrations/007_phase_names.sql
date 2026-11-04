-- Phase cleanup (2026-11-04). 'lobby' did the same as 'defining' (students join
-- and submit definitions in both), so it is gone and sessions start in
-- 'defining'. 'rating_pre' is renamed 'ratings'. Run after 001-006.

update sessions set phase = 'defining' where phase = 'lobby';
update sessions set phase = 'ratings'  where phase = 'rating_pre';
alter table sessions alter column phase set default 'defining';
alter table sessions drop constraint if exists sessions_phase_check;
alter table sessions add constraint sessions_phase_check check (phase in
  ('defining','reading','ratings','locked',
   'standards_submit','standards_vote','final','closed'));

create or replace function submit_definition(p_token text, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v participants;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'defining') then raise exception 'Definitions are closed'; end if;
  insert into definitions (session_id, participant_id, text) values (v.session_id, v.id, trim(p_text))
  on conflict (session_id, participant_id) do update set text = excluded.text;
end $$;

create or replace function submit_rating(p_token text, p_study text, p_phase text,
  p_direction text, p_credibility int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v participants;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if p_phase <> 'pre' then raise exception 'Unknown rating phase'; end if;
  if not _phase_in(v.session_id, 'reading', 'ratings') then
    raise exception 'Ratings are locked'; end if;
  insert into ratings (session_id, participant_id, study_id, phase, direction, credibility, reason)
  values (v.session_id, v.id, p_study, p_phase, p_direction, p_credibility, nullif(trim(p_reason), ''))
  on conflict (session_id, participant_id, study_id, phase) do update
    set direction = excluded.direction, credibility = excluded.credibility, reason = excluded.reason;
end $$;
