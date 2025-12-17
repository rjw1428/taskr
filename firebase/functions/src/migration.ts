import * as admin from 'firebase-admin';

// The Firebase Admin SDK is automatically initialized when deployed to Cloud Functions.
// For local development, you might need to initialize it explicitly if not using firebase-functions-test.
// admin.initializeApp(); // Call without arguments when deployed to functions

const db = admin.firestore();

/**
 * Migrates tasks from a date-nested structure to a single collection for a given user.
 *
 * It moves tasks from:
 *   /todos/{userId}/tasks/{date}/items/{taskId}
 * to:
 *   /todos/{userId}/tasks/{taskId}
 *
 * and adds a `sortOrder` field to each task based on its position in the
 * `/todos/{userId}/tasks/{date}.taskOrder` array.
 *
 * @param {string} userId The ID of the user whose tasks will be migrated.
 * @param {string} startDate The start date of the range to process (inclusive, YYYY-MM-DD).
 * @param {string} endDate The end date of the range to process (inclusive, YYYY-MM-DD).
 */
export async function migrateTasksForUser(
  userId: string,
  startDate: string,
  endDate: string
): Promise<void> {
  if (!userId || !startDate || !endDate) {
    console.error("Error: userId, startDate, and endDate must be provided.");
    return;
  }

  console.log(`Starting task migration for user: ${userId}`);
  console.log(`Date range: ${startDate} to ${endDate}`);

  const dailyTasksCollectionRef = db.collection(`todos/${userId}/tasks`);

  try {
    // 1. Get all daily task summary documents.
    const dailyDocsSnapshot = await dailyTasksCollectionRef.get();

    if (dailyDocsSnapshot.empty) {
      console.log(`No daily task collections found for user ${userId}. Nothing to migrate.`);
      return;
    }

    const migrationPromises: Promise<FirebaseFirestore.WriteResult[]>[] = [];

    // 2. Filter for dates within the specified range.
    for (const dayDoc of dailyDocsSnapshot.docs) {
      const date = dayDoc.id; // The document ID is the date string 'YYYY-MM-DD'
      if (date >= startDate && date <= endDate) {
        console.log(`\nProcessing tasks for date: ${date}`);
        const dayData = dayDoc.data();
        const taskOrder: string[] = dayData.taskOrder;

        if (!taskOrder || !Array.isArray(taskOrder)) {
          console.warn(`- WARN: No 'taskOrder' array found for ${date}. Skipping.`);
          continue;
        }

        if (taskOrder.length === 0) {
          console.log(`- INFO: 'taskOrder' is empty for ${date}. Deleting day document.`);
          migrationPromises.push(dayDoc.ref.delete().then(res => [res])); // Wrap in array for type compatibility
          continue;
        }

        // Get all task items from the subcollection.
        const itemsRef = dayDoc.ref.collection('items');
        const itemsSnapshot = await itemsRef.get();

        if (itemsSnapshot.empty) {
            console.warn(`- WARN: 'taskOrder' array has items but the 'items' subcollection is empty for ${date}. Deleting day document.`);
            migrationPromises.push(dayDoc.ref.delete().then(res => [res])); // Wrap in array for type compatibility
            continue;
        }

        // Prepare a batch write for this day's migration.
        const batch = db.batch();
        const newTasksCollectionRef = db.collection(`todos/${userId}/tasks`);

        console.log(`- Found ${itemsSnapshot.size} tasks to migrate for ${date}.`);

        itemsSnapshot.forEach(taskDoc => {
          const taskId = taskDoc.id;
          const taskData = taskDoc.data();
          const sortOrder = taskOrder.indexOf(taskId);

          if (sortOrder === -1) {
            console.warn(`  - WARN: Task ${taskId} found in 'items' but not in 'taskOrder' array for ${date}. It will be migrated without a sortOrder.`);
            // Decide how to handle this case. Here, we add it without a sortOrder.
            // You could also assign a default, like 999, or skip it.
            batch.set(newTasksCollectionRef.doc(taskId), taskData);
          } else {
            const newData = { ...taskData, sortOrder: sortOrder };
            batch.set(newTasksCollectionRef.doc(taskId), newData);
            console.log(`  - Staging migration for task ${taskId} with sortOrder: ${sortOrder}`);
          }

          // Stage the deletion of the old task document.
          batch.delete(taskDoc.ref);
        });

        // After processing all items, stage the deletion of the parent day document.
        batch.delete(dayDoc.ref);
        console.log(`- Staging deletion of day document: ${date}`);

        // Add the commit promise to our array.
        migrationPromises.push(batch.commit());
      }
    }

    if (migrationPromises.length === 0) {
        console.log("\nNo dates within the specified range had tasks to migrate.");
        return;
    }

    // 3. Execute all batch commits.
    console.log(`\nCommitting ${migrationPromises.length} batches...`);
    await Promise.all(migrationPromises);
    console.log("\nMigration completed successfully for all processed dates!");

  } catch (error) {
    console.error("\nAn error occurred during the migration process:", error);
    throw error; // Re-throw the error to ensure the Cloud Function reports failure
  }
}
