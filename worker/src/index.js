// LifeBase AI proxy (Cloudflare Worker).
// Holds your Anthropic API key so the app can use AI without exposing it,
// and caps usage per device and in total each month so costs can't run away.
// It stores nothing but request counts. Prompts and answers are not saved.

const MODELS = { quick: 'claude-haiku-5-5', default: 'claude-sonnet-5-5', complex: 'claude-sonnet-5-5' };

export default {
  async fetch(req, env) {
    const origin = req.headers.get('origin') || '';
    const allowed = (env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
    const cors = {
      'access-control-allow-origin': allowed.includes(origin) ? origin : (allowed[0] || ''),
      'access-control-allow-methods': 'POST, OPTIONS',
      'access-control-allow-headers': 'content-type, x-lifebase-device',
      'vary': 'origin'
    };
    const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...cors, 'content-type': 'application/json' } });

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return json({ error: 'Not found' }, 404);
    if (allowed.length && !allowed.includes(origin)) return json({ error: 'This app isn’t allowed to use this AI proxy.' }, 403);

    const device = req.headers.get('x-lifebase-device') || '';
    if (!/^[a-f0-9]{24}$/.test(device)) return json({ error: 'Missing device id' }, 400);

    let body;
    try { body = await req.json(); } catch { return json({ error: 'Bad request' }, 400); }
    const prompt = String(body.prompt || '');
    if (!prompt || prompt.length > 60000) return json({ error: 'Prompt is empty or too long' }, 400);

    const month = new Date().toISOString().slice(0, 7);
    const perUser = Number(env.MONTHLY_LIMIT || 100);
    const total = Number(env.GLOBAL_MONTHLY_LIMIT || 1000);
    const uKey = `u:${month}:${device}`, gKey = `g:${month}`;
    const [u, g] = await Promise.all([env.USAGE.get(uKey), env.USAGE.get(gKey)]);
    const used = Number(u || 0), usedAll = Number(g || 0);
    if (used >= perUser) return json({ error: `You’ve used this month’s ${perUser} AI requests. They reset on the 1st.` }, 429);
    if (usedAll >= total) return json({ error: 'LifeBase’s shared AI budget is used up for this month.' }, 429);

    const model = MODELS[body.tier] || MODELS.default;
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model, max_tokens: 2000, messages: [{ role: 'user', content: prompt }] })
    });
    if (!r.ok) return json({ error: 'The AI service had a problem. Try again in a minute.' }, 502);
    const data = await r.json();
    const text = (data.content || []).filter(c => c.type === 'text').map(c => c.text).join('');

    const ttl = 60 * 60 * 24 * 40;
    await Promise.all([env.USAGE.put(uKey, String(used + 1), { expirationTtl: ttl }), env.USAGE.put(gKey, String(usedAll + 1), { expirationTtl: ttl })]);
    return json({ text, remaining: perUser - used - 1 });
  }
};
