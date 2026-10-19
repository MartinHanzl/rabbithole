-- Support for the `search-assist` Edge Function (Gemini turns questions into search terms).
-- Only the function (service role) touches these tables.

-- Same question → same terms, for everybody: Gemini is asked once per distinct query.
create table public.search_terms_cache (
  query      text primary key check (char_length(query) between 1 and 200),
  wikipedia  text not null check (char_length(wikipedia) between 1 and 100),
  youtube    text not null check (char_length(youtube) between 1 and 100),
  created_at timestamptz not null default now()
);

-- Fixed-window request counters (bucket = hashed client IP), kept for a day.
create table public.edge_rate_limits (
  bucket       text not null,
  window_start timestamptz not null,
  hits         integer not null default 0,
  primary key (bucket, window_start)
);

alter table public.search_terms_cache enable row level security;
alter table public.edge_rate_limits enable row level security;
revoke all on public.search_terms_cache, public.edge_rate_limits from anon, authenticated;

-- Counts one hit and returns whether the bucket is still within `max_hits` per hour.
create function public.hit_rate_limit(p_bucket text, p_max_hits integer) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  current_window timestamptz := date_trunc('hour', now());
  count_now integer;
begin
  insert into public.edge_rate_limits (bucket, window_start, hits)
  values (p_bucket, current_window, 1)
  on conflict (bucket, window_start) do update set hits = public.edge_rate_limits.hits + 1
  returning hits into count_now;

  -- Housekeeping on roughly 1 % of calls.
  if random() < 0.01 then
    delete from public.edge_rate_limits where window_start < now() - interval '1 day';
  end if;

  return count_now <= p_max_hits;
end;
$$;

revoke execute on function public.hit_rate_limit(text, integer) from public, anon, authenticated;
grant execute on function public.hit_rate_limit(text, integer) to service_role;
