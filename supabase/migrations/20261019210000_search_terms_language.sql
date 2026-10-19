-- search-assist also returns the query language (ISO 639-1) so YouTube results match it.
alter table public.search_terms_cache add column language text check (language ~ '^[a-z]{2}$');
-- Older rows lack the language and were made with a prompt that kept English keywords
-- for Czech Wikipedia; drop them so they're regenerated.
delete from public.search_terms_cache;
