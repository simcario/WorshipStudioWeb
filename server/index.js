// WorshipStudio backend, deployed on Firebase App Hosting.
//
// It serves the built PWA from ./public (copied there by tool/postbuild.js)
// and exposes /api, which is the only way to change groups and invitations:
// firestore.rules lets clients read their groups but not write them.
// Songs and sets are read and written by the app straight from Firestore.
//
// Locally: `node index.js` needs credentials for Firestore, e.g.
// `gcloud auth application-default login`.
const path = require('path');
const express = require('express');
const nodemailer = require('nodemailer');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// App Hosting provides FIREBASE_CONFIG; elsewhere the project is named here.
initializeApp(process.env.FIREBASE_CONFIG ? undefined : { projectId: process.env.GOOGLE_CLOUD_PROJECT || 'worshipstudioweb' });
const db = getFirestore();
const groups = db.collection('groups');
const invites = db.collection('invites');

const mailer = process.env.SMTP_HOST
  ? nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT || 587),
      secure: Number(process.env.SMTP_PORT || 587) === 465,
      auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS } : undefined,
    })
  : null;

/** Error sent to the app as `{error: code}`; the app translates the code. */
class ApiError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

const handle = (fn) => (req, res, next) => fn(req, res).then((body) => res.json(body ?? {}), next);
const profile = (user) => ({ email: user.email, name: user.name || user.email, photo: user.picture || '' });
const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function cleanName(value) {
  const name = typeof value === 'string' ? value.trim() : '';
  if (!name || name.length > 60) throw new ApiError(400, 'invalid-name');
  return name;
}

/** Reads a group inside a transaction and checks the caller's role in it. */
async function loadGroup(tx, id, uid, { admin = true } = {}) {
  const snap = await tx.get(groups.doc(id));
  if (!snap.exists) throw new ApiError(404, 'not-found');
  const group = snap.data();
  if (!group.memberUids.includes(uid)) throw new ApiError(404, 'not-found');
  if (admin && group.roles[uid] !== 'admin') throw new ApiError(403, 'not-admin');
  return group;
}

async function deleteGroup(id) {
  const pending = await invites.where('groupId', '==', id).get();
  await Promise.all(pending.docs.map((d) => d.ref.delete()));
  await db.recursiveDelete(groups.doc(id)); // with its songs and sets
}

async function sendInvite(req, email, groupName) {
  const link = process.env.APP_URL || `${req.protocol}://${req.get('host')}`;
  if (!mailer) return { mailed: false, link };
  const from = req.user.name || req.user.email;
  try {
    await mailer.sendMail({
      from: process.env.MAIL_FROM || process.env.SMTP_USER,
      to: email,
      replyTo: req.user.email,
      subject: `${from} ti ha invitato nel gruppo "${groupName}" su WorshipStudio`,
      text:
        `${from} ti ha invitato nel gruppo "${groupName}" su WorshipStudio.\n\n` +
        `Apri ${link} e accedi con l'account Google ${email}: troverai l'invito da accettare. ` +
        `Dopo averlo accettato vedrai i brani e le scalette del gruppo.\n\n` +
        `${from} invited you to the group "${groupName}" on WorshipStudio. ` +
        `Open ${link} and sign in with the Google account ${email} to accept.`,
      html:
        `<p><b>${escapeHtml(from)}</b> ti ha invitato nel gruppo <b>${escapeHtml(groupName)}</b> su WorshipStudio.</p>` +
        `<p><a href="${escapeHtml(link)}">Apri WorshipStudio</a> e accedi con l'account Google ` +
        `<b>${escapeHtml(email)}</b>: troverai l'invito da accettare. Dopo averlo accettato vedrai i brani e le scalette del gruppo.</p>` +
        `<p style="color:#666">${escapeHtml(from)} invited you to the group "${escapeHtml(groupName)}" on WorshipStudio. ` +
        `Open the link and sign in with the Google account ${escapeHtml(email)} to accept.</p>`,
    });
    return { mailed: true, link };
  } catch (err) {
    console.error('Invitation mail failed', err);
    return { mailed: false, link };
  }
}

const api = express.Router();

// The app may be run from another local port during development.
api.use((req, res, next) => {
  const origin = req.get('origin') || '';
  if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
    res.set({
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE',
      Vary: 'Origin',
    });
    if (req.method === 'OPTIONS') return res.sendStatus(204);
  }
  next();
});
api.use(express.json({ limit: '20kb' }));

// Every call carries the Firebase ID token of a Google account.
api.use(async (req, res, next) => {
  try {
    const token = (req.get('authorization') || '').replace(/^Bearer /, '');
    req.user = await getAuth().verifyIdToken(token);
    if (!req.user.email || !req.user.email_verified) throw new Error('no verified email');
    req.user.email = req.user.email.toLowerCase();
    next();
  } catch (_) {
    next(new ApiError(401, 'unauthenticated'));
  }
});

api.post('/groups', handle(async (req) => {
  const ref = groups.doc();
  await ref.set({
    name: cleanName(req.body.name),
    createdAt: FieldValue.serverTimestamp(),
    createdBy: req.user.uid,
    membersCanEdit: false,
    memberUids: [req.user.uid],
    roles: { [req.user.uid]: 'admin' },
    profiles: { [req.user.uid]: profile(req.user) },
    invites: {},
  });
  return { id: ref.id };
}));

api.patch('/groups/:gid', handle(async (req) => {
  const changes = {};
  if (req.body.name !== undefined) changes.name = cleanName(req.body.name);
  if (typeof req.body.membersCanEdit === 'boolean') changes.membersCanEdit = req.body.membersCanEdit;
  await db.runTransaction(async (tx) => {
    await loadGroup(tx, req.params.gid, req.user.uid);
    tx.update(groups.doc(req.params.gid), changes);
  });
}));

api.delete('/groups/:gid', handle(async (req) => {
  await db.runTransaction((tx) => loadGroup(tx, req.params.gid, req.user.uid));
  await deleteGroup(req.params.gid);
}));

api.post('/groups/:gid/invites', handle(async (req) => {
  const email = typeof req.body.email === 'string' ? req.body.email.trim().toLowerCase() : '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 200) throw new ApiError(400, 'invalid-email');
  const { id, name } = await db.runTransaction(async (tx) => {
    const group = await loadGroup(tx, req.params.gid, req.user.uid);
    if (Object.values(group.profiles).some((p) => p.email === email)) throw new ApiError(409, 'already-member');
    // Inviting the same address again only sends the mail again.
    const existing = Object.keys(group.invites).find((k) => group.invites[k] === email);
    if (existing) return { id: existing, name: group.name };
    if (Object.keys(group.invites).length >= 100) throw new ApiError(409, 'too-many-invites');
    const ref = invites.doc();
    tx.set(ref, {
      groupId: req.params.gid,
      groupName: group.name,
      email,
      invitedByUid: req.user.uid,
      invitedBy: req.user.name || req.user.email,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(groups.doc(req.params.gid), { [`invites.${ref.id}`]: email });
    return { id: ref.id, name: group.name };
  });
  return { id, ...(await sendInvite(req, email, name)) };
}));

api.delete('/groups/:gid/invites/:id', handle(async (req) => {
  await db.runTransaction(async (tx) => {
    const group = await loadGroup(tx, req.params.gid, req.user.uid);
    if (!(req.params.id in group.invites)) throw new ApiError(404, 'not-found');
    tx.delete(invites.doc(req.params.id));
    tx.update(groups.doc(req.params.gid), { [`invites.${req.params.id}`]: FieldValue.delete() });
  });
}));

// Invitations waiting for the signed-in address.
api.get('/invites', handle(async (req) => {
  const snap = await invites.where('email', '==', req.user.email).get();
  return snap.docs.map((d) => ({ id: d.id, groupId: d.get('groupId'), groupName: d.get('groupName'), invitedBy: d.get('invitedBy') }));
}));

/** Accepts or declines: either way the invitation is used up. */
const answer = (accept) => handle(async (req) => {
  await db.runTransaction(async (tx) => {
    const ref = invites.doc(req.params.id);
    const invite = await tx.get(ref);
    if (!invite.exists) throw new ApiError(404, 'not-found');
    if (invite.get('email') !== req.user.email) throw new ApiError(403, 'wrong-account');
    const groupRef = groups.doc(invite.get('groupId'));
    const group = await tx.get(groupRef);
    tx.delete(ref);
    if (!group.exists) return;
    const changes = { [`invites.${ref.id}`]: FieldValue.delete() };
    if (accept && !group.get('memberUids').includes(req.user.uid)) {
      changes.memberUids = FieldValue.arrayUnion(req.user.uid);
      changes[`roles.${req.user.uid}`] = 'member';
      changes[`profiles.${req.user.uid}`] = profile(req.user);
    }
    tx.update(groupRef, changes);
  });
});
api.post('/invites/:id/accept', answer(true));
api.post('/invites/:id/decline', answer(false));

api.put('/groups/:gid/members/:uid', handle(async (req) => {
  const role = req.body.role;
  if (role !== 'admin' && role !== 'member') throw new ApiError(400, 'invalid-role');
  await db.runTransaction(async (tx) => {
    const group = await loadGroup(tx, req.params.gid, req.user.uid);
    if (!group.memberUids.includes(req.params.uid)) throw new ApiError(404, 'not-found');
    const roles = { ...group.roles, [req.params.uid]: role };
    if (!Object.values(roles).includes('admin')) throw new ApiError(409, 'last-admin');
    tx.update(groups.doc(req.params.gid), { [`roles.${req.params.uid}`]: role });
  });
}));

// An administrator removes anyone; a member can only leave.
api.delete('/groups/:gid/members/:uid', handle(async (req) => {
  const target = req.params.uid;
  const empty = await db.runTransaction(async (tx) => {
    const group = await loadGroup(tx, req.params.gid, req.user.uid, { admin: target !== req.user.uid });
    if (!group.memberUids.includes(target)) throw new ApiError(404, 'not-found');
    if (group.memberUids.length === 1) return true;
    const roles = { ...group.roles };
    delete roles[target];
    if (!Object.values(roles).includes('admin')) throw new ApiError(409, 'last-admin');
    tx.update(groups.doc(req.params.gid), {
      memberUids: FieldValue.arrayRemove(target),
      [`roles.${target}`]: FieldValue.delete(),
      [`profiles.${target}`]: FieldValue.delete(),
    });
    return false;
  });
  if (empty) await deleteGroup(req.params.gid); // the last member left
}));

api.use((req, res, next) => next(new ApiError(404, 'not-found')));
api.use((err, req, res, next) => {
  if (!(err instanceof ApiError)) console.error(err);
  const status = err.status || 500;
  res.status(status).json({ error: status === 500 ? 'server-error' : err.message });
});

const app = express();
app.set('trust proxy', true);
app.disable('x-powered-by');
app.use('/api', api);

// The service worker decides what is cached: the shell must always be revalidated.
const publicDir = path.join(__dirname, 'public');
app.use(express.static(publicDir, { setHeaders: (res) => res.set('Cache-Control', 'no-cache') }));
app.get('*', (req, res) => res.set('Cache-Control', 'no-cache').sendFile(path.join(publicDir, 'index.html')));

const port = Number(process.env.PORT || 8080);
app.listen(port, () => console.log(`WorshipStudio on http://localhost:${port}${mailer ? '' : '  (no SMTP: invitations are not mailed)'}`));
