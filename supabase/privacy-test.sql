-- Fulbito FC y Liga FC · test de privacidad (correr DESPUÉS de privacy.sql).
-- Igual que los otros tests: todo se deshace solo y queda la fila 'test-iso-resultado' con {ok, fallas, detalle}.
-- Borrarla al terminar:  delete from public.fulbito_state where id = 'test-iso-resultado';
--
-- A = dueño de test-priv-a · B = admin de A (invitado por email) · C = logueado, no es nada · anon = sin login.

do $$
declare
  ua constant text := '00000000-0000-4000-8000-0000000000a1';
  ub constant text := '00000000-0000-4000-8000-0000000000b1';
  uc constant text := '00000000-0000-4000-8000-0000000000c1';
  ok int := 0; bad int := 0; log text := ''; n int; v text;
begin
 delete from public.fulbito_state where id = 'test-iso-resultado';
 begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-priv.local', 'role', 'authenticated')::text, true);
  insert into public.fulbito_state (id, data, name, admins) values ('test-priv-a', '{"mode":"interno"}', 'Grupo A', array['b@test-priv.local']);

  ---------------------------------------------------------------- sin login
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  begin
    select owner_email into v from public.fulbito_state where id = 'test-priv-a';
    bad := bad + 1; log := log || E'\nFALLA sin login se lee owner_email: ' || coalesce(v, '');
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO se lee el email del dueño';
  end;
  begin
    select array_to_string(admins, ',') into v from public.fulbito_state where id = 'test-priv-a';
    bad := bad + 1; log := log || E'\nFALLA sin login se leen los admins: ' || coalesce(v, '');
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO se leen los emails de admins';
  end;
  begin
    select count(*) into n from public.fulbito_state where admins @> array['b@test-priv.local'];
    bad := bad + 1; log := log || E'\nFALLA sin login se puede buscar por email de admin';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO se puede buscar por email';
  end;
  select count(*) into n from public.fulbito_state where id = 'test-priv-a' and name = 'Grupo A' and data->>'mode' = 'interno';
  if n = 1 then ok := ok + 1; log := log || E'\nok   sin login se sigue leyendo nombre y datos (el link anda)';
  else bad := bad + 1; log := log || E'\nFALLA sin login no se lee el grupo'; end if;
  select count(*) into n from public.fulbito_league_admins('test-priv-a');
  if n = 0 then ok := ok + 1; log := log || E'\nok   sin login la lista de admins viene vacía';
  else bad := bad + 1; log := log || E'\nFALLA sin login la función devuelve emails'; end if;
  v := public.fulbito_my_role('test-priv-a');
  if v is null then ok := ok + 1; log := log || E'\nok   sin login no tiene rol';
  else bad := bad + 1; log := log || E'\nFALLA sin login tiene rol ' || v; end if;

  ---------------------------------------------------------------- A (dueño)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-priv.local', 'role', 'authenticated')::text, true);
  v := public.fulbito_my_role('test-priv-a');
  if v = 'owner' then ok := ok + 1; log := log || E'\nok   el dueño se ve como dueño';
  else bad := bad + 1; log := log || E'\nFALLA rol del dueño: ' || coalesce(v, 'null'); end if;
  select string_agg(role || ':' || email, ',' order by role desc) into v from public.fulbito_league_admins('test-priv-a');
  if v = 'owner:a@test-priv.local,admin:b@test-priv.local' then ok := ok + 1; log := log || E'\nok   el dueño ve la lista de admins';
  else bad := bad + 1; log := log || E'\nFALLA lista para el dueño: ' || coalesce(v, 'vacía'); end if;
  update public.fulbito_state set admins = array['b@test-priv.local', 'd@test-priv.local'] where id = 'test-priv-a';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   el dueño cambia los admins';
  else bad := bad + 1; log := log || E'\nFALLA el dueño no pudo cambiar admins'; end if;
  insert into public.fulbito_backups (league_id, kind, data) values ('test-priv-a', 'manual', '{}');
  ok := ok + 1; log := log || E'\nok   el dueño guarda una copia';

  ---------------------------------------------------------------- B (admin invitado)
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-priv.local', 'role', 'authenticated')::text, true);
  v := public.fulbito_my_role('test-priv-a');
  if v = 'admin' then ok := ok + 1; log := log || E'\nok   el admin invitado se ve como admin';
  else bad := bad + 1; log := log || E'\nFALLA rol del admin: ' || coalesce(v, 'null'); end if;
  update public.fulbito_state set name = 'Grupo A FC' where id = 'test-priv-a';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   el admin edita el grupo';
  else bad := bad + 1; log := log || E'\nFALLA el admin no pudo editar'; end if;
  select count(*) into n from public.fulbito_backups where league_id = 'test-priv-a';
  if n = 1 then ok := ok + 1; log := log || E'\nok   el admin ve las copias';
  else bad := bad + 1; log := log || E'\nFALLA el admin ve ' || n || ' copias'; end if;
  select count(*) into n from public.fulbito_my_leagues() where id = 'test-priv-a' and role = 'admin';
  if n = 1 then ok := ok + 1; log := log || E'\nok   el grupo aparece en "mis grupos" del admin';
  else bad := bad + 1; log := log || E'\nFALLA no aparece en mis grupos del admin'; end if;

  ---------------------------------------------------------------- C (logueado, no es nada)
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'email', 'c@test-priv.local', 'role', 'authenticated')::text, true);
  v := public.fulbito_my_role('test-priv-a');
  if v is null then ok := ok + 1; log := log || E'\nok   otro usuario no tiene rol';
  else bad := bad + 1; log := log || E'\nFALLA otro usuario tiene rol ' || v; end if;
  select count(*) into n from public.fulbito_league_admins('test-priv-a');
  if n = 0 then ok := ok + 1; log := log || E'\nok   otro usuario NO ve los emails de admins';
  else bad := bad + 1; log := log || E'\nFALLA otro usuario ve ' || n || ' emails'; end if;
  begin
    select owner_email into v from public.fulbito_state where id = 'test-priv-a';
    bad := bad + 1; log := log || E'\nFALLA un logueado lee owner_email';
  exception when others then ok := ok + 1; log := log || E'\nok   un logueado tampoco lee owner_email';
  end;
  update public.fulbito_state set name = 'hackeado' where id = 'test-priv-a';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   otro usuario NO edita el grupo';
  else bad := bad + 1; log := log || E'\nFALLA otro usuario editó el grupo'; end if;
  select count(*) into n from public.fulbito_backups where league_id = 'test-priv-a';
  if n = 0 then ok := ok + 1; log := log || E'\nok   otro usuario NO ve las copias';
  else bad := bad + 1; log := log || E'\nFALLA otro usuario ve copias'; end if;
  select count(*) into n from public.fulbito_my_leagues() where id = 'test-priv-a';
  if n = 0 then ok := ok + 1; log := log || E'\nok   el grupo NO aparece en "mis grupos" de otro';
  else bad := bad + 1; log := log || E'\nFALLA aparece en mis grupos de otro'; end if;

  raise exception 'FIN_DEL_TEST';
 exception when others then
  if sqlerrm <> 'FIN_DEL_TEST' then bad := bad + 1; log := log || E'\nFALLA error inesperado: ' || sqlerrm; end if;
 end;
  insert into public.fulbito_state (id, data, name)
  values ('test-iso-resultado', jsonb_build_object('ok', ok, 'fallas', bad, 'detalle', log), 'Resultado test');
end $$;
