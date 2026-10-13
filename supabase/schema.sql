-- Familienzeit: Datenbank für Supabase
-- Einmal komplett im Supabase-Dashboard unter „SQL Editor“ ausführen.
--
-- Sicherheitsprinzip: Die Tabellen sind für den öffentlichen Schlüssel (anon) gesperrt.
-- Zugriff gibt es nur über die Funktionen unten, und die verlangen den Familien-Schlüssel
-- aus dem App-Link (#k=…). In der Datenbank liegt nur dessen SHA-256-Prüfsumme.

create table if not exists public.families (
  id            uuid primary key default gen_random_uuid(),
  key_hash      text unique not null,
  setup         jsonb not null default '{}'::jsonb,
  setup_updated timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

create table if not exists public.done (
  family_id  uuid not null references public.families(id) on delete cascade,
  day        date not null,
  item       text not null,            -- "<kindId>_<aufgabeId>"
  done       boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (family_id, day, item)
);

alter table public.families enable row level security;
alter table public.done enable row level security;
-- Keine Policies: direkter Tabellenzugriff ist für anon/authenticated gesperrt.
revoke all on public.families from anon, authenticated;
revoke all on public.done from anon, authenticated;

-- Interne Hilfsfunktion: Familie zum Schlüssel finden
create or replace function public.fz_family(p_key text)
returns uuid
language sql stable security definer set search_path = public
as $$
  select id from public.families
  where key_hash = encode(sha256(convert_to(p_key, 'UTF8')), 'hex')
$$;
revoke execute on function public.fz_family(text) from public, anon, authenticated;

-- Laden: Einstellungen + Häkchen eines Zeitraums
create or replace function public.fz_load(p_key text, p_from date, p_to date)
returns json
language plpgsql stable security definer set search_path = public
as $$
declare
  fam public.families;
  marks json;
begin
  select * into fam from public.families
  where key_hash = encode(sha256(convert_to(p_key, 'UTF8')), 'hex');
  if fam.id is null then
    return null;
  end if;

  select coalesce(json_object_agg(d.day::text, d.items), '{}'::json) into marks
  from (
    select day, json_object_agg(item, done) as items
    from public.done
    where family_id = fam.id and day between p_from and p_to
    group by day
  ) d;

  return json_build_object('setup', fam.setup, 'setup_updated', fam.setup_updated, 'done', marks);
end;
$$;

-- Einstellungen speichern (legt die Familie beim ersten Mal an)
create or replace function public.fz_save_setup(p_key text, p_setup jsonb)
returns timestamptz
language plpgsql volatile security definer set search_path = public
as $$
declare
  ts timestamptz := now();
begin
  if p_key is null or length(p_key) < 16 then
    raise exception 'Schlüssel zu kurz';
  end if;
  if pg_column_size(p_setup) > 200000 then
    raise exception 'Einstellungen zu groß';
  end if;
  insert into public.families (key_hash, setup, setup_updated)
  values (encode(sha256(convert_to(p_key, 'UTF8')), 'hex'), p_setup, ts)
  on conflict (key_hash) do update set setup = excluded.setup, setup_updated = ts;
  return ts;
end;
$$;

-- Häkchen setzen oder entfernen
create or replace function public.fz_set_done(p_key text, p_day date, p_item text, p_done boolean)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  fid uuid := public.fz_family(p_key);
begin
  if fid is null then
    raise exception 'Unbekannte Familie';
  end if;
  insert into public.done (family_id, day, item, done, updated_at)
  values (fid, p_day, left(p_item, 120), p_done, now())
  on conflict (family_id, day, item) do update set done = excluded.done, updated_at = now();
  -- Alte Häkchen (älter als 90 Tage) aufräumen
  delete from public.done where family_id = fid and day < current_date - 90;
end;
$$;

revoke execute on function public.fz_load(text, date, date) from public;
revoke execute on function public.fz_save_setup(text, jsonb) from public;
revoke execute on function public.fz_set_done(text, date, text, boolean) from public;
grant execute on function public.fz_load(text, date, date) to anon, authenticated;
grant execute on function public.fz_save_setup(text, jsonb) to anon, authenticated;
grant execute on function public.fz_set_done(text, date, text, boolean) to anon, authenticated;
