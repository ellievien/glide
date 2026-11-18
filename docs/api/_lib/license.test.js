'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const L = require('./license');

const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
const SID = 'cs_test_a1B2c3D4e5';
const IAT = 1790000000;

test('format, field order, base64url without padding', () => {
  const key = L.signLicense(SID, IAT, privateKey);
  assert.ok(key.startsWith('GLIDE-'));
  const [p, s, ...rest] = key.slice(6).split('.');
  assert.equal(rest.length, 0);
  assert.match(p, /^[A-Za-z0-9_-]+$/);
  assert.match(s, /^[A-Za-z0-9_-]+$/);
  const payloadText = Buffer.from(p, 'base64url').toString('utf8');
  assert.equal(payloadText, `{"v":1,"sku":"glide_full","sid":"${SID}","iat":${IAT}}`);
  assert.equal(Buffer.from(s, 'base64url').length, 64);
});

test('verifies with public key and is deterministic', () => {
  const key = L.signLicense(SID, IAT, privateKey);
  assert.deepEqual(L.verifyLicense(key, publicKey), { v: 1, sku: 'glide_full', sid: SID, iat: IAT });
  assert.equal(L.signLicense(SID, IAT, privateKey), key);
});

test('tampered payload or signature fails', () => {
  const key = L.signLicense(SID, IAT, privateKey);
  const [p, s] = key.slice(6).split('.');
  const bad = Buffer.from(p, 'base64url').toString().replace('glide_full', 'glide_pro');
  assert.equal(L.verifyLicense('GLIDE-' + Buffer.from(bad).toString('base64url') + '.' + s, publicKey), null);
  const sig = Buffer.from(s, 'base64url'); sig[0] ^= 1;
  assert.equal(L.verifyLicense('GLIDE-' + p + '.' + sig.toString('base64url'), publicKey), null);
  const other = crypto.generateKeyPairSync('ed25519').publicKey;
  assert.equal(L.verifyLicense(key, other), null);
});

test('PEM with literal backslash-n sequences loads', () => {
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const escaped = pem.replace(/\n/g, '\\n');
  const key = L.signLicense(SID, IAT, L.loadPrivateKey(escaped));
  assert.ok(L.verifyLicense(key, publicKey));
});

test('session id regex', () => {
  assert.ok(L.SESSION_RE.test('cs_live_AbC123'));
  assert.ok(!L.SESSION_RE.test('cs_foo_abc'));
  assert.ok(!L.SESSION_RE.test('cs_test_ab-c'));
});
