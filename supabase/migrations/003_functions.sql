-- Student-facing functions. All are SECURITY DEFINER and callable by anon.
-- Each one looks up the participant by token and checks the session phase in
-- the database, so the pre-reveal lock and the five-vote cap do not depend on
-- the browser.

create or replace function _participant(p_token text)
returns participants language sql stable security definer set search_path = public as $$
  select * from participants where token = p_token;
$$;

create or replace function _phase_in(p_session uuid, variadic p_phases text[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from sessions where id = p_session and phase = any(p_phases));
$$;

-- Session state visible to students: phase, flags, and group assignments.
create or replace function get_session(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', s.id, 'join_code', s.join_code, 'phase', s.phase,
    'show_results', s.show_results,
    'groups', (select coalesce(json_object_agg(g.group_code, g.studies), '{}'::json)
               from (select group_code, json_agg(study_id order by study_id) studies
                     from group_assignments where session_id = s.id group by group_code) g))
  from sessions s where upper(s.join_code) = upper(p_join_code) and s.phase <> 'closed';
$$;

create or replace function join_session(p_join_code text, p_group text)
returns json language plpgsql security definer set search_path = public as $$
declare v_session uuid; v_p participants;
begin
  select id into v_session from sessions where upper(join_code) = upper(p_join_code) and phase <> 'closed';
  if v_session is null then raise exception 'No open session with that code'; end if;
  insert into participants (session_id, group_code) values (v_session, upper(p_group)) returning * into v_p;
  return json_build_object('token', v_p.token, 'participant_id', v_p.id, 'group_code', v_p.group_code);
end $$;

create or replace function set_group(p_token text, p_group text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update participants set group_code = upper(p_group) where token = p_token;
end $$;

create or replace function submit_definition(p_token text, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v participants;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'lobby', 'defining') then raise exception 'Definitions are closed'; end if;
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
  if p_phase = 'pre' and not _phase_in(v.session_id, 'reading', 'rating_pre') then
    raise exception 'Pre-reveal ratings are locked'; end if;
  if p_phase = 'post' and not _phase_in(v.session_id, 'rating_post') then
    raise exception 'Post-reveal ratings are not open'; end if;
  insert into ratings (session_id, participant_id, study_id, phase, direction, credibility, reason)
  values (v.session_id, v.id, p_study, p_phase, p_direction, p_credibility, nullif(trim(p_reason), ''))
  on conflict (session_id, participant_id, study_id, phase) do update
    set direction = excluded.direction, credibility = excluded.credibility, reason = excluded.reason;
end $$;

create or replace function my_ratings(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('study_id', r.study_id, 'phase', r.phase,
    'direction', r.direction, 'credibility', r.credibility, 'reason', r.reason)), '[]'::json)
  from ratings r join participants p on p.id = r.participant_id where p.token = p_token;
$$;

-- Reveal data: returned only once the instructor has moved the session past 'locked'.
create or replace function get_reveals(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('study_id', r.study_id, 'citation', r.citation, 'url', r.url,
    'authors', r.authors, 'affiliations', r.affiliations, 'funding', r.funding,
    'relationships', r.relationships, 'disclosure_quote', r.disclosure_quote) order by st.display_order), '[]'::json)
  from study_reveals r join studies st on st.id = r.study_id
  where exists (select 1 from sessions s where upper(s.join_code) = upper(p_join_code)
    and s.phase in ('revealed','rating_post','standards_submit','standards_sort','standards_vote','final'));
$$;

-- Aggregates only (no reasons, no participant ids). Students see them when show_results is on.
create or replace function get_results(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  with s as (select * from sessions where upper(join_code) = upper(p_join_code) and show_results)
  select json_build_object(
    'participants', (select count(*) from participants p, s where p.session_id = s.id),
    'definitions', (select coalesce(json_agg(d.text order by d.created_at), '[]'::json) from definitions d, s where d.session_id = s.id),
    'ratings', (select coalesce(json_agg(json_build_object('study_id', study_id, 'phase', phase,
        'direction', direction, 'credibility', credibility, 'n', n)), '[]'::json)
      from (select r.study_id, r.phase, r.direction, r.credibility, count(*) n
            from ratings r, s where r.session_id = s.id group by 1,2,3,4) x),
    'standards', (select coalesce(json_agg(json_build_object('id', id, 'label', label, 'scope', scope,
        'is_ballot_option', is_ballot_option, 'is_winner', is_winner, 'votes',
        (select count(*) from standard_votes v where v.standard_id = st.id)) order by sort_order, id), '[]'::json)
      from standards st, s where st.session_id = s.id))
  from s;
$$;

create or replace function submit_standard(p_token text, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v participants;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'standards_submit') then raise exception 'Standard submissions are closed'; end if;
  insert into standard_submissions (session_id, participant_id, text) values (v.session_id, v.id, trim(p_text))
  on conflict (session_id, participant_id) do update set text = excluded.text;
end $$;

create or replace function get_ballot(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', st.id, 'label', st.label, 'scope', st.scope) order by st.sort_order, st.id), '[]'::json)
  from standards st join sessions s on s.id = st.session_id
  where upper(s.join_code) = upper(p_join_code) and st.is_ballot_option
    and s.phase in ('standards_vote','final');
$$;

create or replace function cast_votes(p_token text, p_standard_ids bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare v participants; n_valid int;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'standards_vote') then raise exception 'Voting is not open'; end if;
  if coalesce(array_length(p_standard_ids, 1), 0) > 5 then raise exception 'Choose at most five standards'; end if;
  select count(*) into n_valid from standards
    where id = any(p_standard_ids) and session_id = v.session_id and is_ballot_option;
  if n_valid <> coalesce(array_length(p_standard_ids, 1), 0) then raise exception 'Invalid ballot option'; end if;
  delete from standard_votes where session_id = v.session_id and participant_id = v.id;
  insert into standard_votes (session_id, participant_id, standard_id)
    select v.session_id, v.id, unnest(p_standard_ids);
end $$;

create or replace function my_votes(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(sv.standard_id), '[]'::json) from standard_votes sv
  join participants p on p.id = sv.participant_id where p.token = p_token;
$$;

create or replace function get_final(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', st.id, 'label', st.label, 'scope', st.scope) order by st.sort_order, st.id), '[]'::json)
  from standards st join sessions s on s.id = st.session_id
  where upper(s.join_code) = upper(p_join_code) and st.is_winner and s.phase in ('final','closed');
$$;

-- Instructor-only helpers (run as the authenticated owner).
create or replace function purge_session(p_session uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from sessions where id = p_session and owner = auth.uid()) then
    raise exception 'Not your session'; end if;
  delete from sessions where id = p_session;   -- cascades to all response tables
end $$;

revoke all on function get_session(text), join_session(text,text), set_group(text,text), submit_definition(text,text),
  submit_rating(text,text,text,text,int,text), my_ratings(text), get_reveals(text), get_results(text),
  submit_standard(text,text), get_ballot(text), cast_votes(text,bigint[]), my_votes(text), get_final(text) from public;
grant execute on function get_session(text), join_session(text,text), set_group(text,text), submit_definition(text,text),
  submit_rating(text,text,text,text,int,text), my_ratings(text), get_reveals(text), get_results(text),
  submit_standard(text,text), get_ballot(text), cast_votes(text,bigint[]), my_votes(text), get_final(text)
  to anon, authenticated;
revoke all on function purge_session(uuid), _participant(text), _phase_in(uuid, text[]) from public;
grant execute on function purge_session(uuid) to authenticated;
