-- Rabbithole – Phase 2: accounts, friends, sharing, chat.
--
-- Principles:
-- * Only data needed for social features lives here. Topic weights, reading history
--   and reading time stay on the device.
-- * Row Level Security on every table; `anon` has no access at all.
-- * Article content is never stored – only Wikipedia page id, title and thumbnail URL.

create extension if not exists citext with schema extensions;

-- =====================================================================
-- Tables
-- =====================================================================

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nickname    extensions.citext not null unique
              check (char_length(nickname) between 3 and 24 and nickname::text ~ '^[A-Za-z0-9_.]+$'),
  avatar_path text check (char_length(avatar_path) <= 200),
  share_saved_with_friends boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.user_topics (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  topic_id text not null check (char_length(topic_id) between 1 and 32),
  primary key (user_id, topic_id)
);

create type public.friendship_status as enum ('pending', 'accepted');

create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       public.friendship_status not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);
-- One relation per pair regardless of direction.
create unique index friendships_pair_key on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_addressee_idx on public.friendships (addressee_id, status);
create index friendships_requester_idx on public.friendships (requester_id, status);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.shares (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid not null references public.profiles (id) on delete cascade,
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  page_id       integer not null check (page_id > 0),
  title         text not null check (char_length(title) between 1 and 300),
  thumbnail_url text check (thumbnail_url ~ '^https://[a-z]+\.wikimedia\.org/'),
  created_at    timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index shares_recipient_idx on public.shares (recipient_id, created_at desc);
create index shares_sender_idx on public.shares (sender_id, created_at desc);

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  share_id   uuid not null references public.shares (id) on delete cascade,
  author_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index messages_share_idx on public.messages (share_id, created_at);
create index messages_author_idx on public.messages (author_id);

create table public.share_reads (
  share_id     uuid not null references public.shares (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (share_id, user_id)
);
create index share_reads_user_idx on public.share_reads (user_id);

create table public.saved_articles (
  user_id       uuid not null references public.profiles (id) on delete cascade,
  page_id       integer not null check (page_id > 0),
  title         text not null check (char_length(title) between 1 and 300),
  thumbnail_url text check (thumbnail_url ~ '^https://[a-z]+\.wikimedia\.org/'),
  saved_at      timestamptz not null default now(),
  primary key (user_id, page_id)
);
create index saved_articles_recent_idx on public.saved_articles (user_id, saved_at desc);

create type public.report_reason as enum ('spam', 'harassment', 'inappropriate', 'impersonation', 'other');

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid references public.profiles (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  message_id       uuid references public.messages (id) on delete set null,
  reason           public.report_reason not null,
  note             text check (char_length(note) <= 1000),
  -- Copy of the reported message, filled by trigger (never by the client) so it
  -- survives deletion of the message for moderation.
  content_snapshot text,
  status           text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at       timestamptz not null default now()
  -- "user or message" is enforced on insert only (reports_prepare): both may become
  -- NULL later when the reported account is deleted, and the report must survive.
);
create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_reporter_idx on public.reports (reporter_id);
create index reports_reported_user_idx on public.reports (reported_user_id);
create index reports_message_idx on public.reports (message_id);

-- =====================================================================
-- Helper functions (security definer: see rows the caller can't, e.g. the other
-- side's blocks, without RLS recursion). Empty search_path, fully qualified names.
-- =====================================================================

create function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

create function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and least(requester_id, addressee_id) = least(a, b)
      and greatest(requester_id, addressee_id) = greatest(a, b)
  );
$$;

-- Caller participates in the share, the two are still friends and nobody blocks anybody.
create function public.can_post_to_share(s uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shares sh
    where sh.id = s
      and (select auth.uid()) in (sh.sender_id, sh.recipient_id)
      and public.are_friends(sh.sender_id, sh.recipient_id)
      and not public.is_blocked_between(sh.sender_id, sh.recipient_id)
  );
$$;

create function public.is_share_participant(s uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shares sh
    where sh.id = s and (select auth.uid()) in (sh.sender_id, sh.recipient_id)
  );
$$;

revoke execute on function
  public.is_blocked_between(uuid, uuid), public.are_friends(uuid, uuid),
  public.can_post_to_share(uuid), public.is_share_participant(uuid)
  from public, anon;
grant execute on function
  public.is_blocked_between(uuid, uuid), public.are_friends(uuid, uuid),
  public.can_post_to_share(uuid), public.is_share_participant(uuid)
  to authenticated;

-- =====================================================================
-- Triggers
-- =====================================================================

create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Participants and creation time are immutable; accepting stamps responded_at.
create function public.friendships_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.responded_at := null;
    return new;
  end if;
  if new.requester_id <> old.requester_id
     or new.addressee_id <> old.addressee_id
     or new.created_at <> old.created_at then
    raise exception 'friendship participants are immutable';
  end if;
  if new.status = 'accepted' and old.status = 'pending' then
    new.responded_at := now();
  end if;
  return new;
end;
$$;

create trigger friendships_guard before insert or update on public.friendships
  for each row execute function public.friendships_guard();

-- Blocking ends the friendship and removes pending requests in both directions.
create function public.blocks_end_friendship() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.friendships
  where least(requester_id, addressee_id) = least(new.blocker_id, new.blocked_id)
    and greatest(requester_id, addressee_id) = greatest(new.blocker_id, new.blocked_id);
  return null;
end;
$$;

create trigger blocks_end_friendship after insert on public.blocks
  for each row execute function public.blocks_end_friendship();

-- Server-side fields of a report: status, timestamp and a snapshot of the reported
-- message, which the reporter must be able to see.
create function public.reports_prepare() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  reported_body text;
  reported_author uuid;
begin
  new.status := 'open';
  new.created_at := now();
  new.content_snapshot := null;
  if new.message_id is null and new.reported_user_id is null then
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
  end if;
  return new;
end;
$$;

create trigger reports_prepare before insert on public.reports
  for each row execute function public.reports_prepare();

-- Trigger functions are not meant to be called directly.
revoke execute on function
  public.set_updated_at(), public.friendships_guard(),
  public.blocks_end_friendship(), public.reports_prepare()
  from public, anon, authenticated;

-- =====================================================================
-- Row Level Security
-- =====================================================================

alter table public.profiles       enable row level security;
alter table public.user_topics    enable row level security;
alter table public.friendships    enable row level security;
alter table public.blocks         enable row level security;
alter table public.shares         enable row level security;
alter table public.messages       enable row level security;
alter table public.share_reads    enable row level security;
alter table public.saved_articles enable row level security;
alter table public.reports        enable row level security;

revoke all on all tables in schema public from anon;

-- profiles: visible to signed-in users unless either side blocked the other.
create policy "profiles: read unless blocked" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or not public.is_blocked_between(id, (select auth.uid())));
create policy "profiles: insert own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- user_topics: me and my friends.
create policy "user_topics: read own or friends" on public.user_topics
  for select to authenticated
  using (user_id = (select auth.uid()) or public.are_friends(user_id, (select auth.uid())));
create policy "user_topics: insert own" on public.user_topics
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "user_topics: delete own" on public.user_topics
  for delete to authenticated using (user_id = (select auth.uid()));

-- friendships
create policy "friendships: participants read" on public.friendships
  for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));
create policy "friendships: send request" on public.friendships
  for insert to authenticated
  with check (
    requester_id = (select auth.uid())
    and status = 'pending'
    and not public.is_blocked_between(requester_id, addressee_id)
  );
create policy "friendships: addressee accepts" on public.friendships
  for update to authenticated
  using (addressee_id = (select auth.uid()) and status = 'pending')
  with check (addressee_id = (select auth.uid()) and status = 'accepted');
create policy "friendships: decline, cancel or unfriend" on public.friendships
  for delete to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

-- blocks: only the blocker sees and manages them.
create policy "blocks: read own" on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy "blocks: insert own" on public.blocks
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy "blocks: delete own" on public.blocks
  for delete to authenticated using (blocker_id = (select auth.uid()));

-- shares
create policy "shares: participants read" on public.shares
  for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));
create policy "shares: send to friend" on public.shares
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and public.are_friends(sender_id, recipient_id)
    and not public.is_blocked_between(sender_id, recipient_id)
  );

-- messages
create policy "messages: participants read" on public.messages
  for select to authenticated using (public.is_share_participant(share_id));
create policy "messages: post as self" on public.messages
  for insert to authenticated
  with check (author_id = (select auth.uid()) and public.can_post_to_share(share_id));
create policy "messages: delete own" on public.messages
  for delete to authenticated using (author_id = (select auth.uid()));

-- share_reads: own rows for shares I take part in.
create policy "share_reads: read own" on public.share_reads
  for select to authenticated using (user_id = (select auth.uid()));
create policy "share_reads: insert own" on public.share_reads
  for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_share_participant(share_id));
create policy "share_reads: update own" on public.share_reads
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- saved_articles: mine, and friends' only when they opted in.
create policy "saved_articles: read own or opted-in friends" on public.saved_articles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      public.are_friends(user_id, (select auth.uid()))
      and exists (select 1 from public.profiles p where p.id = user_id and p.share_saved_with_friends)
    )
  );
create policy "saved_articles: insert own" on public.saved_articles
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "saved_articles: delete own" on public.saved_articles
  for delete to authenticated using (user_id = (select auth.uid()));

-- reports: file and read own; moderation happens with the service role.
create policy "reports: file" on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy "reports: read own" on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));

-- =====================================================================
-- Search and "From friends" feed
-- =====================================================================

-- Prefix search by nickname. Blocked users are filtered by RLS on profiles.
create function public.search_profiles(query text)
returns table (id uuid, nickname extensions.citext, avatar_path text)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.nickname, p.avatar_path
  from public.profiles p
  where char_length(query) >= 2
    and p.id <> (select auth.uid())
    and p.nickname::text ilike
        (replace(replace(replace(query, '\', '\\'), '%', '\%'), '_', '\_') || '%')
  order by p.nickname
  limit 20;
$$;

revoke execute on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

-- Friends' saved articles (opt-in, enforced by RLS) and articles shared with me.
create view public.friend_activity with (security_invoker = true) as
  select 'saved'::text as kind, sa.user_id as friend_id, p.nickname, p.avatar_path,
         sa.page_id, sa.title, sa.thumbnail_url, sa.saved_at as occurred_at, null::uuid as share_id
  from public.saved_articles sa
  join public.profiles p on p.id = sa.user_id
  where sa.user_id <> (select auth.uid())
  union all
  select 'shared', sh.sender_id, p.nickname, p.avatar_path,
         sh.page_id, sh.title, sh.thumbnail_url, sh.created_at, sh.id
  from public.shares sh
  join public.profiles p on p.id = sh.sender_id
  where sh.recipient_id = (select auth.uid());

revoke all on public.friend_activity from anon;
grant select on public.friend_activity to authenticated;

-- =====================================================================
-- Realtime
-- =====================================================================

alter publication supabase_realtime add table public.messages, public.shares, public.friendships;

-- =====================================================================
-- Storage: avatars/{user_id}/<file>
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg', 'image/png', 'image/heic']);

create policy "avatars: signed-in users read" on storage.objects
  for select to authenticated using (bucket_id = 'avatars');
create policy "avatars: upload own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
