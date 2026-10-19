-- search-assist support: rate limit counter and access.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(public.hit_rate_limit('bucket-a', 2), 'first hit allowed');
select ok(public.hit_rate_limit('bucket-a', 2), 'second hit allowed');
select ok(not public.hit_rate_limit('bucket-a', 2), 'third hit over the limit');
select ok(public.hit_rate_limit('bucket-b', 2), 'other bucket counts separately');

set local role authenticated;
select throws_ok($$ select public.hit_rate_limit('x', 1) $$, '42501', null, 'clients cannot call the limiter');
select throws_ok($$ select * from public.search_terms_cache $$, '42501', null, 'clients cannot read the cache');
set local role anon;
select throws_ok($$ select * from public.edge_rate_limits $$, '42501', null, 'anon cannot read counters');

select * from finish();
rollback;
