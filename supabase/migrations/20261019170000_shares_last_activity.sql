-- Conversation list ordered by latest message without scanning messages (free-tier friendly).

alter table public.shares add column last_activity_at timestamptz not null default now();

create index shares_recipient_activity_idx on public.shares (recipient_id, last_activity_at desc);
create index shares_sender_activity_idx on public.shares (sender_id, last_activity_at desc);

create function public.messages_touch_share() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.shares set last_activity_at = new.created_at where id = new.share_id;
  return null;
end;
$$;

create trigger messages_touch_share after insert on public.messages
  for each row execute function public.messages_touch_share();

revoke execute on function public.messages_touch_share() from public, anon, authenticated;

-- Clients must not forge activity time: it's set by default on insert and by the trigger.
create function public.shares_guard_activity() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.last_activity_at := now();
  return new;
end;
$$;

create trigger shares_guard_activity before insert on public.shares
  for each row execute function public.shares_guard_activity();

revoke execute on function public.shares_guard_activity() from public, anon, authenticated;
