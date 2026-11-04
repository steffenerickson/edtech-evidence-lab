-- Simplified standards step (2026-11-04). Students may propose up to three
-- standards each; there is no instructor sorting step and no separate ballot;
-- every submission is a ballot option; the class result is the five submissions
-- with the most votes, in vote order. Run after 001-005 in the SQL editor.

-- Phase 'standards_sort' is gone. Sessions parked there move on to voting.
update sessions set phase = 'standards_vote' where phase = 'standards_sort';
alter table sessions drop constraint if exists sessions_phase_check;
alter table sessions add constraint sessions_phase_check check (phase in
  ('lobby','defining','reading','rating_pre','locked',
   'standards_submit','standards_vote','final','closed'));

-- Submissions: up to three per student (enforced in submit_standard), no canonical mapping.
alter table standard_submissions drop constraint if exists standard_submissions_canonical_fk;
alter table standard_submissions drop constraint if exists standard_submissions_session_id_participant_id_key;
alter table standard_submissions drop column if exists canonical_standard_id;

-- Votes now point at submissions directly; the ballot-options table is gone.
drop table if exists standard_votes;
drop table if exists standards;
create table standard_votes (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  submission_id bigint not null references standard_submissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, submission_id)
);
alter table standard_votes enable row level security;
create policy votes_owner on standard_votes for select to authenticated
  using (is_instructor() and exists (select 1 from sessions s where s.id = session_id and s.owner = auth.uid()));
grant select, insert, update, delete on standard_votes to authenticated;
grant usage, select on sequence standard_votes_id_seq to authenticated;

drop function if exists get_ballot(text);
drop function if exists cast_votes(text, bigint[]);
drop function if exists my_votes(text);
drop function if exists get_final(text);
drop function if exists submit_standard(text, text);

create or replace function submit_standard(p_token text, p_text text)
returns json language plpgsql security definer set search_path = public as $$
declare v participants; n int; new_id bigint;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'standards_submit') then raise exception 'Standard submissions are closed'; end if;
  if char_length(trim(p_text)) = 0 then raise exception 'Write a standard first'; end if;
  select count(*) into n from standard_submissions where session_id = v.session_id and participant_id = v.id;
  if n >= 3 then raise exception 'You have already proposed three standards'; end if;
  insert into standard_submissions (session_id, participant_id, text) values (v.session_id, v.id, trim(p_text))
    returning id into new_id;
  return json_build_object('id', new_id);
end $$;

create or replace function delete_standard(p_token text, p_submission bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v participants;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'standards_submit') then raise exception 'Standard submissions are closed'; end if;
  delete from standard_submissions where id = p_submission and participant_id = v.id;
end $$;

create or replace function my_standards(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', ss.id, 'text', ss.text) order by ss.created_at), '[]'::json)
  from standard_submissions ss join participants p on p.id = ss.participant_id where p.token = p_token;
$$;

-- Every submission is on the ballot. Order is randomized per call so that early
-- submissions do not sit at the top of every phone.
create or replace function get_ballot(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', ss.id, 'text', ss.text) order by random()), '[]'::json)
  from standard_submissions ss join sessions s on s.id = ss.session_id
  where upper(s.join_code) = upper(p_join_code) and s.phase in ('standards_vote','final');
$$;

create or replace function cast_votes(p_token text, p_submission_ids bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare v participants; n_valid int;
begin
  v := _participant(p_token);
  if v.id is null then raise exception 'Unknown participant'; end if;
  if not _phase_in(v.session_id, 'standards_vote') then raise exception 'Voting is not open'; end if;
  if coalesce(array_length(p_submission_ids, 1), 0) > 5 then raise exception 'Choose at most five standards'; end if;
  select count(distinct id) into n_valid from standard_submissions
    where id = any(p_submission_ids) and session_id = v.session_id;
  if n_valid <> coalesce(array_length(p_submission_ids, 1), 0) then raise exception 'Invalid ballot option'; end if;
  delete from standard_votes where session_id = v.session_id and participant_id = v.id;
  insert into standard_votes (session_id, participant_id, submission_id)
    select distinct v.session_id, v.id, unnest(p_submission_ids);
end $$;

create or replace function my_votes(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(sv.submission_id), '[]'::json) from standard_votes sv
  join participants p on p.id = sv.participant_id where p.token = p_token;
$$;

-- The five submissions with the most votes, ranked 1..5. Ties break by earlier submission.
create or replace function get_final(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('rank', x.rank, 'id', x.id, 'text', x.text, 'votes', x.votes) order by x.rank), '[]'::json)
  from (select ss.id, ss.text, count(sv.id) votes,
               row_number() over (order by count(sv.id) desc, ss.created_at, ss.id) rank
        from standard_submissions ss
        join sessions s on s.id = ss.session_id
        left join standard_votes sv on sv.submission_id = ss.id
        where upper(s.join_code) = upper(p_join_code) and s.phase in ('final','closed')
        group by ss.id, ss.text, ss.created_at) x
  where x.rank <= 5 and x.votes > 0;
$$;

-- Results are always live on the Results page; the show_results flag is no longer consulted.
create or replace function get_results(p_join_code text)
returns json language sql stable security definer set search_path = public as $$
  with s as (select * from sessions where upper(join_code) = upper(p_join_code) and phase <> 'closed')
  select json_build_object(
    'participants', (select count(*) from participants p, s where p.session_id = s.id),
    'definitions', (select coalesce(json_agg(d.text order by d.created_at), '[]'::json) from definitions d, s where d.session_id = s.id),
    'ratings', (select coalesce(json_agg(json_build_object('study_id', study_id, 'phase', phase,
        'direction', direction, 'credibility', credibility, 'n', n)), '[]'::json)
      from (select r.study_id, r.phase, r.direction, r.credibility, count(*) n
            from ratings r, s where r.session_id = s.id group by 1,2,3,4) x),
    'standards', (select coalesce(json_agg(json_build_object('id', ss.id, 'text', ss.text, 'votes',
        (select count(*) from standard_votes v where v.submission_id = ss.id)) order by ss.created_at), '[]'::json)
      from standard_submissions ss, s where ss.session_id = s.id))
  from s;
$$;

revoke all on function submit_standard(text,text), delete_standard(text,bigint), my_standards(text),
  get_ballot(text), cast_votes(text,bigint[]), my_votes(text), get_final(text), get_results(text) from public;
grant execute on function submit_standard(text,text), delete_standard(text,bigint), my_standards(text),
  get_ballot(text), cast_votes(text,bigint[]), my_votes(text), get_final(text), get_results(text)
  to anon, authenticated;
