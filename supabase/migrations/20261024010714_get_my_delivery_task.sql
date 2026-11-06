-- P03.1 authorized task-detail projection.
-- This function composes the two P01.1 read projections only.  It deliberately
-- does not read orders, returns, catalog, storage, business events or notes.

create function public.get_my_delivery_task(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_user_id uuid;
  l_authorized boolean;
  l_task jsonb;
  l_items jsonb;
begin
  if p_task_id is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_ARGUMENT';
  end if;

  /*
   * Keep authorization, task projection and item projection in one SQL
   * statement.  The materialized CTEs make the task scope explicit and keep
   * the response on one statement snapshot.  The P01.1 helpers remain the
   * only sources of task and item data.
   */
  with caller as materialized (
    select (select auth.uid()) as user_id
  ),
  gate as materialized (
    select
      c.user_id,
      c.user_id is not null
        and exists (
          select 1
          from public.profiles p
          where p.id = c.user_id
            and p.role = 'shipper'::public.user_role
        ) as authorized
    from caller c
  ),
  task_projection as materialized (
    select to_jsonb(t) as task_json
    from gate g
    cross join lateral public.read_my_delivery_tasks(p_task_id) t
    where g.authorized
  ),
  item_projection as materialized (
    select to_jsonb(i) as item_json
    from gate g
    cross join lateral public.read_my_delivery_task_items(p_task_id) i
    where g.authorized
  )
  select
    g.user_id,
    g.authorized,
    (select tp.task_json from task_projection tp limit 1),
    coalesce(
      (
        select jsonb_agg(ip.item_json order by ip.item_json ->> 'item_id')
        from item_projection ip
      ),
      '[]'::jsonb
    )
  into l_user_id, l_authorized, l_task, l_items
  from gate g;

  if not l_authorized then
    raise exception using
      errcode = '42501',
      message = 'DELIVERY_TASK_FORBIDDEN';
  end if;

  if l_task is null then
    -- The same error is returned for a nonexistent, foreign, reassigned or
    -- otherwise unauthorized task so existence and assignment are not leaked.
    raise exception using
      errcode = 'P0002',
      message = 'NOT_FOUND_OR_FORBIDDEN';
  end if;

  return jsonb_build_object(
    'task', l_task,
    'items', l_items,
    'notes', null,
    'notes_source', 'unavailable_schema',
    'as_of', statement_timestamp()
  );
end;
$$;

-- Keep the API executable by authenticated clients only.  The owner is the
-- existing locked-down NOLOGIN/NOBYPASSRLS projection role, not postgres.
grant create on schema public to sports_store_delivery_reader;
alter function public.get_my_delivery_task(uuid)
  owner to sports_store_delivery_reader;
revoke create on schema public from sports_store_delivery_reader;
revoke all on function public.get_my_delivery_task(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_delivery_task(uuid) to authenticated;

comment on function public.get_my_delivery_task(uuid) is
  'P03.1 shipper-only authorized detail projection composed from P01.1 read projections; notes are unavailable in the current schema.';

notify pgrst, 'reload schema';
