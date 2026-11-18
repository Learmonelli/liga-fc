-- Fulbito FC · modo INTERNO (estilo Piel Morena: plantel, partidos A vs B, goles, premios, ranking).
-- Se pega en SQL Editor y se ejecuta DESPUÉS de schema.sql y backups.sql. Se puede volver a correr.
--
-- Una liga es de modo interno si su fila de fulbito_state tiene data.mode = 'interno'.
-- Sus jugadores y partidos van en dos tablas aparte (una fila por jugador / partido), así varias
-- personas cargan a la vez sin pisarse.
--
-- Permisos (en las ligas de modo interno):
--   * Leer: cualquiera (el link se comparte).
--   * Cargar jugadores y partidos (goles, equipos, premios, pronósticos): CUALQUIERA, sin login.
--   * Finalizar un partido, editar uno finalizado (salvo comentarios) y borrar: solo el dueño y
--     los admins de ESA liga.
--   * Todos los días a las 02:55 (Argentina) el servidor finaliza los partidos de días anteriores.

create table if not exists public.fulbito_players (
  league_id  text not null references public.fulbito_state(id) on delete cascade,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (league_id, id)
);

create table if not exists public.fulbito_matches (
  league_id  text not null references public.fulbito_state(id) on delete cascade,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (league_id, id)
);
create index if not exists fulbito_matches_open_idx on public.fulbito_matches (league_id) where coalesce((data->>'closed')::boolean, false) = false;

-- ¿La liga es de modo interno?
create or replace function public.fulbito_is_interno(p_league text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from public.fulbito_state where id = p_league and data->>'mode' = 'interno');
$$;

-- ¿Quien hace el pedido es dueño o admin de esa liga?
create or replace function public.fulbito_league_admin(p_league text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from public.fulbito_state s
                 where s.id = p_league and public.fulbito_can_edit(s.id, s.owner, s.admins));
$$;

-- Reglas comunes a jugadores y partidos: ids válidos, tamaño acotado, cantidad acotada por liga,
-- no se mueven de liga, updated_at automático.
create or replace function public.fulbito_row_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  n int;
  max_rows int := case when tg_table_name = 'fulbito_players' then 300 else 3000 end;
begin
  if tg_op = 'UPDATE' and (new.league_id <> old.league_id or new.id <> old.id) then
    raise exception 'No se puede cambiar la liga ni el id' using errcode = '42501';
  end if;
  if new.id !~ '^[A-Za-z0-9_-]{1,64}$' then
    raise exception 'Id inválido' using errcode = '22023';
  end if;
  if octet_length(new.data::text) > 65536 then
    raise exception 'Demasiados datos en una sola fila' using errcode = '22023';
  end if;
  new.data := jsonb_set(new.data, '{id}', to_jsonb(new.id), true); -- el id del documento = el de la fila
  if tg_op = 'INSERT' then
    execute format('select count(*) from public.%I where league_id = $1', tg_table_name) into n using new.league_id;
    if n >= max_rows then
      raise exception 'Se llegó al máximo de filas para esta liga' using errcode = '22023';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Partidos: solo un admin finaliza; un partido finalizado solo admite comentarios (salvo admin).
-- Los procesos del servidor (cierre automático, restaurar copia) no pasan por acá: no corren como
-- anon/authenticated.
create or replace function public.fulbito_match_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  was_closed boolean := tg_op = 'UPDATE' and coalesce((old.data->>'closed')::boolean, false);
  now_closed boolean := coalesce((new.data->>'closed')::boolean, false);
begin
  if current_user not in ('anon', 'authenticated') then return new; end if;
  if public.fulbito_league_admin(new.league_id) then return new; end if;
  if was_closed then
    if (new.data - 'comments') is distinct from (old.data - 'comments') then
      raise exception 'El partido está finalizado: solo se pueden agregar comentarios' using errcode = '42501';
    end if;
  elsif now_closed then
    raise exception 'Solo un administrador de la liga puede finalizar partidos' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fulbito_players_guard on public.fulbito_players;
create trigger fulbito_players_guard before insert or update on public.fulbito_players
for each row execute function public.fulbito_row_guard();

drop trigger if exists fulbito_matches_guard on public.fulbito_matches;
create trigger fulbito_matches_guard before insert or update on public.fulbito_matches
for each row execute function public.fulbito_row_guard();

drop trigger if exists fulbito_matches_closed on public.fulbito_matches;
create trigger fulbito_matches_closed before insert or update on public.fulbito_matches
for each row execute function public.fulbito_match_guard();

alter table public.fulbito_players enable row level security;
alter table public.fulbito_matches enable row level security;

grant select, insert, update on public.fulbito_players to anon, authenticated;
grant select, insert, update on public.fulbito_matches to anon, authenticated;
grant delete on public.fulbito_players to authenticated;
grant delete on public.fulbito_matches to authenticated;
revoke delete on public.fulbito_players from anon;
revoke delete on public.fulbito_matches from anon;

drop policy if exists fulbito_players_select on public.fulbito_players;
create policy fulbito_players_select on public.fulbito_players for select using (true);
drop policy if exists fulbito_players_insert on public.fulbito_players;
create policy fulbito_players_insert on public.fulbito_players for insert
  with check (public.fulbito_is_interno(league_id));
drop policy if exists fulbito_players_update on public.fulbito_players;
create policy fulbito_players_update on public.fulbito_players for update
  using (public.fulbito_is_interno(league_id)) with check (public.fulbito_is_interno(league_id));
drop policy if exists fulbito_players_delete on public.fulbito_players;
create policy fulbito_players_delete on public.fulbito_players for delete to authenticated
  using (public.fulbito_league_admin(league_id));

drop policy if exists fulbito_matches_select on public.fulbito_matches;
create policy fulbito_matches_select on public.fulbito_matches for select using (true);
drop policy if exists fulbito_matches_insert on public.fulbito_matches;
create policy fulbito_matches_insert on public.fulbito_matches for insert
  with check (public.fulbito_is_interno(league_id));
drop policy if exists fulbito_matches_update on public.fulbito_matches;
create policy fulbito_matches_update on public.fulbito_matches for update
  using (public.fulbito_is_interno(league_id)) with check (public.fulbito_is_interno(league_id));
drop policy if exists fulbito_matches_delete on public.fulbito_matches;
create policy fulbito_matches_delete on public.fulbito_matches for delete to authenticated
  using (public.fulbito_league_admin(league_id));

-- Restaurar una copia (jugadores y partidos): solo dueño y admins de la liga.
create or replace function public.fulbito_restore_interno(p_league text, p_players jsonb, p_matches jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fulbito_league_admin(p_league) then
    raise exception 'Solo los administradores de la liga pueden restaurar copias' using errcode = '42501';
  end if;
  if not public.fulbito_is_interno(p_league) then
    raise exception 'Esta liga no es de modo interno' using errcode = '22023';
  end if;
  delete from public.fulbito_players where league_id = p_league;
  delete from public.fulbito_matches where league_id = p_league;
  insert into public.fulbito_players (league_id, id, data)
  select p_league, x->>'id', x from jsonb_array_elements(coalesce(p_players, '[]'::jsonb)) as t(x)
  where x->>'id' ~ '^[A-Za-z0-9_-]{1,64}$';
  insert into public.fulbito_matches (league_id, id, data)
  select p_league, x->>'id', x from jsonb_array_elements(coalesce(p_matches, '[]'::jsonb)) as t(x)
  where x->>'id' ~ '^[A-Za-z0-9_-]{1,64}$';
end;
$$;
revoke all on function public.fulbito_restore_interno(text, jsonb, jsonb) from public, anon;
grant execute on function public.fulbito_restore_interno(text, jsonb, jsonb) to authenticated;

-- Cierre automático: los partidos abiertos de días anteriores (hora de Argentina) quedan finalizados.
create or replace function public.fulbito_autoclose()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  update public.fulbito_matches
     set data = jsonb_set(data, '{closed}', 'true'::jsonb, true)
   where coalesce((data->>'closed')::boolean, false) = false
     and data->>'date' ~ '^\d{4}-\d{2}-\d{2}$'
     and data->>'date' < to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date, 'YYYY-MM-DD');
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.fulbito_autoclose() from public, anon, authenticated;

select cron.unschedule('fulbito-autoclose') where exists (select 1 from cron.job where jobname = 'fulbito-autoclose');
-- 05:55 UTC = 02:55 en Argentina (antes de la copia diaria de las 03:00).
select cron.schedule('fulbito-autoclose', '55 5 * * *', $$select public.fulbito_autoclose();$$);

-- La copia diaria también guarda jugadores y partidos de las ligas de modo interno.
create or replace function public.fulbito_league_payload(p_league text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when s.data->>'mode' = 'interno' then s.data || jsonb_build_object(
      'players', coalesce((select jsonb_agg(p.data order by p.id) from public.fulbito_players p where p.league_id = s.id), '[]'::jsonb),
      'matches', coalesce((select jsonb_agg(m.data order by m.id) from public.fulbito_matches m where m.league_id = s.id), '[]'::jsonb))
    else s.data end
  from public.fulbito_state s where s.id = p_league;
$$;
revoke all on function public.fulbito_league_payload(text) from public, anon, authenticated;

create or replace function public.fulbito_daily_backup()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer := 0;
  r record;
  payload jsonb;
begin
  for r in select id from public.fulbito_state loop
    payload := public.fulbito_league_payload(r.id);
    if not exists (
      select 1 from public.fulbito_backups b
      where b.id = (select max(id) from public.fulbito_backups where league_id = r.id) and b.data = payload
    ) then
      insert into public.fulbito_backups (league_id, kind, data, created_by) values (r.id, 'auto', payload, null);
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;
revoke all on function public.fulbito_daily_backup() from public, anon, authenticated;

-- Cambios en vivo.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'fulbito_players') then
    alter publication supabase_realtime add table public.fulbito_players;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'fulbito_matches') then
    alter publication supabase_realtime add table public.fulbito_matches;
  end if;
end $$;

select (select count(*) from cron.job where jobname = 'fulbito-autoclose') as cierre_programado;
