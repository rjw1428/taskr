import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp, firestore } from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";


async function completedTaskCleanup() {
  initializeApp();

  try {
    const todoRef = await firestore().collection("todos").get();
    todoRef.docs.forEach(async (doc) => {
      const deleteIds: String[] = [];
      const deletes: Promise<firestore.WriteResult>[] = [];

      const userId = doc.id;
      const completedDocs = await firestore()
        .collection("todos")
        .doc(userId)
        .collection("tasks")
        .where("completed", "==", true)
        .get();

      // For each documnet
      completedDocs.forEach((doc) => {
        // Add doc id to user's array
        deleteIds.push(doc.id)

        // Add delete task to promise queue
        deletes.push(doc.ref.delete())
      });

      // add the delete task for the "taskOrder"
      deletes.push(firestore().collection("todos").doc(userId).update({
        taskOrder: FieldValue.arrayRemove(deleteIds)
      }))
      
      // execute promie queue for single user
      await Promise.all(deletes);
    });
  } catch (err) {
    logger.log(err);
  }

}


export const scheduledCompletedTaskCleanup = onSchedule("every day 03:00", async (event) => {
  await completedTaskCleanup()
});

export const triggeredCompletedTaskCleanup = onRequest({cors: false}, async (req, res) => {
  await completedTaskCleanup()
  res.status(200).send("Mission Accomplished!");
})
