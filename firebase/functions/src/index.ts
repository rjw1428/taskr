import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import {FieldValue} from "firebase-admin/firestore";
import axios from "axios";
import * as https from 'https';

const httpsAgent = new https.Agent({
    // Standard secure cipher suites
    ciphers: 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:HIGH:!aNULL:!MD5',
    honorCipherOrder: true,
    minVersion: 'TLSv1.2'
});

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

export const triggeredCompletedTaskCleanup = onRequest({cors: false}, async (req, res) => {
  await completedTaskCleanup();
  res.status(200).send("Mission Accomplished!");
});

export const windspeedCheck = onSchedule("every day 15:00", async () => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const notifyPromises: Promise<any>[] = [];

    todosSnap.forEach((doc) => {
      const data = doc.data() as any;
      if (data && data.weatherAlert === true) {
        logger.info(`Checking windspeed for user ${doc.id}`);
        notifyPromises.push(getWindspeed(doc.id));
      }
    });

    await Promise.all(notifyPromises);
  } catch (e) {
    logger.error(e)
  }
});

export const windspeedCheckTest = onRequest({cors: false}, async (req, res) => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const notifyPromises: Promise<any>[] = [];

    todosSnap.forEach((doc) => {
      const data = doc.data() as any;
      if (data && data.weatherAlert === true) {
        logger.info(`Checking windspeed for user ${doc.id}`);
        notifyPromises.push(getWindspeed(doc.id));
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

    const resp = await axios.get(url, { httpsAgent });
    const trains = resp.data;
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


async function getWindspeed(userId: string) {
  const zip = "18966";
  const api = `https://wttr.in/${zip}?format=j1`;
  const threshold = 15; // mph
  let lastHighWindHour
  try {
    const resp = await axios.get(api, { httpsAgent });
    const data = resp.data;
    
    const formatTime = (timeStr: string) => {
      const time = parseInt(timeStr, 10);
      const hours = Math.floor(time / 100);
      const ampm = hours >= 12 ? 'pm' : 'am';
      const displayHours = hours % 12 || 12;
      return `${displayHours}${ampm}`;
    };

    const todayHourly = data.weather[0].hourly
      .filter((h: any) => parseInt(h.time) >= 900);

    const tomorrowHourly = data.weather[1].hourly
      .filter((h: any) => parseInt(h.time) < 900);

    const hourlyForecast = [...todayHourly, ...tomorrowHourly].map((h: any) => ({
      time: h.time,
      formattedTime: formatTime(h.time),
      windspeed: parseInt(h.windspeedMiles)
    }));

    const highWinds = hourlyForecast.filter((h: any) => h.windspeed >= threshold);

    if (highWinds.length == 0) {
      logger.info("No high winds today");
      return "No high winds today";
    }

    const startTime = highWinds[0].formattedTime;
    const maxWindspeed = Math.max(...highWinds.map((h: any) => h.windspeed));
    let body = "";

    const lastForecastHour = hourlyForecast[hourlyForecast.length - 1];
    lastHighWindHour = highWinds[highWinds.length - 1];

    if (lastHighWindHour.time === lastForecastHour.time) {
      body = `High winds starting at ${startTime} and continuing into tomorrow, with gusts up to ${maxWindspeed} mph.`;
    } else {
      const endTime = lastHighWindHour.formattedTime;
      if (startTime === endTime) {
        body = `High winds of ${maxWindspeed} mph expected around ${startTime}.`;
      } else {
        body = `High winds expected from ${startTime} to ${endTime}, with gusts up to ${maxWindspeed} mph.`;
      }
    }
    const fcmToken = await getUserFcmToken(userId)

    const toHourMinute = (t: string) => {
      const n = parseInt(t, 10);
      if (Number.isNaN(n)) return t;
      const hh = Math.floor(n / 100);
      const mm = n % 100;
      return `${hh}:${mm.toString().padStart(2, "0")}`;
    };

    const startHour = toHourMinute(highWinds[0].time);
    const date = new Date().toISOString().split("T")[0];
    let endHour = null;
    if (lastHighWindHour.time !== lastForecastHour.time) {
      endHour = lastHighWindHour.time;
    }
    
    if (highWinds.length === 1) {
      endHour = (parseInt(lastHighWindHour.time) + 100).toString()
    }

    const message = {
      token: fcmToken,
      notification: {
        title: "Batten Down the Decorations!",
        body: body,
      },
      data: {
        actions: JSON.stringify([
          {
            action: "add-wind-task",
            title: "Yes",
          },
          {
            action: "dismiss",
            title: "No",
          },
        ]),
        date: date,
        body: body,
        startHour: startHour,
        endHour: toHourMinute(endHour),
      },
    };

    await admin.messaging().send(message);
    logger.info(`Notification sent regarding high winds`);

    return body;
  } catch (e) {
   logger.error(e);
   return "Something went wrong"
  }
}

export const addWindTaskFromNotification = onRequest({cors: false}, async (req, res) => {
  const {uid, date, body, startHour, endHour} = req.query;

  if (!uid || !date || !body) {
    res.status(400).send("Missing required parameters");
    return;
  }

  await addWindTask(uid as string, date as string, body as string, startHour as string | undefined, endHour as string | undefined);
  res.status(200).send("Task added");
});

async function addWindTask(uid: string, date: string, body: string, startHour?: string, endHour?: string) {
    const task = {
      title: "Batten Down Christmas Decorations",
      description: body,
      startTime: startHour,
      endTime: endHour,
      priority: "low",
      completed: false,
      dueDate: date,
      pushCount: 0,
      added: Date.now(),
      tags: [],
      subtasks: []
    };
    
    logger.info(`Adding task to ${date}`)
    const docRef = await admin.firestore()
      .collection("todos")
      .doc(uid)
      .collection("tasks")
      .doc(date)
      .collection("items")
      .add(task);

    logger.info(`Adding ${docRef.id} to task order`)
    await admin.firestore()
      .collection("todos")
      .doc(uid)
      .collection("tasks")
      .doc(date)
      .update({taskOrder: FieldValue.arrayUnion(docRef.id)});
}

async function getUserFcmToken(userId: string): Promise<string> {
  const userDoc = await admin.firestore().collection('todos').doc(userId).get()
  const data = userDoc.data()
  if (!data) {
    throw Error("user does not exist")
  }
  return data.fcmToken;
}