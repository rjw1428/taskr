import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp, firestore } from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";


async function completedTaskCleanup() {
  initializeApp();

  const deletes: Promise<firestore.WriteResult>[] = [];

  try {
    const todoRef = await firestore().collection("todos").get();
    todoRef.docs.forEach(async (doc) => {
      const userId = doc.id;
      const completedDocs = await firestore()
        .collection("todos")
        .doc(userId)
        .collection("tasks")
        .where("completed", "==", true)
        .get();
      completedDocs.forEach((doc) => deletes.push(doc.ref.delete()));
    });
  } catch (err) {
    logger.log(err);
  }

  await Promise.all(deletes);
}


export const scheduledCompletedTaskCleanup = onSchedule("every day 03:00", async (event) => {
  await completedTaskCleanup()
});

export const triggeredCompletedTaskCleanup = onRequest({cors: false}, async (req, res) => {
  await completedTaskCleanup()
  res.status(200).send("Mission Accomplished!");
})
