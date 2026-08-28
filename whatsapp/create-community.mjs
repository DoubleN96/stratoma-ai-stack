#!/usr/bin/env node
// Create ONE WhatsApp Community set up as an announcement-only funnel unit:
// community + photo + description + free entry + admins + welcome pinned in the
// announcements group, with the auto-created "General" chat removed.
//
//   node create-community.mjs community.json [photo.jpg]
//
// Why this exists: server products built on Baileys (Evolution API and friends)
// do not expose community endpoints over HTTP — they return 404. The capability
// is in the library, not in the HTTP layer, so community provisioning has to
// talk to Baileys directly. See README.md.
//
// ⚠️ Run this with any other process using the same credentials STOPPED. Two
// Baileys sockets on one WhatsApp account fight each other and drop the session.
import { dirname, join, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync, existsSync } from 'node:fs';
import pino from 'pino';
import baileys, { useMultiFileAuthState, Browsers } from '@whiskeysockets/baileys';

const makeWASocket = baileys.default || baileys.makeWASocket || baileys;
const HERE = dirname(fileURLToPath(import.meta.url));
const logger = pino({ level: 'silent' });
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString(), ...a);

const CONFIG_PATH = process.argv[2] || join(HERE, 'community.json');
if (!existsSync(CONFIG_PATH)) {
  console.error(`config not found: ${CONFIG_PATH}\nStart from community.example.json`);
  process.exit(2);
}
const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
const resolve = (p) => (p ? (isAbsolute(p) ? p : join(dirname(CONFIG_PATH), p)) : null);

const AUTH_DIR = resolve(cfg.authDir || './auth');
const SUBJECT = cfg.subject;
const PHOTO = process.argv[3] || resolve(cfg.photo);
const WELCOME_FILE = resolve(cfg.welcomeFile);
const DESC_FILE = resolve(cfg.descriptionFile);
const DESCRIPTION = DESC_FILE && existsSync(DESC_FILE)
  ? readFileSync(DESC_FILE, 'utf8').trim()
  : (cfg.description || '');

if (!SUBJECT) { console.error('config needs a "subject"'); process.exit(2); }

// Numbers: country code, digits only. "+34 600 111 222" -> "34600111222"
const ADMINS = (cfg.admins || [])
  .map((n) => String(n).replace(/[^0-9]/g, ''))
  .filter(Boolean)
  .map((n) => n + '@s.whatsapp.net');

async function connect() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const sock = makeWASocket({
    auth: state,
    logger,
    printQRInTerminal: false,
    browser: Browsers.macOS('Chrome'),
    syncFullHistory: false,
    markOnlineOnConnect: false,
  });
  sock.ev.on('creds.update', saveCreds);

  await new Promise((ok, fail) => {
    const t = setTimeout(() => fail(new Error('connect timeout 90s')), 90000);
    sock.ev.on('connection.update', (u) => {
      if (u.connection) log('[conn]', u.connection, u.lastDisconnect?.error?.output?.statusCode || '');
      if (u.connection === 'open') { clearTimeout(t); ok(); }
      // 515 is the expected "restart required" right after pairing — not a failure.
      else if (u.connection === 'close' && u.lastDisconnect?.error?.output?.statusCode !== 515) {
        clearTimeout(t);
        fail(new Error('closed code=' + u.lastDisconnect?.error?.output?.statusCode));
      }
    });
  });
  return sock;
}

async function main() {
  const sock = await connect();
  log('connected — creating community:', SUBJECT);

  const meta = await sock.communityCreate(SUBJECT, DESCRIPTION);
  const communityJid = meta?.id;
  if (!communityJid) throw new Error('communityCreate returned no jid');
  log('community:', communityJid);
  await delay(1500);

  const out = { subject: SUBJECT, communityJid, invite: null, announceJid: null, admins: {} };

  if (PHOTO) {
    try { await sock.updateProfilePicture(communityJid, { url: PHOTO }); log('photo: ok'); }
    catch (e) { log('photo failed:', e.message); }
    await delay(1200);
  }

  // Invite link. communityInviteCode is the right call; groupInviteCode on the
  // parent is the fallback when the community call misbehaves.
  for (const fn of ['communityInviteCode', 'groupInviteCode']) {
    if (out.invite) break;
    try {
      const code = await sock[fn](communityJid);
      if (code) out.invite = 'https://chat.whatsapp.com/' + code;
    } catch (e) { log(`${fn} failed:`, e.message); }
  }
  log('invite:', out.invite || '(none)');

  // Admins. Adding people usually FAILS — most accounts block being added by
  // strangers, and WhatsApp rate-limits it hard. The reliable flow is: they join
  // through the invite link themselves, then you promote them (rerun with
  // "promoteOnly": true). Both attempts are best-effort and never abort the run.
  const promoteOnly = cfg.promoteOnly === true;
  if (!promoteOnly) {
    for (const jid of ADMINS) {
      try { const r = await sock.communityParticipantsUpdate(communityJid, [jid], 'add'); out.admins[jid] = { add: r?.[0]?.status }; }
      catch (e) { out.admins[jid] = { add: 'ERR:' + e.message }; }
      await delay(900);
    }
    await delay(1200);
  }
  for (const jid of ADMINS) {
    try { const r = await sock.communityParticipantsUpdate(communityJid, [jid], 'promote'); out.admins[jid] = { ...out.admins[jid], promote: r?.[0]?.status }; }
    catch (e) { out.admins[jid] = { ...out.admins[jid], promote: 'ERR:' + e.message }; }
    await delay(900);
  }
  log('admins:', JSON.stringify(out.admins));

  // Communities are created with join approval ON. A funnel link with an
  // approval queue in front of it is a funnel that leaks, so turn it off.
  if (cfg.freeEntry !== false) {
    try { await sock.communityJoinApprovalMode(communityJid, 'off'); log('join approval: off'); }
    catch (e) { log('joinApprovalMode failed:', e.message); }
    await delay(1200);
  }

  // A new community comes with two linked groups: the announcements one
  // (announce=true, admins-only) and "General" (everyone can post). Only the
  // announcements group protects members' phone numbers from each other.
  let generalJid = null;
  try {
    const linked = await sock.communityFetchLinkedGroups(communityJid);
    for (const g of linked.linkedGroups || []) {
      try {
        const gm = await sock.groupMetadata(g.id);
        if (gm.announce) out.announceJid = g.id; else generalJid = g.id;
      } catch { /* a group we cannot read is a group we do not touch */ }
      await delay(300);
    }
  } catch (e) { log('fetchLinkedGroups failed:', e.message); }
  log('announcements:', out.announceJid, '| general:', generalJid);

  if (generalJid && cfg.removeGeneral !== false) {
    try { await sock.groupSettingUpdate(generalJid, 'announcement'); } catch (e) { log('general lockdown failed:', e.message); }
    await delay(1000);
    try { await sock.communityUnlinkGroup(generalJid, communityJid); log('general: unlinked'); }
    catch (e) { log('general unlink failed:', e.message); }
    await delay(1000);
  }

  if (out.announceJid && WELCOME_FILE && existsSync(WELCOME_FILE)) {
    const welcome = readFileSync(WELCOME_FILE, 'utf8').trim();
    try {
      const sent = await sock.sendMessage(out.announceJid, { text: welcome });
      log('welcome: posted');
      await delay(2500);
      if (sent?.key) {
        // 604800 = one week pinned
        await sock.sendMessage(out.announceJid, { pin: sent.key, type: 1, time: 604800 });
        log('welcome: pinned');
      }
    } catch (e) { log('welcome failed:', e.message); }
    await delay(1500);
  }

  // Print the record to keep: feed it into whatever registry tracks capacity.
  console.log('\n' + JSON.stringify(out, null, 2));
  await sock.end();
  process.exit(0);
}

main().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
