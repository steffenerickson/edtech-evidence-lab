-- The reveal step was removed from the lesson (2026-11-03). Each study card now
-- carries its own citation and link, so the reveal table, the function that served
-- it, and the 'revealed' and 'rating_post' phases are no longer used.
-- Run after 001-003 in the SQL editor. Safe on a database that never loaded reveals.

-- Any open session parked on a removed phase moves to 'locked', the phase that
-- now precedes standards_submit.
update sessions set phase = 'locked' where phase in ('revealed', 'rating_post');

drop function if exists get_reveals(text);
drop table if exists study_reveals;

alter table sessions drop constraint if exists sessions_phase_check;
alter table sessions add constraint sessions_phase_check check (phase in
  ('lobby','defining','reading','rating_pre','locked',
   'standards_submit','standards_sort','standards_vote','final','closed'));
