-- Challenges ("Výzva kamarádovi"): a question attached to a shared article, private between
-- two friends. No points, streaks or leaderboards.
--
-- * The correct answer lives in challenge_solutions: RLS filters rows, not columns, so this
--   is how it stays hidden from the recipient until they answer.
-- * Clients never write these tables directly – only through create_challenge() and
--   answer_challenge() (security definer), which validate everything and evaluate answers.

create type public.challenge_kind as enum ('multiple_choice', 'open');
create type public.challenge_source as enum ('custom', 'wikidata', 'generated');

alter table public.profiles add column accepts_challenges boolean not null default true;

-- Every option non-blank, at most max_length characters, and all distinct (case-insensitive).
create function public.valid_challenge_options(options text[], max_length int) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(array_length(options, 1), 0) = 3
     and (select bool_and(char_length(btrim(o)) between 1 and max_length) from unnest(options) o)
     and (select count(distinct lower(btrim(o))) from unnest(options) o) = 3;
$$;

create table public.challenges (
  id            uuid primary key default gen_random_uuid(),
  share_id      uuid not null unique references public.shares (id) on delete cascade,
  sender_id     uuid not null references public.profiles (id) on delete cascade,
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  kind          public.challenge_kind not null,
  source        public.challenge_source not null default 'custom',
  question      text not null check (char_length(btrim(question)) between 1 and 200),
  options       text[],
  answer_index  smallint check (answer_index between 0 and 2),
  answer_text   text check (char_length(answer_text) <= 80),
  answered_before_reading boolean,
  is_correct    boolean,
  created_at    timestamptz not null default now(),
  answered_at   timestamptz,
  check ((kind = 'multiple_choice') = (options is not null)),
  check (options is null or public.valid_challenge_options(options, 80))
);
create index challenges_recipient_idx on public.challenges (recipient_id, created_at desc);
create index challenges_sender_idx on public.challenges (sender_id, created_at desc);

create table public.challenge_solutions (
  challenge_id    uuid primary key references public.challenges (id) on delete cascade,
  correct_index   smallint check (correct_index between 0 and 2),
  expected_answer text check (char_length(expected_answer) <= 80)
);

alter table public.challenges enable row level security;
alter table public.challenge_solutions enable row level security;
revoke all on public.challenges, public.challenge_solutions from anon;

create policy "challenges: participants read" on public.challenges
  for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));

create policy "challenge_solutions: sender, or recipient after answering" on public.challenge_solutions
  for select to authenticated
  using (exists (
    select 1 from public.challenges c
    where c.id = challenge_id
      and (c.sender_id = (select auth.uid())
           or (c.recipient_id = (select auth.uid()) and c.answered_at is not null))
  ));

-- ---------------------------------------------------------------------------
-- RPC: create
-- Errors (message): share_not_found, not_friends, blocked, challenges_disabled,
-- invalid_question, invalid_options, invalid_answer, challenge_exists.
-- ---------------------------------------------------------------------------

create function public.create_challenge(
  p_share_id uuid,
  p_kind public.challenge_kind,
  p_question text,
  p_options text[] default null,
  p_correct_index smallint default null,
  p_expected_answer text default null,
  p_source public.challenge_source default 'custom'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  share public.shares;
  new_id uuid;
begin
  select * into share from public.shares where id = p_share_id;
  if not found or share.sender_id <> me then
    raise exception 'share_not_found';
  end if;
  if not public.are_friends(share.sender_id, share.recipient_id) then
    raise exception 'not_friends';
  end if;
  if public.is_blocked_between(share.sender_id, share.recipient_id) then
    raise exception 'blocked';
  end if;
  if exists (select 1 from public.profiles
             where id in (share.sender_id, share.recipient_id) and not accepts_challenges) then
    raise exception 'challenges_disabled';
  end if;
  if p_question is null or char_length(btrim(p_question)) not between 1 and 200 then
    raise exception 'invalid_question';
  end if;
  if p_kind = 'multiple_choice' then
    if p_options is null or not public.valid_challenge_options(p_options, 80) then
      raise exception 'invalid_options';
    end if;
    if p_correct_index is null or p_correct_index not between 0 and 2 then
      raise exception 'invalid_answer';
    end if;
  else
    if p_options is not null or p_correct_index is not null
       or char_length(coalesce(p_expected_answer, '')) > 80 then
      raise exception 'invalid_options';
    end if;
  end if;
  if exists (select 1 from public.challenges where share_id = p_share_id) then
    raise exception 'challenge_exists';
  end if;

  insert into public.challenges (share_id, sender_id, recipient_id, kind, source, question, options)
  values (
    p_share_id, share.sender_id, share.recipient_id, p_kind, p_source, btrim(p_question),
    (select array_agg(btrim(o)) from unnest(p_options) o)
  )
  returning id into new_id;

  insert into public.challenge_solutions (challenge_id, correct_index, expected_answer)
  values (new_id, p_correct_index, nullif(btrim(coalesce(p_expected_answer, '')), ''));

  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: answer. Returns the evaluation together with the solution.
-- Errors: challenge_not_found, already_answered, blocked, invalid_answer.
-- ---------------------------------------------------------------------------

create function public.answer_challenge(
  p_challenge_id uuid,
  p_answer_index smallint default null,
  p_answer_text text default null,
  p_before_reading boolean default false
) returns table (is_correct boolean, correct_index smallint, expected_answer text)
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  challenge public.challenges;
  solution public.challenge_solutions;
  correct boolean;
begin
  select * into challenge from public.challenges where id = p_challenge_id for update;
  if not found or challenge.recipient_id <> me then
    raise exception 'challenge_not_found';
  end if;
  if challenge.answered_at is not null then
    raise exception 'already_answered';
  end if;
  if public.is_blocked_between(challenge.sender_id, challenge.recipient_id) then
    raise exception 'blocked';
  end if;

  select * into solution from public.challenge_solutions where challenge_id = challenge.id;

  if challenge.kind = 'multiple_choice' then
    if p_answer_index is null or p_answer_index not between 0 and 2 or p_answer_text is not null then
      raise exception 'invalid_answer';
    end if;
    correct := p_answer_index = solution.correct_index;
  else
    if p_answer_index is not null or p_answer_text is null
       or char_length(btrim(p_answer_text)) not between 1 and 80 then
      raise exception 'invalid_answer';
    end if;
    correct := null; -- open questions aren't judged automatically
  end if;

  update public.challenges set
    answer_index = p_answer_index,
    answer_text = nullif(btrim(coalesce(p_answer_text, '')), ''),
    answered_before_reading = coalesce(p_before_reading, false),
    is_correct = correct,
    answered_at = now()
  where id = challenge.id;

  -- The answer is part of the conversation: bump it for the other side's list.
  update public.shares set last_activity_at = now() where id = challenge.share_id;

  return query select correct, solution.correct_index, solution.expected_answer;
end;
$$;

revoke execute on function
  public.create_challenge(uuid, public.challenge_kind, text, text[], smallint, text, public.challenge_source),
  public.answer_challenge(uuid, smallint, text, boolean)
  from public, anon;
grant execute on function
  public.create_challenge(uuid, public.challenge_kind, text, text[], smallint, text, public.challenge_source),
  public.answer_challenge(uuid, smallint, text, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Reports: a challenge can be reported too (snapshot of the question).
-- ---------------------------------------------------------------------------

alter table public.reports add column challenge_id uuid references public.challenges (id) on delete set null;
create index reports_challenge_idx on public.reports (challenge_id);

create or replace function public.reports_prepare() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  reported_body text;
  reported_author uuid;
begin
  new.status := 'open';
  new.created_at := now();
  new.content_snapshot := null;
  if new.message_id is null and new.reported_user_id is null and new.challenge_id is null then
    raise exception 'report needs a user or a message';
  end if;
  if new.message_id is not null then
    select m.body, m.author_id into reported_body, reported_author
    from public.messages m
    join public.shares s on s.id = m.share_id
    where m.id = new.message_id
      and (select auth.uid()) in (s.sender_id, s.recipient_id);
    if not found then
      raise exception 'message not found';
    end if;
    new.content_snapshot := reported_body;
    new.reported_user_id := reported_author;
  elsif new.challenge_id is not null then
    select c.question || coalesce(' | ' || array_to_string(c.options, ' | '), ''), c.sender_id
      into reported_body, reported_author
    from public.challenges c
    where c.id = new.challenge_id
      and (select auth.uid()) in (c.sender_id, c.recipient_id);
    if not found then
      raise exception 'challenge not found';
    end if;
    new.content_snapshot := reported_body;
    new.reported_user_id := reported_author;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- "From friends" shows pending challenges on shared articles.
-- ---------------------------------------------------------------------------

create or replace view public.friend_activity with (security_invoker = true) as
  select 'saved'::text as kind, sa.user_id as friend_id, p.nickname, p.avatar_path,
         sa.page_id, sa.title, sa.thumbnail_url, sa.saved_at as occurred_at, null::uuid as share_id,
         null::text as challenge_question, null::boolean as challenge_answered
  from public.saved_articles sa
  join public.profiles p on p.id = sa.user_id
  where sa.user_id <> (select auth.uid())
  union all
  select 'shared', sh.sender_id, p.nickname, p.avatar_path,
         sh.page_id, sh.title, sh.thumbnail_url, sh.created_at, sh.id,
         c.question, c.answered_at is not null
  from public.shares sh
  join public.profiles p on p.id = sh.sender_id
  left join public.challenges c on c.share_id = sh.id
  where sh.recipient_id = (select auth.uid());

-- Live update of the challenge card only inside an open chat (filtered by share_id).
alter publication supabase_realtime add table public.challenges;
