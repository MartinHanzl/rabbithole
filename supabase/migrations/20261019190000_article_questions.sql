-- Shared cache of ready-made challenge questions per Wikipedia article, filled by the
-- `article-questions` Edge Function (Wikidata templates, Gemini as fallback).
-- Each article is generated once for everybody, which keeps the free tiers comfortable.

create table public.article_questions (
  page_id      integer primary key check (page_id > 0),
  -- [{"question": "...", "correct": "...", "wrong": ["...", "..."], "source": "wikidata" | "generated"}]
  questions    jsonb not null default '[]'::jsonb check (jsonb_typeof(questions) = 'array'),
  generated_at timestamptz not null default now()
);

alter table public.article_questions enable row level security;
revoke all on public.article_questions from anon, authenticated;
-- No policies: only the Edge Function (service role) reads and writes the cache.
