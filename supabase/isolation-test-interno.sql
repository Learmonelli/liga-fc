-- Fulbito FC · test de permisos del modo INTERNO (correr después de interno.sql).
-- Igual que isolation-test.sql: las pruebas se deshacen solas y solo queda la fila
-- 'test-iso-resultado' con {ok, fallas, detalle}. Borrarla al terminar:
--   delete from public.fulbito_state where id = 'test-iso-resultado';
--
-- A = dueño de la liga interna test-int-a · B = dueño de test-int-b (no es admin de A) · anon = sin login.

do $$
declare
  ua  constant text := '00000000-0000-4000-8000-0000000000aa';
  ub  constant text := '00000000-0000-4000-8000-0000000000bb';
  ok  int := 0;
  bad int := 0;
  log text := '';
  n   int;
  v   text;
  j   jsonb;
begin
 delete from public.fulbito_state where id = 'test-iso-resultado';
 begin
  ---------------------------------------------------------------- ligas de prueba
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-int.local', 'role', 'authenticated')::text, true);
  insert into public.fulbito_state (id, data, name) values ('test-int-a', '{"mode":"interno"}', 'Interna A');
  insert into public.fulbito_state (id, data, name) values ('test-camp-a', '{"teams":[]}', 'Campeonato A');
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-int.local', 'role', 'authenticated')::text, true);
  insert into public.fulbito_state (id, data, name) values ('test-int-b', '{"mode":"interno"}', 'Interna B');

  ---------------------------------------------------------------- sin login: carga
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

  insert into public.fulbito_players (league_id, id, data) values ('test-int-a', 'p1', '{"name":"Uno"}');
  ok := ok + 1; log := log || E'\nok   sin login suma un jugador';
  update public.fulbito_players set data = '{"name":"Uno","nickname":"Cara nueva"}' where league_id = 'test-int-a' and id = 'p1';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   sin login personaliza un jugador';
  else bad := bad + 1; log := log || E'\nFALLA no pudo editar el jugador'; end if;

  insert into public.fulbito_matches (league_id, id, data) values ('test-int-a', 'm1', '{"date":"2099-01-01","closed":false,"events":[]}');
  ok := ok + 1; log := log || E'\nok   sin login crea un partido';
  update public.fulbito_matches set data = '{"date":"2099-01-01","closed":false,"events":[{"side":"A"}]}' where league_id = 'test-int-a' and id = 'm1';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   sin login carga un gol';
  else bad := bad + 1; log := log || E'\nFALLA no pudo cargar el gol'; end if;

  begin
    update public.fulbito_matches set data = data || '{"closed":true}' where league_id = 'test-int-a' and id = 'm1';
    bad := bad + 1; log := log || E'\nFALLA sin login finalizó un partido';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO puede finalizar';
  end;
  begin
    insert into public.fulbito_matches (league_id, id, data) values ('test-int-a', 'm2', '{"closed":true}');
    bad := bad + 1; log := log || E'\nFALLA sin login creó un partido ya finalizado';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO crea partidos finalizados';
  end;
  begin
    delete from public.fulbito_matches where league_id = 'test-int-a' and id = 'm1';
    get diagnostics n = row_count;
    if n = 0 then ok := ok + 1; log := log || E'\nok   sin login NO puede borrar partidos';
    else bad := bad + 1; log := log || E'\nFALLA sin login borró un partido'; end if;
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO puede borrar partidos';
  end;
  begin
    delete from public.fulbito_players where league_id = 'test-int-a' and id = 'p1';
    get diagnostics n = row_count;
    if n = 0 then ok := ok + 1; log := log || E'\nok   sin login NO puede borrar jugadores';
    else bad := bad + 1; log := log || E'\nFALLA sin login borró un jugador'; end if;
  exception when others then ok := ok + 1; log := log || E'\nok   sin login NO puede borrar jugadores';
  end;
  begin
    insert into public.fulbito_players (league_id, id, data) values ('test-camp-a', 'p9', '{}');
    bad := bad + 1; log := log || E'\nFALLA cargó jugadores en una liga de campeonato';
  exception when others then ok := ok + 1; log := log || E'\nok   no se carga en ligas de campeonato';
  end;
  begin
    update public.fulbito_matches set league_id = 'test-int-b' where league_id = 'test-int-a' and id = 'm1';
    bad := bad + 1; log := log || E'\nFALLA movió un partido a otra liga';
  exception when others then ok := ok + 1; log := log || E'\nok   un partido no se puede mover de liga';
  end;
  begin
    insert into public.fulbito_matches (league_id, id, data) values ('test-int-a', 'id con espacios', '{}');
    bad := bad + 1; log := log || E'\nFALLA aceptó un id inválido';
  exception when others then ok := ok + 1; log := log || E'\nok   id inválido rechazado';
  end;
  begin
    perform public.fulbito_autoclose();
    bad := bad + 1; log := log || E'\nFALLA sin login corrió el cierre automático';
  exception when others then ok := ok + 1; log := log || E'\nok   sin login no corre el cierre automático';
  end;

  ---------------------------------------------------------------- B (logueado, no admin de A)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-int.local', 'role', 'authenticated')::text, true);
  begin
    update public.fulbito_matches set data = data || '{"closed":true}' where league_id = 'test-int-a' and id = 'm1';
    bad := bad + 1; log := log || E'\nFALLA B finalizó un partido de A';
  exception when others then ok := ok + 1; log := log || E'\nok   B NO finaliza partidos de A';
  end;
  delete from public.fulbito_matches where league_id = 'test-int-a' and id = 'm1';
  get diagnostics n = row_count;
  if n = 0 then ok := ok + 1; log := log || E'\nok   B NO borra partidos de A';
  else bad := bad + 1; log := log || E'\nFALLA B borró un partido de A'; end if;
  begin
    perform public.fulbito_restore_interno('test-int-a', '[]', '[]');
    bad := bad + 1; log := log || E'\nFALLA B restauró (vació) la liga de A';
  exception when others then ok := ok + 1; log := log || E'\nok   B NO restaura copias en A';
  end;

  ---------------------------------------------------------------- A (dueño)
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-int.local', 'role', 'authenticated')::text, true);
  update public.fulbito_matches set data = data || '{"closed":true}' where league_id = 'test-int-a' and id = 'm1';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   el dueño finaliza el partido';
  else bad := bad + 1; log := log || E'\nFALLA el dueño no pudo finalizar'; end if;

  ---------------------------------------------------------------- partido finalizado
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  begin
    update public.fulbito_matches set data = data || '{"events":[]}' where league_id = 'test-int-a' and id = 'm1';
    bad := bad + 1; log := log || E'\nFALLA sin login cambió un partido finalizado';
  exception when others then ok := ok + 1; log := log || E'\nok   finalizado: sin login no cambia goles';
  end;
  begin
    update public.fulbito_matches set data = data || '{"closed":false}' where league_id = 'test-int-a' and id = 'm1';
    bad := bad + 1; log := log || E'\nFALLA sin login reabrió un partido';
  exception when others then ok := ok + 1; log := log || E'\nok   finalizado: sin login no lo reabre';
  end;
  update public.fulbito_matches set data = jsonb_set(data, '{comments}', '[{"text":"buen partido"}]') where league_id = 'test-int-a' and id = 'm1';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   finalizado: sin login sí comenta';
  else bad := bad + 1; log := log || E'\nFALLA no se pudo comentar'; end if;

  ---------------------------------------------------------------- A: admin borra y restaura
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'email', 'a@test-int.local', 'role', 'authenticated')::text, true);
  update public.fulbito_state set admins = array['b@test-int.local'] where id = 'test-int-a';
  perform public.fulbito_restore_interno('test-int-a', '[{"id":"p1","name":"Uno"},{"id":"p2","name":"Dos"}]', '[]');
  select count(*) into n from public.fulbito_players where league_id = 'test-int-a';
  if n = 2 then ok := ok + 1; log := log || E'\nok   el dueño restaura una copia';
  else bad := bad + 1; log := log || E'\nFALLA restaurar dejó ' || n || ' jugadores'; end if;
  -- B ya es admin de A: ahora sí borra.
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'email', 'b@test-int.local', 'role', 'authenticated')::text, true);
  delete from public.fulbito_players where league_id = 'test-int-a' and id = 'p2';
  get diagnostics n = row_count;
  if n = 1 then ok := ok + 1; log := log || E'\nok   un admin invitado borra jugadores';
  else bad := bad + 1; log := log || E'\nFALLA el admin invitado no pudo borrar'; end if;

  ---------------------------------------------------------------- servidor
  execute 'reset role';
  insert into public.fulbito_matches (league_id, id, data) values ('test-int-a', 'm3', '{"date":"2000-01-01","closed":false}');
  perform public.fulbito_autoclose();
  select data->>'closed' into v from public.fulbito_matches where league_id = 'test-int-a' and id = 'm3';
  if v = 'true' then ok := ok + 1; log := log || E'\nok   el cierre automático finaliza partidos viejos';
  else bad := bad + 1; log := log || E'\nFALLA el cierre automático no cerró'; end if;
  j := public.fulbito_league_payload('test-int-a');
  if jsonb_array_length(j->'players') = 1 and jsonb_array_length(j->'matches') = 1 then
    ok := ok + 1; log := log || E'\nok   la copia diaria incluye jugadores y partidos';
  else bad := bad + 1; log := log || E'\nFALLA la copia diaria no trae todo: ' || left(j::text, 200); end if;

  raise exception 'FIN_DEL_TEST';
 exception when others then
  if sqlerrm <> 'FIN_DEL_TEST' then bad := bad + 1; log := log || E'\nFALLA error inesperado: ' || sqlerrm; end if;
 end;
  insert into public.fulbito_state (id, data, name)
  values ('test-iso-resultado', jsonb_build_object('ok', ok, 'fallas', bad, 'detalle', log), 'Resultado test');
end $$;
