#!/usr/bin/env node
'use strict';

/// Creates any real user account (Super Admin, NCP Admin, Supervisor, PST
/// Teacher, Scanner Operator, Viewer) — the general-purpose sibling of
/// bootstrap-admin.js, which only ever creates the first Super Admin.
///
/// Why this exists at all: `firebase/firestore.rules` authorises every
/// request off Auth custom claims, meant to be written automatically by an
/// `onUserWrite` Cloud Function whenever a `users/{uid}` document changes.
/// That function has never been built, and Cloud Functions need the Blaze
/// plan besides — this project stays on Spark. The in-app "Add user" screen
/// is guarded against this gap (see
/// lib/features/users/data/service/manual_provisioning_user_data_source.dart)
/// rather than allowed to create a broken, unsignable-in account, so this
/// script is —- for now —- the only way to onboard someone for real.
///
/// It mirrors exactly what `UserRepositoryImpl`/`FirestoreUserDataSource`
/// would write, plus the two things only a service account can do: create
/// the Auth account and set its custom claims.
///
/// Usage:
///   node create-user.js <path-to-service-account.json>

const admin = require('firebase-admin');
const path = require('path');
const readline = require('readline');

const ROLES = [
  'SUPER_ADMIN',
  'ASSESSMENT_ADMIN',
  'SUPERVISOR',
  'PST_TEACHER',
  'SCANNER_OPERATOR',
  'VIEWER',
];

const SCOPE_LEVELS = ['GLOBAL', 'STATE', 'DISTRICT', 'CLUSTER', 'SCHOOL'];

function ask(question, { hidden = false } = {}) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    if (hidden) {
      rl._writeToOutput = (text) =>
        rl.output.write(text.startsWith(question) ? text : '');
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) {
        process.stdout.write('\n');
      }
      resolve(answer.trim());
    });
  });
}

function splitIds(raw) {
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

async function pickFrom(label, options) {
  console.log(`\n${label}`);
  options.forEach((opt, i) => console.log(`  ${i + 1}. ${opt}`));
  while (true) {
    const answer = await ask(`Choose 1-${options.length}: `);
    const index = Number.parseInt(answer, 10) - 1;
    if (Number.isInteger(index) && index >= 0 && index < options.length) {
      return options[index];
    }
    console.log('Not a valid choice, try again.');
  }
}

/// Mirrors UserRepositoryImpl._resolveScope: a school-level scope also
/// carries its schools' state/district/cluster ancestry, denormalised, so
/// AccessScope.covers and .isWithin work without an extra read later.
async function resolveSchoolAncestry(db, schoolIds) {
  const stateIds = new Set();
  const districtIds = new Set();
  const clusterIds = new Set();
  for (const schoolId of schoolIds) {
    const doc = await db.collection('schools').doc(schoolId).get();
    if (!doc.exists) {
      throw new Error(`School "${schoolId}" was not found in the schools collection.`);
    }
    const data = doc.data();
    if (data.stateId) stateIds.add(data.stateId);
    if (data.districtId) districtIds.add(data.districtId);
    if (data.clusterId) clusterIds.add(data.clusterId);
  }
  return { stateIds: [...stateIds], districtIds: [...districtIds], clusterIds: [...clusterIds] };
}

async function buildScope(db) {
  const level = await pickFrom('Scope level:', SCOPE_LEVELS);
  if (level === 'GLOBAL') {
    return { level, stateIds: [], districtIds: [], clusterIds: [], schoolIds: [], gradeSections: [] };
  }
  if (level === 'SCHOOL') {
    const schoolIds = splitIds(await ask('School id(s), comma-separated: '));
    const ancestry = await resolveSchoolAncestry(db, schoolIds);
    const gradeSectionsRaw = await ask(
      'Grade-sections to narrow to, e.g. "5-A,5-B" (leave blank for every class in these schools): ',
    );
    return {
      level,
      schoolIds,
      ...ancestry,
      gradeSections: splitIds(gradeSectionsRaw),
    };
  }
  const idsRaw = await ask(`${level.charAt(0)}${level.slice(1).toLowerCase()} id(s), comma-separated: `);
  const ids = splitIds(idsRaw);
  return {
    level,
    stateIds: level === 'STATE' ? ids : [],
    districtIds: level === 'DISTRICT' ? ids : [],
    clusterIds: level === 'CLUSTER' ? ids : [],
    schoolIds: [],
    gradeSections: [],
  };
}

function toClaims(role, scope) {
  const claims = {
    role,
    lvl: scope.level,
    st: scope.stateIds,
    di: scope.districtIds,
    cl: scope.clusterIds,
    sc: scope.schoolIds,
  };
  if (scope.gradeSections.length > 0) {
    claims.gs = scope.gradeSections;
  }
  return claims;
}

function toFirestoreScope(scope) {
  return {
    level: scope.level,
    stateIds: scope.stateIds,
    districtIds: scope.districtIds,
    clusterIds: scope.clusterIds,
    schoolIds: scope.schoolIds,
    gradeSections: scope.gradeSections,
  };
}

async function main() {
  const serviceAccountPath = process.argv[2];
  if (!serviceAccountPath) {
    console.error('Usage: node create-user.js <path-to-service-account.json>');
    process.exitCode = 1;
    return;
  }

  const serviceAccount = require(path.resolve(serviceAccountPath));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const email = (await ask('Email: ')).toLowerCase();
  const password = await ask('Password (min 6 characters): ', { hidden: true });
  const displayName = await ask('Display name: ');
  const phone = await ask('Phone (optional, press Enter to skip): ');

  if (!email || !password || password.length < 6 || !displayName) {
    console.error('Email, a 6+ character password and a display name are required.');
    process.exitCode = 1;
    return;
  }

  // Mirrors FirestoreUserDataSource.createUser's email-uniqueness guard.
  const guardRef = db.collection('user_email').doc(email);
  const existingGuard = await guardRef.get();
  if (existingGuard.exists) {
    console.error(
      `An account already exists for ${email}. Use a role/scope change ` +
        'instead of creating a second account for the same person.',
    );
    process.exitCode = 1;
    return;
  }

  const role = await pickFrom('Role:', ROLES);
  const scope = await buildScope(db);

  const userRecord = await admin.auth().createUser({
    email,
    password,
    displayName,
  });

  await admin.auth().setCustomUserClaims(userRecord.uid, toClaims(role, scope));

  const userDoc = {
    email,
    displayName,
    phone: phone || null,
    role,
    scope: toFirestoreScope(scope),
    isActive: true,
    lastLoginAt: null,
    claimsVersion: 1,
  };

  await db.runTransaction(async (tx) => {
    tx.set(guardRef, { userId: userRecord.uid, createdAt: new Date().toISOString() });
    tx.set(db.collection('users').doc(userRecord.uid), userDoc);
  });

  console.log(`\nCreated ${role} account for ${email} (uid ${userRecord.uid}).`);
  console.log('Custom claims and Firestore profile are set. They can sign in now.');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('create-user failed:', error.message || error);
    process.exit(1);
  });
