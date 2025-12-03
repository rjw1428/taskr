import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import {FieldValue} from "firebase-admin/firestore";
import axios from "axios";

admin.initializeApp();

async function completedTaskCleanup() {

  try {
    const todoRef = await admin.firestore().collection("todos").get();
    todoRef.docs.forEach(async (doc: any) => {
      const deleteIds: string[] = [];
      const deletes: Promise<admin.firestore.WriteResult>[] = [];

      const userId = doc.id;
      const completedDocs = await admin.firestore()
        .collection("todos")
        .doc(userId)
        .collection("tasks")
        .where("completed", "==", true)
        .get();

      // For each documnet
      completedDocs.forEach((doc: any) => {
        // Add doc id to user's array
        deleteIds.push(doc.id);

        // Add delete task to promise queue
        deletes.push(doc.ref.delete());
      });

      // add the delete task for the "taskOrder"
      deletes.push(admin.firestore().collection("todos").doc(userId).update({
        taskOrder: FieldValue.arrayRemove(deleteIds),
      }));

      // execute promie queue for single user
      await Promise.all(deletes);
    });
  } catch (err) {
    logger.log(err);
  }
}

export const trainSchedule = onSchedule("every day 12:00", async () => {
  await executeTrainNotification();
});

export const trainScheduleTest = onRequest({cors: false}, async (req, res) => {
  const result = await executeTrainNotification();
  res.status(200).send(result);
});

export const triggeredCompletedTaskCleanup = onRequest({cors: false}, async (req, res) => {
  await completedTaskCleanup();
  res.status(200).send("Mission Accomplished!");
});


async function executeTrainNotification() {
  const uid = "493KKO1BmXca1bRUVwa0PY6HzzT2";
  const fcmToken = "doCNrAEfThS47kUDVIsGR1:APA91bE5yC-fKlkKVMil9hMYmaN6zVMToXwWu5WnKmwcl7B-NTjKc3MxDpcB_sXhniUdP0jHZlqML2bf9g1eqRJdbstjjWzst4EjBHyVViiQObv20h5w2Qw";
  const date = new Date().toISOString().split("T")[0];

  try {
    const querySnapshot = await admin.firestore().collection("todos")
      .doc(uid)
      .collection("tasks")
      .doc(date)
      .collection("items")
      .where("title", "==", "Work Train")
      .get();

    if (querySnapshot.empty) {
      logger.info(`No 'work train' todos found on ${date}.`);
      return { error: `No 'work train' todos found on ${date}.` };
    }

    const doc = querySnapshot.docs[0];
    const todo = doc.data();
    if (!todo.startTime) {
      logger.info(`Document ${doc.id} did not have a start time`);
      return { error: `Document ${doc.id} did not have a start time` };
    }

    const start = "Somerton";
    const end = "Suburban Station";
    const url = `http://www3.septa.org/api/NextToArrive/index.php?req1=${encodeURIComponent(start)}&req2=${encodeURIComponent(end)}`;
    logger.info("Fetching SEPTA data");

    const resp = await axios.get(url);
    const trains = resp.data;
    if (!trains || trains.length == 0) {
      logger.info("No trains returned");
      return { error: "No trains returned" };
    }

    const train = trains[0];
    const data = {
      trainId: train.orig_train,
      delay: train.orig_delay,
      departure: train.orig_departure_time,
      arrival: train.orig_arrival_time,
    };
    const message = {
      token: fcmToken,
      notification: {
        title: `Train Update: ${train.orig_delay}`,
        body: `The ${train.orig_departure_time} train (${train.orig_train}) is ${train.orig_delay} and will be arriving at work at ${train.orig_arrival_time}`,
      },
      data,
    };

    await admin.messaging().send(message);
    logger.info(`Notification sent to ${doc.id} regarding train ${train.orig_train}`);
    return data;
  } catch (e) {
    logger.error("Error in checkTrainStatus function", e);
    return { error: e };
  }
}
