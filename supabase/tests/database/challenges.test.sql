-- Challenges: visibility of the solution, RPC validation, blocking, opt-out, reports.
-- Alice and Bob are friends with a shared article, Cyril is a stranger.
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
   '22222222-2222-2222-2222-222222222222', 771, 'Mars (planeta)'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 797, 'Planeta'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111', 100, 'Jupiter');

set local role authenticated;

-- ---------------------------------------------------------------- creating (Alice)
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';

select throws_ok(
  $$ insert into public.challenges (share_id, sender_id, recipient_id, kind, question)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222', 'open', 'X?') $$,
  '42501', null, 'challenges cannot be inserted directly');

select lives_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000001', 'multiple_choice',
       'Kolik měsíců má Mars?', array['Dva', 'Jeden', 'Žádný'], 0::smallint) $$,
  'sender creates a multiple-choice challenge');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000001', 'open', 'Znovu?') $$,
  'P0001', 'challenge_exists', 'only one challenge per shared article');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000003', 'open', 'Cizí sdílení?') $$,
  'P0001', 'share_not_found', 'only the sender of the share can attach a challenge');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'multiple_choice',
       'Stejné možnosti?', array['A', 'a', 'B'], 1::smallint) $$,
  'P0001', 'invalid_options', 'options must be distinct');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'multiple_choice',
       'Dvě možnosti?', array['A', 'B'], 1::smallint) $$,
  'P0001', 'invalid_options', 'exactly three options');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'multiple_choice',
       'Dlouhá možnost?', array['A', 'B', repeat('x', 81)], 1::smallint) $$,
  'P0001', 'invalid_options', 'option max 80 characters');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'multiple_choice',
       'Bez správné?', array['A', 'B', 'C']) $$,
  'P0001', 'invalid_answer', 'multiple choice needs the correct index');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'open', repeat('x', 201)) $$,
  'P0001', 'invalid_question', 'question max 200 characters');
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'open', 'Proč?', null, null, repeat('x', 81)) $$,
  'P0001', 'invalid_options', 'expected answer max 80 characters');

select results_eq(
  $$ select correct_index from public.challenge_solutions $$, array[0::smallint],
  'sender sees the solution');

-- the stranger must not learn ids, so hand the real one over via a temp table
reset role;
create temp table known_challenge as select id from public.challenges;
grant select on known_challenge to authenticated;
set local role authenticated;

-- ---------------------------------------------------------------- stranger (Cyril)
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333"}';
select is_empty($$ select * from public.challenges $$, 'stranger cannot see challenges');
select is_empty($$ select * from public.challenge_solutions $$, 'stranger cannot see solutions');
select throws_ok(
  $$ select * from public.answer_challenge((select id from known_challenge), 0::smallint) $$,
  'P0001', 'challenge_not_found', 'stranger cannot answer even with the real id');

-- ---------------------------------------------------------------- recipient (Bob)
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';
select results_eq(
  $$ select question from public.challenges $$, array['Kolik měsíců má Mars?'], 'recipient sees the question');
select results_eq(
  $$ select options from public.challenges $$, $$ values (array['Dva', 'Jeden', 'Žádný']) $$, 'recipient sees the options');
select is_empty($$ select * from public.challenge_solutions $$, 'recipient does NOT see the solution before answering');
select results_eq(
  $$ select challenge_question, challenge_answered from public.friend_activity where share_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  $$ values ('Kolik měsíců má Mars?'::text, false) $$,
  'pending challenge shows in friend activity');

update public.challenges set is_correct = true, answer_index = 0, answered_at = now();
select results_eq(
  $$ select count(*)::int from public.challenges where answered_at is not null $$, array[0],
  'recipient cannot fake an answer by updating directly');

select throws_ok(
  $$ select * from public.answer_challenge((select id from public.challenges), null, 'dva') $$,
  'P0001', 'invalid_answer', 'multiple choice needs an index');
select results_eq(
  $$ select is_correct, correct_index from public.answer_challenge((select id from public.challenges), 1::smallint, null, true) $$,
  $$ values (false, 0::smallint) $$,
  'answer is evaluated and the solution returned');
select results_eq(
  $$ select correct_index from public.challenge_solutions $$, array[0::smallint],
  'recipient sees the solution after answering');
select results_eq(
  $$ select answer_index, is_correct, answered_before_reading from public.challenges $$,
  $$ values (1::smallint, false, true) $$,
  'answer stored with "before reading" flag');
select throws_ok(
  $$ select * from public.answer_challenge((select id from public.challenges), 0::smallint) $$,
  'P0001', 'already_answered', 'cannot answer twice');

-- report the challenge: snapshot and reported user come from the server
insert into public.reports (reporter_id, challenge_id, reason)
values ('22222222-2222-2222-2222-222222222222', (select id from public.challenges), 'inappropriate');
select results_eq(
  $$ select content_snapshot, reported_user_id::text from public.reports $$,
  $$ values ('Kolik měsíců má Mars? | Dva | Jeden | Žádný'::text, '11111111-1111-1111-1111-111111111111'::text) $$,
  'challenge report gets a snapshot and the sender as reported user');

-- ---------------------------------------------------------------- open question
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select lives_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000002', 'open',
       'Co tě nejvíc překvapilo?', null, null, 'Velikost') $$,
  'sender creates an open challenge');
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';
select results_eq(
  $$ select is_correct, expected_answer from public.answer_challenge(
       (select id from public.challenges where share_id = 'aaaaaaaa-0000-0000-0000-000000000002'), null, 'Prstence') $$,
  $$ values (null::boolean, 'Velikost'::text) $$,
  'open answers are not judged, the expected answer is revealed');

-- ---------------------------------------------------------------- opt-out and blocking
reset role;
insert into public.shares (id, sender_id, recipient_id, page_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 200, 'Saturn'),
  ('aaaaaaaa-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 201, 'Uran');
update public.profiles set accepts_challenges = false where id = '22222222-2222-2222-2222-222222222222';
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000004', 'open', 'Proč?') $$,
  'P0001', 'challenges_disabled', 'no challenges to someone who turned them off');

reset role;
update public.profiles set accepts_challenges = true where id = '22222222-2222-2222-2222-222222222222';
set local role authenticated;
select lives_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000005', 'open', 'Proč Uran?') $$,
  'challenge created before the block');

set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222"}';
insert into public.blocks (blocker_id, blocked_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select * from public.answer_challenge(
       (select id from public.challenges where share_id = 'aaaaaaaa-0000-0000-0000-000000000005'), null, 'Protože') $$,
  'P0001', 'blocked', 'no answering after a block');

set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111"}';
select throws_ok(
  $$ select public.create_challenge('aaaaaaaa-0000-0000-0000-000000000004', 'open', 'Proč?') $$,
  'P0001', 'not_friends', 'blocked user cannot send challenges (friendship ended)');

select * from finish();
rollback;
