-- The blocker needs the blocked user's nickname to show a "Blocked users" list with Unblock.
-- The blocked user still can't see the blocker, and search hides blocks in both directions.

create function public.i_blocked(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks where blocker_id = (select auth.uid()) and blocked_id = other
  );
$$;

revoke execute on function public.i_blocked(uuid) from public, anon;
grant execute on function public.i_blocked(uuid) to authenticated;

drop policy "profiles: read unless blocked" on public.profiles;
create policy "profiles: read unless blocked" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or not public.is_blocked_between(id, (select auth.uid()))
    or public.i_blocked(id)
  );

create or replace function public.search_profiles(query text)
returns table (id uuid, nickname extensions.citext, avatar_path text)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.nickname, p.avatar_path
  from public.profiles p
  where char_length(query) >= 2
    and p.id <> (select auth.uid())
    and not public.is_blocked_between(p.id, (select auth.uid()))
    and p.nickname::text ilike
        (replace(replace(replace(query, '\', '\\'), '%', '\%'), '_', '\_') || '%')
  order by p.nickname
  limit 20;
$$;
