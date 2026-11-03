# edtech-evidence-lab

Classroom website and polling app for a data-ethics lesson, "Evaluating Evidence on Education Technology." Students read nine study summaries with their sources, rate direction and credibility, discuss, and vote on five evidence standards. Quarto site on GitHub Pages; Supabase for live responses.

## Layout

- `content/studies_public.yml`: the nine cards plus one news item, each with the same four sections (what was studied, how, what was found, who produced it) followed by the citation and link.
- `content/sources_verified.yml`: what was checked, where, and figure licences.
- `supabase/migrations/`: schema, row-level security, and the functions students call. Students (anon key) have no direct table access; every write goes through a function that checks the session phase in the database.
- `js/`, `*.qmd`: student pages and instructor dashboard.
- `slides/`: lesson deck source (`drafts/`), build (`code/build_slides.py`), output.
- `instructor/run_of_show.md`: one-page timing and dashboard sequence.

## Setup (one time)

1. Supabase: create a project; in the SQL editor run `001_schema.sql`, `002_rls.sql`, `003_functions.sql`, `004_drop_reveals.sql` in order. In Authentication, add a user for the instructor email listed in `instructor_emails`.
2. `SUPABASE_SERVICE_KEY=... python3 supabase/seed/load_studies.py` from this folder (needs `pyyaml`).
3. Push to `main`; the GitHub Action renders and publishes to the `gh-pages` branch. In repo Settings, Pages, set the source to `gh-pages`.
4. Local preview: `quarto preview` (needs `pyyaml` and `pandoc`).

## Privacy

No names or emails are collected from students. Each student gets a random token in their browser. Aggregates only are shown to students; written reasons appear only on the instructor dashboard and only when toggled on. Delete the session (dashboard, "Delete this session") within 30 days of class. Classroom use only; any research use needs IRB review first.

## Security checks before class

Pre ratings rejected after `locked`; six votes rejected. On an existing project, run `004_drop_reveals.sql` once to remove the old reveal table, function, and phases.
