import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import { Message } from "firebase-admin/lib/messaging/messaging-api";

admin.initializeApp();

export const trainSchedule = onSchedule("every day 12:00", async () => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const notifyPromises: Promise<any>[] = [];

    todosSnap.forEach((doc) => {
      const data = doc.data() as any;
      if (data && data.trainAlert === true) {
        logger.info(`Scheduling train notification for user ${doc.id}`);
        notifyPromises.push(executeTrainNotification(doc.id));
      }
    });

    await Promise.all(notifyPromises);
  } catch (e) {
    logger.error(e)
  }
});

export const trainScheduleTest = onRequest({cors: false}, async (req, res) => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const notifyPromises: Promise<any>[] = [];
    logger.info(`checking for ${todosSnap.size} users`)
    todosSnap.forEach((doc) => {
      logger.info(`chec for ${doc.id}`)
      const data = doc.data() as any;
      if (data && data.trainAlert === true) {
        logger.info(`Scheduling train notification for user ${doc.id}`);
        notifyPromises.push(executeTrainNotification(doc.id));
      }
    });

    const result = await Promise.all(notifyPromises);
    res.status(200).send(result);
  } catch (e) {
    res.status(500).send(e)
  }
});


async function executeTrainNotification(userId: string) {
  const date = new Date().toISOString().split("T")[0];

  try {
    const querySnapshot = await admin.firestore().collection("todos")
      .doc(userId)
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
    const url = `http://www3.septa.org/api/NextToArrive/index.php?req1=${encodeURIComponent(start)}&req2=${encodeURIComponent(end)}&req3=10`;
    logger.info("Fetching SEPTA data");

    const resp = await fetch(url);
    const trains = await resp.json();
    if (!trains || trains.length == 0) {
      logger.info("No trains returned");
      return { error: "No trains returned" };
    }

    const parse12ToMinutes = (t: string): number => {
      const s = t.replace(/\s+/g, '').toUpperCase(); 
      const m = s.match(/^(\d{1,2}):(\d{2})(AM|PM)$/);
      if (!m) throw new Error(`Invalid 12h time: ${t}`);
      let hh = parseInt(m[1], 10);
      const mm = parseInt(m[2], 10);
      const ampm = m[3];
      if (ampm === "AM" && hh === 12) hh = 0;
      if (ampm === "PM" && hh < 12) hh += 12;
      return hh * 60 + mm;
    };

    const parse24ToMinutes = (t: string): number => {
      const parts = t.split(":").map(p => parseInt(p, 10));
      if (parts.length !== 2 || Number.isNaN(parts[0]) || Number.isNaN(parts[1])) {
        throw new Error(`Invalid 24h time: ${t}`);
      }
      return parts[0] * 60 + parts[1];
    };

    
    // Find train next train after the task's startTime
    const startMinutes = parse24ToMinutes(todo.startTime);
    const train = trains.reduce((match: any, t: any) => {
      try {
        const curDepMinutes = parse12ToMinutes(match.orig_departure_time);
        const currentDiff = curDepMinutes - startMinutes;
        const depMinutes = parse12ToMinutes(t.orig_departure_time);
        const diff = depMinutes - startMinutes;
        logger.info(`Start: ${startMinutes}, Acc: ${currentDiff}, Cur: ${diff}`)
        
        // If the train is at the exact start time or in the future
        // return the train with the lowest diff 
        if (diff >= 0 && (diff < currentDiff || currentDiff < 0)) {
          match = t;
        }
        // If the train is before the start time
        // return the train closest to the start time
        if (diff < 0 && (diff > currentDiff && currentDiff < 0)) {
          match = t;
        }
      } catch (e) {
        // skip malformed times
        logger.warn(`Skipping malformed train time: ${t.orig_train} - ${t.orig_departure_time}: ${e}`);
      }
      return match;
    }, trains[0]);

    const fcmToken = await getUserFcmToken(userId)
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

export const sendMessage = onRequest(async (request, response) => {
  const userId = request.body.userId;
  const payload = request.body.payload;

  if (!userId || !payload) {
    response.status(400).send("Missing userId or payload");
    return;
  }

  try {
    const userDoc = await admin.firestore().collection("todos").doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      response.status(404).send("FCM token not found for user");
      return;
    }

    if (payload.body == null || payload.title == null) { 
      response.status(400).send("Missing body or title in payload");
      return; 
    }
    const message: Message = {
      token: fcmToken,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: {
        ...payload.data,
      }
    };

    await admin.messaging().send(message);
    response.status(200).send("Message sent successfully");
  } catch (error) {
    console.error("Error sending message:", error);
    response.status(500).send("Error sending message");
  }
});

async function getUserFcmToken(userId: string): Promise<string> {
  const userDoc = await admin.firestore().collection('todos').doc(userId).get()
  const data = userDoc.data()
  if (!data) {
    throw Error("user does not exist")
  }
  return data.fcmToken;
}

// TODO: Should be a general cloud function to create a new task.

// export const addWindTaskFromNotification = onRequest({cors: false}, async (req, res) => {
//   const endHour = req.body.endHour;
//   const startHour = req.body.startHour;
//   const body = req.body.body;
//   const date = req.body.date;
//   const uid = req.body.uid;

//   if (!uid || !date || !body) {
//     res.status(400).send("Missing required parameters");
//     return;
//   }

//   try {
//     // await addWindTask(uid as string, date as string, body as string, startHour as string | undefined, endHour as string | undefined);
//     res.status(200).send("Task added");
//   } catch (error) {
//     logger.error("Error adding wind task:", error);
//     res.status(500).send("Error adding wind task");
//   }
// });

