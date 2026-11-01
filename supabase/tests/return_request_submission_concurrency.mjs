// MH13 concurrency checks on the isolated fixture database only. Committed
// fixture rows are removed in finally; the database itself is never dropped.
const CUSTOMER = '13140000-0000-4000-8000-000000000001';
const MANAGER = '13140000-0000-4000-8000-000000000003';
const ORDER = '13141000-0000-4000-8000-000000000001';
const VIDEO = `${CUSTOMER}/${ORDER}/race.mp4`;

async function asCustomer(client) {
  await client.query('begin');
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [CUSTOMER]);
  await client.query('set local role authenticated');
}

async function submit(Client, options, requestId, description) {
  const client = new Client(options);
  await client.connect();
  try {
    await asCustomer(client);
    const { rows } = await client.query(
      `select public.submit_return_request($1, $2, 'defective', $3, $4,
         'Vietcombank', '0123456789', 'NGUYEN VAN A') as r`,
      [ORDER, requestId, description, VIDEO],
    );
    await client.query('commit');
    return { ok: rows[0].r };
  } catch (error) {
    await client.query('rollback').catch(() => {});
    return { error: `${error.code}:${error.message}` };
  } finally {
    await client.end();
  }
}

export async function testReturnRequestConcurrency(Client, options, admin) {
  await admin.query('begin');
  await admin.query(`insert into auth.users (id, email) values
    ($1, 'mh13-race-customer@example.invalid'), ($2, 'mh13-race-manager@example.invalid')`,
    [CUSTOMER, MANAGER]);
  await admin.query(`update public.profiles set role = 'manager' where id = $1`, [MANAGER]);
  await admin.query(`insert into public.orders (id, customer_id, request_id, status,
      recipient_name, recipient_phone, address_detail, latitude, longitude,
      subtotal_vnd, delivery_fee_vnd, delivered_at)
    values ($1, $2, gen_random_uuid(), 'delivered', 'Race', '0900001314',
      'Race address, Ha Noi', 21.03, 105.8, 520000, 30000, now() - interval '1 day')`,
    [ORDER, CUSTOMER]);
  await admin.query(`insert into storage.objects (bucket_id, name, owner_id, metadata)
    values ('return-videos', $1, $2, '{"mimetype":"video/mp4","size":4096}')`,
    [VIDEO, CUSTOMER]);
  await admin.query('commit');
  try {
    const sameKey = '13143000-0000-4000-8000-000000000001';
    const desc = 'Đường may bị bung ở tay áo khi mở kiện.';
    const replays = await Promise.all(
      Array.from({ length: 6 }, () => submit(Client, options, sameKey, desc)),
    );
    const ids = new Set(replays.map((r) => r.ok?.return_request_id));
    if (replays.some((r) => r.error) || ids.size !== 1) {
      throw new Error(`Same-key race must replay one return: ${JSON.stringify(replays)}`);
    }
    if (replays.filter((r) => r.ok.replayed === false).length !== 1) {
      throw new Error('Exactly one same-key call must create the return');
    }
    const others = await Promise.all(
      Array.from({ length: 6 }, (_, i) =>
        submit(Client, options, `13143000-0000-4000-8000-00000000001${i}`, desc)),
    );
    if (others.some((r) => r.error !== 'PT409:ACTIVE_RETURN_EXISTS')) {
      throw new Error(`Different keys must be rejected: ${JSON.stringify(others)}`);
    }
    const { rows } = await admin.query(`select
        (select count(*) from public.return_requests where order_id = $1) as returns,
        (select count(*) from public.notifications n join public.return_requests r
           on r.id = n.subject_id where r.order_id = $1) as notifications`, [ORDER]);
    if (rows[0].returns !== '1' || rows[0].notifications !== '1') {
      throw new Error(`Expected 1 return + 1 notification, got ${JSON.stringify(rows[0])}`);
    }
    console.log('MH13 concurrency: PASS (6 same-key replays -> 1 return; 6 new keys -> ACTIVE_RETURN_EXISTS)');
  } finally {
    await admin.query('begin');
    await admin.query(`delete from public.notifications where subject_id in
      (select id from public.return_requests where order_id = $1)`, [ORDER]);
    await admin.query(`delete from public.business_events where subject_id in
      (select id from public.return_requests where order_id = $1)`, [ORDER]);
    await admin.query('delete from public.return_requests where order_id = $1', [ORDER]);
    await admin.query('delete from storage.objects where name = $1', [VIDEO]);
    await admin.query('delete from public.orders where id = $1', [ORDER]);
    await admin.query('delete from public.profiles where id = any($1)', [[CUSTOMER, MANAGER]]);
    await admin.query('delete from auth.users where id = any($1)', [[CUSTOMER, MANAGER]]);
    await admin.query('commit');
  }
}
