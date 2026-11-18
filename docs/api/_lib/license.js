'use strict';
// Pure license signing / encoding helpers (no I/O, no secrets).
const crypto = require('node:crypto');

const PREFIX = 'GLIDE-';
const SESSION_RE = /^cs_(test|live)_[A-Za-z0-9]+$/;

const b64u = (buf) => Buffer.from(buf).toString('base64url'); // no padding

// Accept PEM with real newlines or literal "\n" sequences (common in env vars).
function normalizePem(pem) {
  let s = String(pem || '').trim();
  if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) s = s.slice(1, -1);
  return s.replace(/\\r/g, '').replace(/\\n/g, '\n');
}

function loadPrivateKey(pem) {
  return crypto.createPrivateKey({ key: normalizePem(pem), format: 'pem' });
}

// Key order is part of the format: v, sku, sid, iat.
function buildPayload(sessionId, created) {
  return Buffer.from(
    JSON.stringify({ v: 1, sku: 'glide_full', sid: sessionId, iat: created }),
    'utf8'
  );
}

function signLicense(sessionId, created, privateKey) {
  const payload = buildPayload(sessionId, created);
  const sig = crypto.sign(null, payload, privateKey); // Ed25519
  return PREFIX + b64u(payload) + '.' + b64u(sig);
}

// Returns the parsed payload on success, or null. publicKey: KeyObject.
function verifyLicense(key, publicKey) {
  if (typeof key !== 'string' || !key.startsWith(PREFIX)) return null;
  const parts = key.slice(PREFIX.length).split('.');
  if (parts.length !== 2) return null;
  const payload = Buffer.from(parts[0], 'base64url');
  const sig = Buffer.from(parts[1], 'base64url');
  if (sig.length !== 64) return null;
  if (!crypto.verify(null, payload, publicKey, sig)) return null;
  try { return JSON.parse(payload.toString('utf8')); } catch { return null; }
}

module.exports = { PREFIX, SESSION_RE, normalizePem, loadPrivateKey, buildPayload, signLicense, verifyLicense };
