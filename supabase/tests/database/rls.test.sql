-- RLS and trigger tests. Run with: npx supabase test db
-- Alice and Bob are friends, Cyril is a stranger.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'cyril@test.local');
insert into public.profiles (id, nickname) values
  ('11111111-1111-1111-1111-111111111111', 'alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob'),
  ('33333333-3333-3333-3333-333333333333', 'cyril');
insert into public.friendships (requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');
insert into public.shares (id, sender_id, recipient_id, page_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 771, 'Mars (planeta)');
insert into public.messages (id, share_id, author_id, body) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Koukni na tohle!');
insert into public.user_topics (user_id, topic_id) values ('22222222-2222-2222-2222-222222222222', 'space');
insert into public.saved_articles (user_id, page_id, title) values ('22222222-2222-2222-2222-222222222222', 797, 'Planeta');

-- ---------------------------------------------------------------- anon
set local role anon;
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select * from public.messages $$, '42501', null, 'anon cannot read messages');
reset role;

-- ---------------------------------------------------------------- stranger (Cyril)
set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333"}';

select is_empty($$ select * from public.shares $$, 'stranger cannot see shares of others');
select is_empty($$ select * from public.messages $$, 'stranger cannot read messages of others');
select is_empty($$ select * from public.friendships where status = 'accepted' $$, 'stranger cannot see others'' friendships');
select is_empty($$ select * from public.user_topics $$, 'stranger cannot see topics of non-friends');
select is_empty($$ select * from public.saved_articles $$, 'stranger cannot see saved articles of non-friends');
select throws_ok(
  $$ insert into public.messages (share_id, author_id, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'ahoj') $$,
  '42501', null, 'stranger cannot post into a foreign thread');
select throws_ok(
  $$ insert into public.shares (sender_id, recipient_id, page_id, title)
     values ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 1, 'X') $$,
  '42501', null, 'cannot share with a non-friend');
select throws_ok(
  $$ insert into public.friendships (requester_id, addressee_id, status)
     values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'accepted') $$,
  '42501', null, 'cannot create an already accepted friendship');
select throws_ok(
  $$ insert into public.reports (reporter_id, message_id, reason)
     values ('33333333-3333-3333-3333-333333333333', 'bbbbbbbb-0000-0000-0000-000000000001', 'spam') $$,
  'P0001', 'message not found', 'cannot report a message one cannot see');

update public.profiles set nickname = 'hacked' where id = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select count(*)::int from public.profiles where nickname = 'hacked' $$, array[0],
  'cannot edit someone else''s profile');
select results_eq(
  $$ select count(*)::int from public.search_profiles('al') $$, array[1], 'search finds by prefix');
select results_eq(
  $$ select count(*)::int from public.search_profiles('%') $$, array[0], 'search treats wildcards literally');

-- ---------------------------------------------------------------- friend (Alice)
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';

select results_eq($$ select count(*)::int from public.user_topics $$, array[1], 'friend sees friend''s topics');
select is_empty($$ select * from public.saved_articles $$, 'friend''s saved articles hidden without opt-in');

-- friend request lifecycle with Cyril
select lives_ok(
  $$ insert into public.friendships (requester_id, addressee_id)
     values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333') $$,
  'can send a friend request');
select throws_ok(
  $$ insert into public.friendships (requester_id, addressee_id)
     values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'cannot create a request on behalf of someone else');
update public.friendships set status = 'accepted' where addressee_id = '33333333-3333-3333-3333-333333333333';
select results_eq(
  $$ select status::text from public.friendships where addressee_id = '33333333-3333-3333-3333-333333333333' $$,
  array['pending'], 'requester cannot accept own request');

set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333"}';
update public.friendships set status = 'accepted' where requester_id = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select status::text from public.friendships where requester_id = '11111111-1111-1111-1111-111111111111' $$,
  array['accepted'], 'addressee can accept');
select isnt_empty(
  $$ select * from public.friendships where responded_at is not null and requester_id = '11111111-1111-1111-1111-111111111111' $$,
  'accepting stamps responded_at');
update public.friendships set status = 'pending' where requester_id = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select status::text from public.friendships where requester_id = '11111111-1111-1111-1111-111111111111' $$,
  array['accepted'], 'accepted friendship cannot be changed back');

-- participants of a pending request are immutable (checked by trigger)
reset role;
insert into public.friendships (requester_id, addressee_id)
values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333');
set local role authenticated;
select throws_ok(
  $$ update public.friendships set requester_id = '11111111-1111-1111-1111-111111111111', status = 'accepted'
     where requester_id = '22222222-2222-2222-2222-222222222222' and addressee_id = '33333333-3333-3333-3333-333333333333' $$,
  'P0001', 'friendship participants are immutable', 'addressee cannot swap the requester');
reset role;
delete from public.friendships
where requester_id = '22222222-2222-2222-2222-222222222222' and addressee_id = '33333333-3333-3333-3333-333333333333';
set local role authenticated;

-- ---------------------------------------------------------------- recipient (Bob)
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';

select results_eq($$ select count(*)::int from public.messages $$, array[1], 'participant reads the thread');
select throws_ok(
  $$ insert into public.messages (share_id, author_id, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'fake') $$,
  '42501', null, 'cannot post as someone else');
select lives_ok(
  $$ insert into public.messages (share_id, author_id, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Super, díky!') $$,
  'participant can reply');
select throws_ok(
  $$ insert into public.messages (share_id, author_id, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '   ') $$,
  '23514', null, 'blank messages are rejected');

update public.profiles set share_saved_with_friends = true where id = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select count(*)::int from public.friend_activity $$, array[1], 'recipient sees shared article in friend activity');

-- reports: snapshot and reported user are set by the server
insert into public.reports (reporter_id, message_id, reason, content_snapshot, status)
values ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000001', 'harassment', 'forged', 'resolved');
select results_eq(
  $$ select content_snapshot, reported_user_id::text, status from public.reports $$,
  $$ values ('Koukni na tohle!'::text, '11111111-1111-1111-1111-111111111111'::text, 'open'::text) $$,
  'report snapshot, reported user and status come from the server');

-- Alice now sees Bob's saved articles (opt-in)
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select results_eq($$ select count(*)::int from public.saved_articles $$, array[1], 'opted-in saved articles visible to friend');
select results_eq(
  $$ select count(*)::int from public.friend_activity where kind = 'saved' $$, array[1], 'friend activity lists saved article');
select is_empty($$ select * from public.reports $$, 'cannot read reports filed by others');
select throws_ok(
  $$ insert into public.reports (reporter_id, reason) values ('11111111-1111-1111-1111-111111111111', 'spam') $$,
  'P0001', 'report needs a user or a message', 'report must target a user or a message');

-- ---------------------------------------------------------------- blocking (Bob blocks Alice)
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';
insert into public.blocks (blocker_id, blocked_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select is_empty(
  $$ select * from public.friendships where '22222222-2222-2222-2222-222222222222' in (requester_id, addressee_id) $$,
  'blocking ends the friendship');
select is_empty($$ select * from public.blocks $$, 'blocked user cannot see the block');
select is_empty(
  $$ select * from public.profiles where id = '22222222-2222-2222-2222-222222222222' $$,
  'blocked user cannot see blocker''s profile');
select is_empty($$ select * from public.search_profiles('bo') $$, 'blocker is hidden from search');
select is_empty($$ select * from public.user_topics $$, 'topics hidden after block');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';
select results_eq(
  $$ select nickname::text from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$,
  array['alice'], 'blocker still sees the blocked profile (for the unblock list)');
select is_empty($$ select * from public.search_profiles('al') $$, 'blocked user is hidden from blocker''s search');
select results_eq(
  $$ select count(*)::int from public.blocks $$, array[1], 'blocker sees own block');
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select throws_ok(
  $$ insert into public.messages (share_id, author_id, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'proč?') $$,
  '42501', null, 'blocked user cannot write into an existing thread');
select throws_ok(
  $$ insert into public.friendships (requester_id, addressee_id)
     values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222') $$,
  '42501', null, 'blocked user cannot send a new friend request');

-- ---------------------------------------------------------------- constraints and account deletion
reset role;
select throws_ok(
  $$ insert into public.profiles (id, nickname) values ('22222222-2222-2222-2222-222222222222', 'Pável') $$,
  '23514', null, 'nickname allows only A-Z, 0-9, _ and .');
select throws_ok(
  $$ update public.profiles set nickname = 'ALICE' where id = '33333333-3333-3333-3333-333333333333' $$,
  '23505', null, 'nicknames are unique case-insensitively');

delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
select is_empty($$ select * from public.messages where author_id = '11111111-1111-1111-1111-111111111111' $$,
  'deleting the account deletes authored messages');
select is_empty($$ select * from public.shares where sender_id = '11111111-1111-1111-1111-111111111111' $$,
  'deleting the account deletes sent shares');
select results_eq($$ select count(*)::int from public.reports where reporter_id is not null $$, array[1],
  'reports filed by others survive');

select * from finish();
rollback;
