-- edtech-evidence-lab: schema. Run in the Supabase SQL editor (or supabase db push).
create extension if not exists pgcrypto with schema extensions;

create table if not exists instructor_emails (
  email text primary key
);
insert into instructor_emails (email) values ('cns8vg@virginia.edu') on conflict do nothing;

create table if not exists studies (
  id text primary key,                 -- s01 .. s10, n01 (news item)
  display_order int not null,
  public_title text not null
);

create table if not exists study_reveals (
  study_id text primary key references studies(id) on delete cascade,
  citation text not null,
  url text,
  authors text,
  affiliations text,
  funding text,
  relationships text,
  disclosure_quote text
);

create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  join_code text not null unique,
  owner uuid not null references auth.users(id),
  phase text not null default 'lobby' check (phase in
    ('lobby','defining','reading','rating_pre','locked','revealed','rating_post',
     'standards_submit','standards_sort','standards_vote','final','closed')),
  show_results boolean not null default false,
  show_reasons boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists group_assignments (
  session_id uuid references sessions(id) on delete cascade,
  group_code text not null,
  study_id text references studies(id),
  primary key (session_id, group_code, study_id)
);

create table if not exists participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  group_code text,
  token text not null unique default encode(extensions.gen_random_bytes(16), 'hex'),
  created_at timestamptz not null default now()
);

create table if not exists definitions (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  text text not null check (char_length(text) <= 400),
  created_at timestamptz not null default now(),
  unique (session_id, participant_id)
);

create table if not exists ratings (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  study_id text not null references studies(id),
  phase text not null check (phase in ('pre','post')),
  direction text check (direction in ('positive','negative','mixed','null','inconclusive')),
  credibility int not null check (credibility between 1 and 5),
  reason text check (char_length(reason) <= 600),
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, study_id, phase)
);

create table if not exists standard_submissions (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  text text not null check (char_length(text) <= 400),
  canonical_standard_id bigint,
  created_at timestamptz not null default now(),
  unique (session_id, participant_id)
);

create table if not exists standards (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  label text not null,
  scope text check (scope in ('study','evidence_base')),
  is_ballot_option boolean not null default false,
  is_winner boolean not null default false,
  sort_order int not null default 0
);
alter table standard_submissions
  drop constraint if exists standard_submissions_canonical_fk,
  add constraint standard_submissions_canonical_fk
  foreign key (canonical_standard_id) references standards(id) on delete set null;

create table if not exists standard_votes (
  id bigserial primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  participant_id uuid not null references participants(id) on delete cascade,
  standard_id bigint not null references standards(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, standard_id)
);

create index if not exists ratings_session_idx on ratings(session_id, study_id, phase);
create index if not exists participants_session_idx on participants(session_id);
