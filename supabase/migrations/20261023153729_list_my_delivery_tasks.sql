-- P02.1: one authorized, filterable and paginated task-list read.
--
-- The existing P01.1 projection remains the authorization boundary.  This
-- function only joins delivery_tasks for its created_at sort tuple; it does
-- not expose another delivery_tasks column or read orders/returns directly.
create function public.list_my_delivery_tasks(
  p_kind public.delivery_task_kind default null,
  p_state_group text default null,
  p_query text default null,
  p_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l_user_id uuid;
  l_trim_chars constant text := E' \t\n\r\f' || chr(11);
  l_state_group text;
  l_query text;
  l_filter_hash text;
  l_cursor_json jsonb;
  l_cursor_created_at timestamptz;
  l_cursor_task_id uuid;
  l_result jsonb;
begin
  l_user_id := (select auth.uid());
  if l_user_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = l_user_id
      and p.role = 'shipper'
  ) then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  l_state_group := nullif(
    lower(btrim(coalesce(p_state_group, ''), l_trim_chars)),
    ''
  );
  if l_state_group is not null
     and l_state_group not in ('waiting', 'in_transit', 'completed') then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  -- Empty search is the unfiltered form.  Search is performed with position,
  -- rather than LIKE, so '%' and '_' remain literal user input.
  l_query := nullif(
    lower(btrim(coalesce(p_query, ''), l_trim_chars)),
    ''
  );
  if l_query is not null and char_length(l_query) > 200 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_filter_hash := md5(
    l_user_id::text || chr(31)
      || coalesce(p_kind::text, '') || chr(31)
      || coalesce(l_state_group, '') || chr(31)
      || coalesce(l_query, '')
  );

  if p_cursor is not null then
    if p_cursor = ''
       or p_cursor <> btrim(p_cursor, l_trim_chars)
       or char_length(p_cursor) > 4096 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;

    begin
      l_cursor_json := convert_from(decode(p_cursor, 'base64'), 'UTF8')::jsonb;
      if jsonb_typeof(l_cursor_json) <> 'object'
         or not (l_cursor_json ?& array[
           'v', 'uid', 'filter', 'created_at', 'task_id'
         ])
         or jsonb_typeof(l_cursor_json->'v') <> 'number'
         or jsonb_typeof(l_cursor_json->'uid') <> 'string'
         or jsonb_typeof(l_cursor_json->'filter') <> 'string'
         or l_cursor_json->>'v' <> '1'
         or l_cursor_json->>'uid' <> l_user_id::text
         or l_cursor_json->>'filter' <> l_filter_hash
         or jsonb_typeof(l_cursor_json->'created_at') <> 'string'
         or jsonb_typeof(l_cursor_json->'task_id') <> 'string' then
        raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
      end if;

      l_cursor_created_at := (l_cursor_json->>'created_at')::timestamptz;
      l_cursor_task_id := (l_cursor_json->>'task_id')::uuid;
      if not isfinite(l_cursor_created_at) then
        raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
      end if;
    exception
      when others then
        if sqlstate = '22023' then
          raise;
        end if;
        raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end;
  end if;

  -- All counts and page rows are derived from the same materialized
  -- authorized projection.  The cursor is a keyset tuple over the stable
  -- (created_at DESC, task_id DESC) order and is bound to this user/filter.
  with authorized as materialized (
    select projection.*, task.created_at
    from public.read_my_delivery_tasks(null::uuid) as projection
    join public.delivery_tasks as task on task.id = projection.task_id
  ),
  filtered as materialized (
    select *
    from authorized
    where (p_kind is null or kind = p_kind)
      and (
        l_query is null
        or position(l_query in lower(coalesce(order_id::text, ''))) > 0
        or position(l_query in lower(coalesce(destination_name, ''))) > 0
      )
  ),
  grouped as materialized (
    select *
    from filtered
    where l_state_group is null
      or (l_state_group = 'waiting' and status in ('assigned', 'accepted'))
      or (l_state_group = 'in_transit' and status = 'in_transit')
      or (l_state_group = 'completed' and status in ('delivered', 'returned_to_store'))
  ),
  page_plus_one as (
    select grouped.*,
      row_number() over (order by created_at desc, task_id desc) as row_number
    from grouped
    where p_cursor is null
      or (created_at, task_id) < (l_cursor_created_at, l_cursor_task_id)
    order by created_at desc, task_id desc
    limit p_limit + 1
  ),
  page_rows as (
    select * from page_plus_one where row_number <= p_limit
  ),
  count_rows as (
    select
      count(*) filter (where status in ('assigned', 'accepted'))::integer as waiting,
      count(*) filter (where status = 'in_transit')::integer as in_transit,
      count(*) filter (where status in ('delivered', 'returned_to_store'))::integer as completed,
      count(*) filter (
        where status not in (
          'assigned', 'accepted', 'in_transit', 'delivered', 'returned_to_store'
        )
      )::integer as ungrouped
    from filtered
  ),
  grouped_count as (
    select
      count(*)::integer as filtered_total
    from grouped
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'task_id', row.task_id,
            'kind', row.kind,
            'status', row.status,
            'attempt_number', row.attempt_number,
            'snapshot_scope', row.snapshot_scope,
            'order_id', row.order_id,
            'return_request_id', row.return_request_id,
            'amount_to_collect_vnd', row.amount_to_collect_vnd,
            'destination_name', row.destination_name,
            'destination_phone', row.destination_phone,
            'destination_address', row.destination_address,
            'destination_latitude', row.destination_latitude,
            'destination_longitude', row.destination_longitude,
            'assigned_at', row.assigned_at,
            'accepted_at', row.accepted_at,
            'started_at', row.started_at,
            'completed_at', row.completed_at,
            'item_source', row.item_source
          )
          order by row.created_at desc, row.task_id desc
        )
        from page_rows as row
      ),
      '[]'::jsonb
    ),
    'next_cursor', (
      select replace(encode(
        convert_to(
          jsonb_build_object(
            'v', 1,
            'uid', l_user_id::text,
            'filter', l_filter_hash,
            'created_at', row.created_at,
            'task_id', row.task_id
          )::text,
          'UTF8'
        ),
        'base64'
      ), E'\n', '')
      from page_plus_one as row
      where row.row_number = p_limit
        and exists (
          select 1
          from page_plus_one as extra
          where extra.row_number = p_limit + 1
        )
    ),
    'filtered_total', grouped_count.filtered_total,
    'counts', jsonb_build_object(
      'waiting', count_rows.waiting,
      'in_transit', count_rows.in_transit,
      'completed', count_rows.completed,
      'ungrouped', count_rows.ungrouped
    ),
    'as_of', statement_timestamp()
  )
  into l_result
  from count_rows
  cross join grouped_count;

  return l_result;
end;
$$;

-- Keep the same locked-down owner and API surface as the P01.1 projection.
grant create on schema public to sports_store_delivery_reader;
alter function public.list_my_delivery_tasks(
  public.delivery_task_kind, text, text, integer, text
) owner to sports_store_delivery_reader;
revoke create on schema public from sports_store_delivery_reader;
revoke all on function public.list_my_delivery_tasks(
  public.delivery_task_kind, text, text, integer, text
) from public, anon, authenticated, service_role;
grant execute on function public.list_my_delivery_tasks(
  public.delivery_task_kind, text, text, integer, text
) to authenticated;

comment on function public.list_my_delivery_tasks(
  public.delivery_task_kind, text, text, integer, text
) is
  'P02.1 shipper task-list projection with full-dataset counts and bound keyset cursor.';

notify pgrst, 'reload schema';
