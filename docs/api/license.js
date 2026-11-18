'use strict';
const { SESSION_RE, loadPrivateKey, signLicense } = require('./_lib/license');

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return send(res, 405, { error: 'Method not allowed.' });
  }

  const { STRIPE_SECRET_KEY, STRIPE_PRICE_ID, LICENSE_PRIVATE_KEY } = process.env;
  if (!STRIPE_SECRET_KEY || !STRIPE_PRICE_ID || !LICENSE_PRIVATE_KEY) {
    return send(res, 500, { error: 'Server is not configured.' });
  }

  const id = typeof (req.query && req.query.session_id) === 'string'
    ? req.query.session_id
    : new URL(req.url, 'http://x').searchParams.get('session_id');
  if (!id || !SESSION_RE.test(id)) {
    return send(res, 400, { error: 'Invalid session_id.' });
  }

  let session;
  try {
    const r = await fetch(
      'https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(id) + '?expand[]=line_items',
      { headers: { Authorization: 'Bearer ' + STRIPE_SECRET_KEY } }
    );
    if (r.status === 404 || r.status === 400) return send(res, 404, { error: 'Purchase not found.' });
    if (!r.ok) return send(res, 502, { error: 'Could not verify the purchase. Please try again.' });
    session = await r.json();
  } catch (e) {
    return send(res, 502, { error: 'Could not verify the purchase. Please try again.' });
  }

  if (session.payment_status !== 'paid') {
    return send(res, 402, { error: 'Payment has not been completed.' });
  }
  const items = (session.line_items && session.line_items.data) || [];
  if (!items.some((li) => li.price && li.price.id === STRIPE_PRICE_ID)) {
    return send(res, 404, { error: 'Purchase not found.' });
  }
  if (!Number.isInteger(session.created)) {
    return send(res, 502, { error: 'Could not verify the purchase.' });
  }

  let key;
  try {
    key = signLicense(session.id, session.created, loadPrivateKey(LICENSE_PRIVATE_KEY));
  } catch (e) {
    return send(res, 500, { error: 'Server is not configured.' });
  }
  return send(res, 200, {
    key,
    email: (session.customer_details && session.customer_details.email) || null,
  });
};
