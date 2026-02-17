# Firestore index: Admin users list (date-ordered)

The admin users list uses a query ordered by **`accountCreatedDate` only** (single field). Firestore may use a **single-field index** for this. If you see "configure using single field index controls", enable indexing for that field as below.

## Option 1: Let Firestore auto-create

Run the admin users list (Date Created sort) once. Firestore often auto-creates a single-field index and may log a link. If the query still fails, use Option 2.

## Option 2: Enable single-field index (Console)

1. Open **Firestore → Indexes**:  
   https://console.firebase.google.com/project/dumplinghouseapp/firestore/indexes

2. Open the **"Single-field"** tab (or **"Field indexes"** / **"Exemptions"**, depending on Console layout).

3. Find the **`users`** collection and ensure **`accountCreatedDate`** has indexing enabled for **Descending** (and **Ascending** if you use "oldest first"). Add the field if it’s not listed, and enable the sort orders you need.

4. Save. Wait for the index to finish building if prompted.

## After the index is ready

The next time the app requests the users list with "Date Created" / "Descending" (or Ascending), the date-ordered query should succeed and you will no longer see the fallback message in the logs.
