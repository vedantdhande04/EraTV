create extension if not exists pgcrypto;

create table if not exists public.shared_playlists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  playlist_url text not null,
  playlist_name text,
  message text,
  era text,
  created_at timestamptz not null default now()
);

alter table public.shared_playlists add column if not exists name text;
alter table public.shared_playlists add column if not exists playlist_url text;
alter table public.shared_playlists add column if not exists playlist_name text;
alter table public.shared_playlists add column if not exists message text;
alter table public.shared_playlists add column if not exists era text;
alter table public.shared_playlists add column if not exists created_at timestamptz default now();

grant usage on schema public to anon, authenticated;
grant select, insert on table public.shared_playlists to anon, authenticated;

alter table public.shared_playlists enable row level security;

drop policy if exists "Anyone can share a playlist" on public.shared_playlists;
drop policy if exists "Anyone can read shared playlists" on public.shared_playlists;

create policy "Anyone can share a playlist"
  on public.shared_playlists
  for insert
  to anon, authenticated
  with check (
    char_length(name) between 1 and 80
    and char_length(playlist_url) between 20 and 240
    and (message is null or char_length(message) <= 48)
  );

create policy "Anyone can read shared playlists"
  on public.shared_playlists
  for select
  to anon, authenticated
  using (true);

do $$
begin
  alter publication supabase_realtime add table public.shared_playlists;
exception
  when duplicate_object then null;
end $$;
