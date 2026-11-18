-- Fulbito FC · test de aislamiento entre ligas (multi-tenant).
-- Se pega en SQL Editor y se ejecuta DESPUÉS de schema.sql y backups.sql.
-- Las pruebas se deshacen solas (error a propósito dentro de un sub-bloque). Lo único que queda es
-- la fila 'test-iso-resultado' con {ok, fallas, detalle}; borrarla al terminar (ver el final).
--
-- Simula usuarios con el mismo mecanismo que usa la API (rol + claims del token):
--   A = dueño de la liga test-iso-a, B = dueño de test-iso-b, anon = sin login.

do $$
declare
  ua  constant text := '00000000-0000-4000-8000-00000000000a';
  ub  constant text := '00000000-0000-4000-8000-00000000000b';
  ok  int := 0;
  bad int := 0;
  log text := '';
  n   int;
  v   text;
begin
 delete from public.fulbito_state where id = 'test-iso-resultado';
 begin
  ---------------------------------------------------------------- A crea su liga
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-iso.local', 'role', 'authenticated')::text, true);
  insert into public.fulbito_state (id, data, name) values ('test-iso-a', '{"equipos":["A"]}', 'Liga A');
  ok := ok + 1; log := log || E'\nok   A crea su liga';

  -- A no puede crear la liga ''main''.
  begin
    insert into public.fulbito_state (id, data) values ('main', '{}');
    bad := bad + 1; log := log || E'\nFALLA A creó la liga main';
  exception when others then ok := ok + 1; log := log || E'\nok   A no puede crear main';
  end;

  -- Ids de link inválidos se rechazan.
  begin
    insert into public.fulbito_state (id, data) values ('X Mala', '{}');
    bad := bad + 1; log := log || E'\nFALLA aceptó un id inválido';
  exception when others then ok := ok + 1; log := log || E'\nok   id de link inválido rechazado';
  end;

  ---------------------------------------------------------------- B crea la suya
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-iso.local', 'role', 'authenticated')::text, true);
  insert into public.fulbito_state (id, data, name) values ('test-iso-b', '{"equipos":["B"]}', 'Liga B');
  ok := ok + 1; log := log || E'\nok   B crea su liga';

  -- B no puede modificar la liga de A.
  update public.fulbito_state set data = '{"hackeado":true}' where id = 'test-iso-a';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   B no puede editar la liga de A';
  else bad := bad + 1; log := log || E'\nFALLA B editó la liga de A'; end if;

  -- B no puede hacerse admin de la liga de A.
  update public.fulbito_state set admins = array['b@test-iso.local'] where id = 'test-iso-a';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   B no puede agregarse como admin de A';
  else bad := bad + 1; log := log || E'\nFALLA B se agregó como admin de A'; end if;

  -- B no puede borrar la liga de A.
  delete from public.fulbito_state where id = 'test-iso-a';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   B no puede borrar la liga de A';
  else bad := bad + 1; log := log || E'\nFALLA B borró la liga de A'; end if;

  -- B no ve ni guarda copias de seguridad de A.
  select count(*) into n from public.fulbito_backups where league_id = 'test-iso-a';
  if n = 0 then ok := ok + 1; log := log || E'\nok   B no ve las copias de A';
  else bad := bad + 1; log := log || E'\nFALLA B ve copias de A'; end if;
  begin
    insert into public.fulbito_backups (league_id, kind, data) values ('test-iso-a', 'manual', '{}');
    bad := bad + 1; log := log || E'\nFALLA B guardó una copia en la liga de A';
  exception when others then ok := ok + 1; log := log || E'\nok   B no puede guardar copias en A';
  end;

  -- B no puede robarse la propiedad de su liga hacia otro ni cambiar el dueño (el trigger lo fija).
  update public.fulbito_state set owner = ua::uuid where id = 'test-iso-b';
  select owner::text into v from public.fulbito_state where id = 'test-iso-b';
  if v = ub then ok := ok + 1; log := log || E'\nok   el dueño no se puede cambiar';
  else bad := bad + 1; log := log || E'\nFALLA cambió el dueño de la liga'; end if;

  -- Leer es público por diseño (los links se comparten): B sí ve los datos de A.
  select count(*) into n from public.fulbito_state where id = 'test-iso-a';
  if n = 1 then ok := ok + 1; log := log || E'\nok   leer es público (por diseño)';
  else bad := bad + 1; log := log || E'\nFALLA no se puede leer una liga ajena'; end if;

  ---------------------------------------------------------------- A invita a B como admin
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-iso.local', 'role', 'authenticated')::text, true);
  update public.fulbito_state set admins = array['B@Test-Iso.local'] where id = 'test-iso-a';
  select coalesce(admins[1], '') into v from public.fulbito_state where id = 'test-iso-a';
  if v = 'b@test-iso.local' then ok := ok + 1; log := log || E'\nok   A agrega a B como admin (email en minúscula)';
  else bad := bad + 1; log := log || E'\nFALLA no se guardó el admin: ' || v; end if;

  -- A tampoco puede tocar la liga de B.
  update public.fulbito_state set data = '{}' where id = 'test-iso-b';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   A no puede editar la liga de B';
  else bad := bad + 1; log := log || E'\nFALLA A editó la liga de B'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-iso.local', 'role', 'authenticated')::text, true);
  update public.fulbito_state set data = '{"cargado_por":"B"}' where id = 'test-iso-a';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   B, ya admin, puede cargar datos en A';
  else bad := bad + 1; log := log || E'\nFALLA B admin no pudo cargar en A'; end if;

  -- Pero siendo admin, B no puede borrar la liga (solo el dueño).
  delete from public.fulbito_state where id = 'test-iso-a';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   un admin no puede borrar la liga';
  else bad := bad + 1; log := log || E'\nFALLA un admin borró la liga'; end if;

  ---------------------------------------------------------------- Sin login
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  begin
    update public.fulbito_state set data = '{}' where id = 'test-iso-a';
    get diagnostics n = row_count;
    if n = 0 then ok := ok + 1; log := log || E'\nok   sin login no se puede editar';
    else bad := bad + 1; log := log || E'\nFALLA sin login editó una liga'; end if;
  exception when others then ok := ok + 1; log := log || E'\nok   sin login no se puede editar';
  end;
  begin
    insert into public.fulbito_state (id, data) values ('test-iso-c', '{}');
    bad := bad + 1; log := log || E'\nFALLA sin login creó una liga';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login no se puede crear';
  end;
  begin
    perform public.fulbito_daily_backup();
    bad := bad + 1; log := log || E'\nFALLA sin login corrió la copia diaria';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login no corre la copia diaria';
  end;

  -- Deshace todo lo de arriba (ligas de prueba, cambios de rol y de usuario).
  raise exception 'FIN_DEL_TEST';
 exception when others then
  if sqlerrm <> 'FIN_DEL_TEST' then bad := bad + 1; log := log || E'\nFALLA error inesperado: ' || sqlerrm; end if;
 end;
  -- Lo único que queda: el resultado, en una fila que se lee por la API y se borra después con
  --   delete from public.fulbito_state where id = 'test-iso-resultado';
  insert into public.fulbito_state (id, data, name)
  values ('test-iso-resultado', jsonb_build_object('ok', ok, 'fallas', bad, 'detalle', log), 'Resultado test');
end $$;
