const SUPABASE_URL = process.env.SUPABASE_URL || 'https://xruvbsbmvpntczaydhpo.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_aldf8cJlqWKZABG_h6B1cw_dajzQxco';

export default async function handler(req, res) {
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.setHeader('Allow', 'GET, HEAD');
    return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  }

  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/keepalive_ping`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
      cache: 'no-store',
    });

    const text = await response.text();
    let payload;
    try { payload = text ? JSON.parse(text) : {}; }
    catch { payload = { raw: text }; }

    res.setHeader('Cache-Control', 'no-store, max-age=0');
    if (!response.ok) {
      return res.status(502).json({ ok: false, error: 'supabase_keepalive_failed', details: payload });
    }

    return res.status(200).json({ ok: true, source: 'vercel-cron', supabase: payload });
  } catch (error) {
    return res.status(500).json({ ok: false, error: 'keepalive_exception', message: error?.message || String(error) });
  }
}
