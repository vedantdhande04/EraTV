create extension if not exists pgcrypto;

create table if not exists public.shared_playlists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  playlist_url text not null,
  era text,
  created_at timestamptz not null default now()
);

alter table public.shared_playlists add column if not exists name text;
alter table public.shared_playlists add column if not exists playlist_url text;
alter table public.shared_playlists add column if not exists era text;
alter table public.shared_playlists add column if not exists created_at timestamptz default now();

grant usage on schema public to anon, authenticated;
grant insert on table public.shared_playlists to anon, authenticated;

alter table public.shared_playlists enable row level security;

drop policy if exists "Anyone can share a playlist" on public.shared_playlists;

create policy "Anyone can share a playlist"
  on public.shared_playlists
  for insert
  to anon, authenticated
  with check (true);
