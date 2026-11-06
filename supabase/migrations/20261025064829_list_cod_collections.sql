-- P06.1: role-scoped COD read projection.
--
-- The base cod_collections policy is intentionally not the API contract for
-- MH12: this projection binds every request to auth.uid(), applies manager
-- filters server-side, and computes counts/outstanding over the complete
-- authorized scope before paging.  No orders join is used because the schema
-- has no order-code snapshot; order_code is explicitly the order UUID text.

-- Full-scope aggregates materialize the authorized rows before paging. Keep
-- existing shipper_id/PK indexes; no unmeasured order index is added here.

create or replace function public.list_cod_collections(
  p_shipper_id uuid default null,
  p_order_id uuid default null,
  p_statuses public.cod_status[] default null,
  p_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l_user_id uuid;
  l_role text;
  l_limit integer;
  l_filter_hash text;
  l_cursor_json jsonb;
  l_cursor_created_at timestamptz;
  l_cursor_order_id uuid;
  l_canonical_statuses text[];
  l_result jsonb;
  l_as_of timestamptz := statement_timestamp();
begin
  l_user_id := (select auth.uid());
  if l_user_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  select p.role::text
    into l_role
  from public.profiles p
  where p.id = l_user_id;

  if l_role is null or l_role not in ('shipper', 'manager') then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;
  l_limit := p_limit;

  if l_role = 'shipper'
     and p_shipper_id is not null
     and p_shipper_id is distinct from l_user_id then
    raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
  end if;

  if p_statuses is not null and (
    coalesce(array_ndims(p_statuses), 0) <> 1
    or coalesce(array_length(p_statuses, 1), 0) = 0
    or exists (select 1 from unnest(p_statuses) as values(value) where value is null)
  ) then
    raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
  end if;

  -- Enum values are validated by PostgreSQL.  Canonicalize their textual
  -- order so an equivalent status filter cannot invalidate a cursor merely by
  -- changing the order in which the array was supplied.
  if p_statuses is null then
    l_canonical_statuses := null;
  else
    select array_agg(distinct s order by s)
      into l_canonical_statuses
    from unnest(p_statuses::text[]) as statuses(s);
  end if;

  l_filter_hash := md5(
    l_user_id::text || chr(31) || l_role || chr(31)
      || coalesce(
        (case when l_role = 'shipper' then l_user_id else p_shipper_id end)::text,
        ''
      ) || chr(31)
      || coalesce(p_order_id::text, '') || chr(31)
      || coalesce(array_to_string(l_canonical_statuses, ','), '')
  );

  if p_cursor is not null then
    if p_cursor = '' or btrim(p_cursor) <> p_cursor
       or char_length(p_cursor) > 4096 then
      raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
    end if;

    begin
      l_cursor_json := convert_from(decode(p_cursor, 'base64'), 'UTF8')::jsonb;
      if jsonb_typeof(l_cursor_json) <> 'object'
         or not (l_cursor_json ?& array['v', 'uid', 'filter', 'created_at', 'order_id'])
         or jsonb_typeof(l_cursor_json->'v') <> 'number'
         or jsonb_typeof(l_cursor_json->'uid') <> 'string'
         or jsonb_typeof(l_cursor_json->'filter') <> 'string'
         or l_cursor_json->>'v' <> '1'
         or l_cursor_json->>'uid' <> l_user_id::text
         or l_cursor_json->>'filter' <> l_filter_hash
         or jsonb_typeof(l_cursor_json->'created_at') <> 'string'
         or jsonb_typeof(l_cursor_json->'order_id') <> 'string' then
        raise exception using errcode = '22023', message = 'INVALID_ARGUMENT';
      end if;
      l_cursor_created_at := (l_cursor_json->>'created_at')::timestamptz;
      l_cursor_order_id := (l_cursor_json->>'order_id')::uuid;
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

  -- The projection is materialized once.  This keeps the page, counts and
  -- outstanding total on one statement snapshot and prevents page-local
  -- totals.  `scoped` is role-filtered; `filtered` applies manager/status
  -- filters, and `page_plus_one` applies only the bound keyset cursor.
  with scoped as materialized (
    select c.*
    from public.cod_collections c
    where (
      (l_role = 'shipper' and c.shipper_id = l_user_id)
      or (
        l_role = 'manager'
        and (p_shipper_id is null or c.shipper_id = p_shipper_id)
      )
    )
    and (p_order_id is null or c.order_id = p_order_id)
  ),
  filtered as materialized (
    select *
    from scoped
    where p_statuses is null or status = any(p_statuses)
  ),
  page_plus_one as (
    select filtered.*,
      row_number() over (order by created_at desc, order_id desc) as row_number
    from filtered
    where p_cursor is null
      or (created_at, order_id) < (l_cursor_created_at, l_cursor_order_id)
    order by created_at desc, order_id desc
    limit l_limit + 1
  ),
  page_rows as (
    select * from page_plus_one where row_number <= l_limit
  ),
  scope_counts as (
    select
      count(*)::integer as all_count,
      count(*) filter (where status = 'uncollected')::integer as uncollected_count,
      count(*) filter (where status = 'collected')::integer as collected_count,
      count(*) filter (where status = 'received')::integer as received_count,
      coalesce(sum(collected_amount_vnd - received_amount_vnd)
        filter (where status = 'collected'), 0)::bigint as outstanding_vnd
    from scoped
  ),
  filtered_count as (
    select count(*)::integer as filtered_total from filtered
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'order_id', row.order_id,
            'order_code', row.order_id::text,
            'order_code_source', 'order_uuid',
            'shipper_id', row.shipper_id,
            'status', row.status,
            'expected_amount_vnd', row.expected_amount_vnd,
            'collected_amount_vnd', row.collected_amount_vnd,
            'received_amount_vnd', row.received_amount_vnd,
            'collected_by', row.collected_by,
            'received_by', row.received_by,
            'collected_at', row.collected_at,
            'handed_over_at', row.handed_over_at,
            'received_at', row.received_at,
            'created_at', row.created_at,
            'updated_at', row.updated_at
          ) order by row.created_at desc, row.order_id desc
        ) from page_rows row
      ), '[]'::jsonb
    ),
    'next_cursor', (
      select replace(encode(convert_to(
        jsonb_build_object(
          'v', 1, 'uid', l_user_id::text, 'filter', l_filter_hash,
          'created_at', row.created_at, 'order_id', row.order_id
        )::text, 'UTF8'), 'base64'), E'\n', '')
      from page_plus_one row
      where row.row_number = l_limit
        and exists (
          select 1 from page_plus_one extra
          where extra.row_number = l_limit + 1
        )
    ),
    'filtered_total', filtered_count.filtered_total,
    'counts', jsonb_build_object(
      'all', scope_counts.all_count,
      'uncollected', scope_counts.uncollected_count,
      'collected', scope_counts.collected_count,
      'received', scope_counts.received_count
    ),
    'outstanding_vnd', scope_counts.outstanding_vnd,
    'as_of', l_as_of
  )
  into l_result
  from scope_counts cross join filtered_count;

  return l_result;
end;
$$;

revoke all on function public.list_cod_collections(uuid, uuid, public.cod_status[], integer, text)
  from public, anon, service_role;
grant execute on function public.list_cod_collections(uuid, uuid, public.cod_status[], integer, text)
  to authenticated;

comment on function public.list_cod_collections(uuid, uuid, public.cod_status[], integer, text)
  is 'P06.1 role-scoped COD projection; counts/outstanding are full-scope and status-filter independent.';

notify pgrst, 'reload schema';
