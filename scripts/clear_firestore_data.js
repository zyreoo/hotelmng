
const admin = require('firebase-admin');
const path = require('path');

const COLLECTIONS_TO_CLEAR = [
  'bookings',
  'departments',
  'employers',
  'hotels',
  'roles',
  'services',
  'shift_presets',
  'shifts',
  'users',
];

async function deleteCollection(db, collectionPath) {
  const ref = db.collection(collectionPath);
  const snapshot = await ref.get();
  if (snapshot.empty) {
    console.log(`  ${collectionPath}: (empty)`);
    return;
  }
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  console.log(`  ${collectionPath}: deleted ${snapshot.size} doc(s)`);
}

async function main() {
  const keyPath = path.join(__dirname, 'serviceAccountKey.json');
  try {
    require.resolve(keyPath);
  } catch {
    console.error('Missing scripts/serviceAccountKey.json');
    console.error('Get it from: Firebase Console → Project Settings → Service accounts → Generate new private key');
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(keyPath) });
  const db = admin.firestore();

  console.log('Clearing root-level Firestore collections...\n');
  for (const name of COLLECTIONS_TO_CLEAR) {
    try {
      await deleteCollection(db, name);
    } catch (e) {
      console.error(`  ${name}: error -`, e.message);
    }
  }
  console.log('\nDone. Firestore root data cleared.');
  process.exit(0);
}

main();
