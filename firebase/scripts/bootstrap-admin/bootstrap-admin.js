#!/usr/bin/env node
'use strict';

/// Creates the first Super Admin account on a fresh Firebase project.
///
/// Firestore's security rules authorise every request off Auth custom
/// claims, normally written by an `onUserWrite` Cloud Function whenever a
/// user document changes (see ../../firestore.rules). That function has
/// never been built, and Cloud Functions require the Blaze plan anyway —
/// this project stays on Spark. The Admin SDK can set custom claims
/// directly from a service account, without Cloud Functions or Blaze, so
/// this script does by hand what `onUserWrite` would otherwise automate:
/// create the Auth user, write its `users/{uid}` Firestore profile, and set
/// matching custom claims, all in the exact shape `AppUser`/`AccessScope`
/// expect (lib/features/auth/domain/entity/{app_user,access_scope}.dart).
///
/// Run it again by hand for future admin accounts until `onUserWrite` is
/// built and this project upgrades to Blaze.
///
/// Usage:
///   node bootstrap-admin.js <path-to-service-account.json>

const admin = require('firebase-admin');
const path = require('path');
const readline = require('readline');

function ask(question, { hidden = false } = {}) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    if (hidden) {
      // Mutes echo for the password prompt only; readline still needs a
      // real output stream to render the question text itself.
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

async function main() {
  const serviceAccountPath = process.argv[2];
  if (!serviceAccountPath) {
    console.error('Usage: node bootstrap-admin.js <path-to-service-account.json>');
    process.exitCode = 1;
    return;
  }

  const serviceAccount = require(path.resolve(serviceAccountPath));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

  const email = await ask('Super Admin email: ');
  const password = await ask('Super Admin password (min 6 characters): ', { hidden: true });
  const displayName = await ask('Display name: ');

  if (!email || !password || password.length < 6) {
    console.error('Email and a password of at least 6 characters are required.');
    process.exitCode = 1;
    return;
  }

  const userRecord = await admin.auth().createUser({
    email,
    password,
    displayName: displayName || email,
  });

  // Matches AccessScope.toClaims() for ScopeLevel.global exactly.
  const claims = {
    role: 'SUPER_ADMIN',
    lvl: 'GLOBAL',
    st: [],
    di: [],
    cl: [],
    sc: [],
  };
  await admin.auth().setCustomUserClaims(userRecord.uid, claims);

  // Matches AppUser.toJson() / AccessScope.toJson() — the shape
  // FirebaseAuthService reads back via AppUser.tryFromJson.
  await admin.firestore().collection('users').doc(userRecord.uid).set({
    email,
    displayName: displayName || email,
    phone: null,
    role: 'SUPER_ADMIN',
    scope: {
      level: 'GLOBAL',
      stateIds: [],
      districtIds: [],
      clusterIds: [],
      schoolIds: [],
      gradeSections: [],
    },
    isActive: true,
    lastLoginAt: null,
    claimsVersion: 1,
  });

  console.log(`\nCreated Super Admin ${email} (uid ${userRecord.uid}).`);
  console.log('Custom claims and Firestore profile are set. Sign in from the app with this email and password.');
  console.log(
    '\nNote: the ID token caches claims for up to an hour. If you change this ' +
      'account\'s role or scope later by re-running a similar script, sign out ' +
      'and back in (or call getIdToken(true)) to pick up the new claims.',
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Bootstrap failed:', error.message || error);
    process.exit(1);
  });
