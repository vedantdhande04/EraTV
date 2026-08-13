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

create table if not exists public.share_ip_cooldowns (
  ip text primary key,
  last_shared_at timestamptz not null default now()
);

alter table public.share_ip_cooldowns enable row level security;
revoke all on table public.share_ip_cooldowns from public, anon, authenticated;

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

create or replace function public.request_client_ip()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  headers json;
  raw text;
begin
  begin
    headers := current_setting('request.headers', true)::json;
  exception
    when others then
      headers := '{}'::json;
  end;
  raw := coalesce(
    headers->>'x-forwarded-for',
    headers->>'x-real-ip',
    headers->>'cf-connecting-ip',
    ''
  );
  raw := trim(split_part(raw, ',', 1));
  if raw = '' then
    return null;
  end if;
  return raw;
end;
$$;

create or replace function public.share_cooldown_remaining()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  ip text;
  last_at timestamptz;
  left_secs integer;
begin
  ip := public.request_client_ip();
  if ip is null then
    return 0;
  end if;
  select last_shared_at into last_at
  from public.share_ip_cooldowns
  where share_ip_cooldowns.ip = ip;
  if last_at is null then
    return 0;
  end if;
  left_secs := ceil(extract(epoch from (last_at + interval '12 hours' - now())));
  return greatest(0, left_secs);
end;
$$;

create or replace function public.shared_playlists_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ip text;
  last_at timestamptz;
  left_secs integer;
begin
  ip := public.request_client_ip();
  if ip is null then
    raise exception 'Could not verify your network. Try again.';
  end if;

  select last_shared_at into last_at
  from public.share_ip_cooldowns
  where share_ip_cooldowns.ip = ip;

  if last_at is not null then
    left_secs := ceil(extract(epoch from (last_at + interval '12 hours' - now())));
    if left_secs > 0 then
      raise exception 'SHARE_COOLDOWN:%', left_secs;
    end if;
  end if;

  insert into public.share_ip_cooldowns (ip, last_shared_at)
  values (ip, now())
  on conflict (ip) do update
    set last_shared_at = excluded.last_shared_at;

  return new;
end;
$$;

drop trigger if exists shared_playlists_guard on public.shared_playlists;
create trigger shared_playlists_guard
before insert on public.shared_playlists
for each row execute function public.shared_playlists_guard();

revoke all on function public.request_client_ip() from public, anon, authenticated;
grant execute on function public.share_cooldown_remaining() to anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.shared_playlists;
exception
  when duplicate_object then null;
end $$;
