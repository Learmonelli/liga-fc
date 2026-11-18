-- Fulbito FC y Liga FC · privacidad: los emails de dueños y administradores dejan de ser públicos.
-- Se pega en SQL Editor y se ejecuta DESPUÉS de schema.sql, backups.sql e interno.sql. Se puede volver a correr.
--
-- Antes: cualquiera con la clave pública (la que va en la app) podía leer owner_email y admins de todas
-- las ligas y grupos. Ahora:
--   * Las columnas owner_email y admins de fulbito_state no se pueden leer desde la app (permiso por columna).
--     El resto (id, nombre, datos, dueño como id, fechas) se sigue leyendo igual: links y carga en vivo no cambian.
--   * La app pregunta lo justo con funciones:
--       fulbito_my_role(liga)        -> 'owner' | 'admin' | null   (¿qué soy yo en esta liga?)
--       fulbito_league_admins(liga)  -> emails del dueño y los admins, SOLO si quien pregunta es dueño o admin
--       fulbito_my_leagues()         -> mis ligas y grupos (donde soy dueño o admin), sin emails de nadie
--   * Las reglas de escritura usan una función que sí puede ver los emails (security definer).

-- ¿Quien hace el pedido es dueño o admin de esa liga? (ve las columnas privadas: security definer)
create or replace function public.fulbito_league_admin(p_league text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.fulbito_state s
                 where s.id = p_league and public.fulbito_can_edit(s.id, s.owner, s.admins));
$$;

create or replace function public.fulbito_my_role(p_league text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then null
    when s.owner = auth.uid() then 'owner'
    when public.fulbito_can_edit(s.id, s.owner, s.admins) then 'admin'
  end
  from public.fulbito_state s where s.id = p_league;
$$;

create or replace function public.fulbito_league_admins(p_league text)
returns table (email text, role text)
language sql
stable
security definer
set search_path = public
as $$
  select x.email, x.role
  from public.fulbito_state s
  cross join lateral (
    select s.owner_email as email, 'owner'::text as role where coalesce(s.owner_email, '') <> ''
    union all
    select a, 'admin'::text from unnest(s.admins) as a
  ) x
  where s.id = p_league and public.fulbito_can_edit(s.id, s.owner, s.admins);
$$;

create or replace function public.fulbito_my_leagues()
returns table (id text, name text, role text, mode text)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.name,
         case when s.owner = auth.uid() then 'owner' else 'admin' end,
         s.data->>'mode'
  from public.fulbito_state s
  where auth.uid() is not null and (
    s.owner = auth.uid()
    or lower(coalesce(auth.jwt() ->> 'email', '')) = any (s.admins)
    or (s.id = 'main' and public.fulbito_is_admin())
  );
$$;

revoke all on function public.fulbito_league_admin(text) from public;
revoke all on function public.fulbito_my_role(text) from public;
revoke all on function public.fulbito_league_admins(text) from public;
revoke all on function public.fulbito_my_leagues() from public;
grant execute on function public.fulbito_league_admin(text) to anon, authenticated;
grant execute on function public.fulbito_my_role(text) to anon, authenticated;
grant execute on function public.fulbito_league_admins(text) to anon, authenticated;
grant execute on function public.fulbito_my_leagues() to anon, authenticated;

-- Reglas de escritura sin leer columnas privadas desde la consulta (las ve la función de arriba).
drop policy if exists fulbito_update on public.fulbito_state;
create policy fulbito_update on public.fulbito_state
  for update to authenticated
  using (public.fulbito_league_admin(id))
  with check (public.fulbito_league_admin(id));

drop policy if exists fulbito_backups_select on public.fulbito_backups;
create policy fulbito_backups_select on public.fulbito_backups
  for select to authenticated using (public.fulbito_league_admin(league_id));

drop policy if exists fulbito_backups_insert on public.fulbito_backups;
create policy fulbito_backups_insert on public.fulbito_backups
  for insert to authenticated with check (kind = 'manual' and public.fulbito_league_admin(league_id));

-- Lo importante: owner_email y admins ya no se pueden leer desde la app.
revoke select on public.fulbito_state from anon, authenticated;
grant select (id, name, data, owner, updated_at, updated_by, created_at) on public.fulbito_state to anon, authenticated;

-- Verificación: qué columnas puede leer la app (no tienen que aparecer owner_email ni admins).
select string_agg(column_name, ', ' order by column_name) as columnas_visibles_para_la_app
from information_schema.column_privileges
where table_schema = 'public' and table_name = 'fulbito_state' and grantee = 'anon' and privilege_type = 'SELECT';
