// fix_missing_categories.js
// This script ensures every 'menu/{categoryId}/items' subcollection has a parent 'menu/{categoryId}' document.
// It now uses Application Default Credentials (ADC) and works with Firebase CLI user credentials.

const admin = require('firebase-admin');

// Initialize Firebase Admin SDK with ADC and explicit projectId
admin.initializeApp({ projectId: 'dumplinghouseapp' });

const db = admin.firestore();

async function main() {
  const menuRef = db.collection('menu');
  const categoriesWithItems = new Set();

  // List all subcollections under 'menu' (categories)
  const menuSnap = await menuRef.get();
  for (const doc of menuSnap.docs) {
    const itemsSnap = await doc.ref.collection('items').limit(1).get();
    if (!itemsSnap.empty) {
      categoriesWithItems.add(doc.id);
    }
  }

  // Also check for orphaned subcollections (in case category doc is missing)
  // Firestore does not provide a direct way to list all subcollections without a parent doc,
  // so we rely on the above. If you know of any orphaned subcollections, add their IDs here manually.

  // For each category with items, ensure the parent doc exists
  for (const categoryId of categoriesWithItems) {
    const catDoc = menuRef.doc(categoryId);
    const catSnap = await catDoc.get();
    if (!catSnap.exists) {
      console.log(`Creating missing category document: ${categoryId}`);
      await catDoc.set({ name: categoryId });
    } else {
      console.log(`Category document exists: ${categoryId}`);
    }
  }

  console.log('Done.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
}); 