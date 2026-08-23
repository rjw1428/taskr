import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest, onCall, HttpsError} from "firebase-functions/v2/https";
import { Message } from "firebase-admin/lib/messaging/messaging-api";
import {defineSecret} from "firebase-functions/params";
import {google} from "googleapis";
import {CloudTasksClient} from "@google-cloud/tasks";
import {
  COMMUTE_TIMEZONE,
  localDateIn,
  localTimeToEpochSeconds,
  parkingPromptDecision,
} from "./parking.logic";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const oauthClientSecret = defineSecret("GOOGLE_OAUTH_CLIENT_SECRET");
const oauthWebClientId = defineSecret("GOOGLE_OAUTH_WEB_CLIENT_ID");

admin.initializeApp();

// The two opt-ins are independent: a user can take the train without paying for
// parking, or park without wanting the SEPTA status push.
async function runTrainFanout() {
  const todosSnap = await admin.firestore().collection("todos").get();
  logger.info(`checking for ${todosSnap.size} users`);
  const notifyPromises: Promise<any>[] = [];

  todosSnap.forEach((doc) => {
    const data = doc.data() as any;
    if (!data) return;
    if (data.trainAlert === true) {
      logger.info(`Scheduling train notification for user ${doc.id}`);
      notifyPromises.push(executeTrainNotification(doc.id));
    }
    if (data.parkingAlert === true) {
      logger.info(`Scheduling parking prompt for user ${doc.id}`);
      notifyPromises.push(scheduleParkingPrompt(doc.id));
    }
  });

  return Promise.all(notifyPromises);
}

export const trainSchedule = onSchedule("every day 11:00", async () => {
  try {
    await runTrainFanout();
  } catch (e) {
    logger.error(e)
  }
});

export const trainScheduleTest = onRequest({cors: false}, async (req, res) => {
  try {
    const result = await runTrainFanout();
    res.status(200).send(result);
  } catch (e) {
    res.status(500).send(e)
  }
});


const WORK_TRAIN_TITLE = "Work Train";

/**
 * Finds today's "Work Train" task for a user. Returns null when there is no such
 * task, so both the train status push and the parking prompt share one lookup
 * instead of duplicating the query.
 */
async function findWorkTrainTask(userId: string, date: string) {
  const querySnapshot = await admin.firestore().collection("todos")
    .doc(userId)
    .collection("tasks")
    .doc(date)
    .collection("items")
    .where("title", "==", WORK_TRAIN_TITLE)
    .get();

  if (querySnapshot.empty) return null;
  return querySnapshot.docs[0];
}

async function executeTrainNotification(userId: string) {
  // Commute-local, not UTC: the task partitions are keyed by local date.
  const date = localDateIn(COMMUTE_TIMEZONE);

  try {
    const doc = await findWorkTrainTask(userId, date);

    if (!doc) {
      logger.info(`No 'work train' todos found on ${date}.`);
      return { error: `No 'work train' todos found on ${date}.` };
    }

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
    await recordNotification(userId, {
      title: message.notification?.title ?? "Train Update",
      body: message.notification?.body ?? "",
      data,
      type: "train",
    });
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
    await recordNotification(userId, {
      title: payload.title,
      body: payload.body,
      data: payload.data,
      type: payload.data?.type,
    });
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

// Persist a record of every FCM message we send so the app's Notification
// Center can review/clear them. Best-effort: never let a logging failure break
// the actual push send.
async function recordNotification(
  userId: string,
  n: {title: string; body: string; data?: Record<string, unknown>; type?: string}
): Promise<void> {
  try {
    await admin.firestore()
      .collection("todos").doc(userId)
      .collection("notifications").add({
        title: n.title,
        body: n.body,
        data: n.data ?? {},
        type: n.type ?? (n.data ? (n.data as {type?: string}).type ?? null : null),
        sentAt: Date.now(),
        read: false,
      });
  } catch (e) {
    logger.warn(`recordNotification failed for ${userId}:`, e);
  }
}

// --- Goal Reminder Functions ---

async function getIncompleteGoalTasksForToday(userId: string): Promise<{taskCount: number; goalNames: string[]}> {
  const date = new Date().toISOString().split("T")[0];
  const tasksSnap = await admin.firestore()
    .collection("todos").doc(userId)
    .collection("tasks").doc(date)
    .collection("items")
    .where("goalId", "!=", null)
    .where("completed", "==", false)
    .get();

  if (tasksSnap.empty) return {taskCount: 0, goalNames: []};

  const goalIds = new Set<string>();
  tasksSnap.forEach((doc) => {
    const data = doc.data();
    if (data.goalId) goalIds.add(data.goalId);
  });

  const goalNames: string[] = [];
  for (const goalId of goalIds) {
    const goalDoc = await admin.firestore()
      .collection("todos").doc(userId)
      .collection("goals").doc(goalId)
      .get();
    const goalData = goalDoc.data();
    if (goalData && goalData.status === "active") {
      goalNames.push(goalData.title);
    }
  }

  if (goalNames.length === 0) return {taskCount: 0, goalNames: []};

  return {taskCount: tasksSnap.size, goalNames};
}

async function sendGoalReminder(userId: string, messagePrefix: string): Promise<void> {
  try {
    const {taskCount, goalNames} = await getIncompleteGoalTasksForToday(userId);
    if (taskCount === 0) return;

    const fcmToken = await getUserFcmToken(userId);
    if (!fcmToken) return;

    const goalText = goalNames.length === 1 ? goalNames[0] : `${goalNames.length} goals`;
    const message: Message = {
      token: fcmToken,
      notification: {
        title: `${messagePrefix}`,
        body: `You have ${taskCount} goal task${taskCount > 1 ? "s" : ""} remaining today for ${goalText}`,
      },
      data: {
        type: "goal_reminder",
      },
    };

    await admin.messaging().send(message);
    await recordNotification(userId, {
      title: message.notification?.title ?? "Goal Reminder",
      body: message.notification?.body ?? "",
      type: "goal_reminder",
    });
    logger.info(`Goal reminder sent to user ${userId}: ${taskCount} tasks`);
  } catch (e) {
    logger.error(`Error sending goal reminder to ${userId}:`, e);
  }
}

export const goalReminder5pm = onSchedule("every day 17:00", async () => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const promises: Promise<void>[] = [];

    todosSnap.forEach((doc) => {
      const data = doc.data();
      if (data && data.fcmToken) {
        promises.push(sendGoalReminder(doc.id, "Goal Reminder"));
      }
    });

    await Promise.all(promises);
  } catch (e) {
    logger.error("Error in goalReminder5pm:", e);
  }
});

export const goalReminder9pm = onSchedule("every day 21:00", async () => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const promises: Promise<void>[] = [];

    todosSnap.forEach((doc) => {
      const data = doc.data();
      if (data && data.fcmToken) {
        promises.push(sendGoalReminder(doc.id, "Don't forget"));
      }
    });

    await Promise.all(promises);
  } catch (e) {
    logger.error("Error in goalReminder9pm:", e);
  }
});

// --- Weekly Goal Task Generation ---
// Note: Task generation uses VertexAI which runs client-side on initial creation.
// This function handles the weekly server-side regeneration.

export const generateGoalTasks = onSchedule({schedule: "every sunday 20:00", secrets: [geminiApiKey]}, async () => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    const promises: Promise<void>[] = [];

    for (const userDoc of todosSnap.docs) {
      const goalsSnap = await admin.firestore()
        .collection("todos").doc(userDoc.id)
        .collection("goals")
        .where("status", "==", "active")
        .get();

      if (!goalsSnap.empty) {
        for (const goalDoc of goalsSnap.docs) {
          const goalData = goalDoc.data();
          const endDate = new Date(goalData.endDate);
          if (endDate > new Date()) {
            promises.push(generateWeeklyTasksForGoal(userDoc.id, goalDoc.id, goalData));
          }
        }
      }
    }

    await Promise.all(promises);
    logger.info(`Weekly goal task generation complete. Processed ${promises.length} goals.`);
  } catch (e) {
    logger.error("Error in generateGoalTasks:", e);
  }
});

export const generateGoalTasksTest = onRequest({cors: false, secrets: [geminiApiKey]}, async (req, res) => {
  try {
    const todosSnap = await admin.firestore().collection("todos").get();
    let processed = 0;

    for (const userDoc of todosSnap.docs) {
      const goalsSnap = await admin.firestore()
        .collection("todos").doc(userDoc.id)
        .collection("goals")
        .where("status", "==", "active")
        .get();

      for (const goalDoc of goalsSnap.docs) {
        const goalData = goalDoc.data();
        const endDate = new Date(goalData.endDate);
        if (endDate > new Date()) {
          await generateWeeklyTasksForGoal(userDoc.id, goalDoc.id, goalData);
          processed++;
        }
      }
    }

    res.status(200).send({processed});
  } catch (e) {
    logger.error("Error in generateGoalTasksTest:", e);
    res.status(500).send({error: String(e)});
  }
});

async function generateWeeklyTasksForGoal(
  userId: string,
  goalId: string,
  goalData: admin.firestore.DocumentData
): Promise<void> {
  try {
    const generationsSnap = await admin.firestore()
      .collection("todos").doc(userId)
      .collection("goals").doc(goalId)
      .collection("generations")
      .orderBy("generatedAt", "desc")
      .limit(3)
      .get();

    const history = generationsSnap.docs.map((doc) => doc.data());
    const weekNumber = generationsSnap.size + 1;

    let prompt = `Goal: ${goalData.title}\n`;
    if (goalData.description) prompt += `Description: ${goalData.description}\n`;
    prompt += `Timeframe: ${goalData.timeframe}\n`;
    prompt += `Frequency: ${goalData.frequency}`;
    if (goalData.frequency === "n_times_week" && goalData.frequencyCount) {
      prompt += ` (${goalData.frequencyCount}x)`;
    }
    prompt += `\nThis is week ${weekNumber}.\n`;

    if (history.length > 0) {
      prompt += "\nPrevious weeks:\n";
      for (const gen of history) {
        prompt += `  ${gen.weekStart} to ${gen.weekEnd}:\n`;
        prompt += `    Tasks generated: ${gen.taskIds?.length || 0}\n`;
        prompt += `    Completed: ${gen.completedTaskIds?.length || 0}\n`;

        if (gen.response) {
          try {
            const genTasks = JSON.parse(gen.response) as any[];
            const completedTitles: string[] = [];
            const skippedTitles: string[] = [];
            for (let i = 0; i < genTasks.length; i++) {
              const title = genTasks[i].title || "";
              const taskId = gen.taskIds?.[i];
              if (taskId && gen.completedTaskIds?.includes(taskId)) {
                completedTitles.push(title);
              } else {
                skippedTitles.push(title);
              }
            }
            if (completedTitles.length > 0) {
              prompt += `    Completed tasks: ${completedTitles.join(", ")}\n`;
            }
            if (skippedTitles.length > 0) {
              prompt += `    Skipped tasks: ${skippedTitles.join(", ")}\n`;
            }
          } catch {}
        }

        const taskFeedback = gen.taskFeedback as Record<string, string> | undefined;
        if (taskFeedback && Object.keys(taskFeedback).length > 0) {
          prompt += "    User feedback:\n";
          try {
            const genTasks = JSON.parse(gen.response) as any[];
            for (const [taskId, feedback] of Object.entries(taskFeedback)) {
              const taskIndex = gen.taskIds?.indexOf(taskId) ?? -1;
              const title = taskIndex >= 0 && taskIndex < genTasks.length
                ? genTasks[taskIndex].title
                : "Task";
              prompt += `      "${title}": ${feedback}\n`;
            }
          } catch {
            for (const [, feedback] of Object.entries(taskFeedback)) {
              prompt += `      ${feedback}\n`;
            }
          }
        }
      }
    }

    if (goalData.frequency === "daily") {
      prompt += "\nGenerate 7 tasks, one per day (dayOffset 0=Mon to 6=Sun).\n";
    } else if (goalData.frequency === "n_times_week" && goalData.frequencyCount) {
      prompt += `\nGenerate ${goalData.frequencyCount} tasks spread across the week.\n`;
    } else {
      prompt += "\nDecide the best number and distribution of tasks.\n";
    }
    prompt += "Build on prior progress. Do not repeat completed tasks. Adapt if tasks were skipped.\n";
    prompt += "Incorporate user feedback when provided — adjust difficulty, relevance, and task types accordingly.\n";
    prompt += "Return ONLY a JSON array of {title, description, dayOffset, effort}.";

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      logger.error("GEMINI_API_KEY secret not set");
      return;
    }

    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

    const geminiResponse = await fetch(geminiUrl, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        system_instruction: {
          parts: [{
            text: "You are a personal development coach. Generate concrete, actionable tasks. Take into account user feedback from previous weeks to improve task quality. Return ONLY a JSON array of objects with: title (string), description (string), dayOffset (int 0-6), effort (low/medium/high).",
          }],
        },
        contents: [{role: "user", parts: [{text: prompt}]}],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                title: {type: "STRING"},
                description: {type: "STRING"},
                dayOffset: {type: "INTEGER"},
                effort: {type: "STRING", enum: ["low", "medium", "high"]},
              },
              required: ["title", "description", "dayOffset", "effort"],
            },
          },
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errText = await geminiResponse.text();
      logger.error(`Gemini API error ${geminiResponse.status} for goal ${goalId}: ${errText}`);
      return;
    }

    const geminiData = await geminiResponse.json() as any;
    let tasksText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text || "";
    tasksText = tasksText.trim();

    let tasks: any[] | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const parsed = JSON.parse(tasksText);
        if (Array.isArray(parsed)) {
          tasks = parsed;
          break;
        }
        logger.warn(`LLM response is not an array for goal ${goalId} (attempt ${attempt + 1})`);
      } catch {
        logger.warn(`Failed to parse LLM response for goal ${goalId} (attempt ${attempt + 1}): ${tasksText.substring(0, 200)}`);
      }

      if (attempt === 0) {
        logger.info(`Retrying Gemini request for goal ${goalId}`);
        const retryResponse = await fetch(geminiUrl, {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({
            system_instruction: {
              parts: [{
                text: "You are a personal development coach. Generate concrete, actionable tasks. Take into account user feedback from previous weeks to improve task quality. Return ONLY a JSON array of objects with: title (string), description (string), dayOffset (int 0-6), effort (low/medium/high).",
              }],
            },
            contents: [{role: "user", parts: [{text: prompt}]}],
            generationConfig: {
          responseMimeType: "application/json",
          responseSchema: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                title: {type: "STRING"},
                description: {type: "STRING"},
                dayOffset: {type: "INTEGER"},
                effort: {type: "STRING", enum: ["low", "medium", "high"]},
              },
              required: ["title", "description", "dayOffset", "effort"],
            },
          },
        },
          }),
        });
        if (!retryResponse.ok) {
          logger.error(`Gemini retry failed for goal ${goalId}: ${retryResponse.status}`);
          return;
        }
        const retryData = await retryResponse.json() as any;
        tasksText = (retryData?.candidates?.[0]?.content?.parts?.[0]?.text || "").trim();
      }
    }

    if (!tasks) {
      logger.error(`Failed to get valid LLM response for goal ${goalId} after retries`);
      return;
    }

    const now = new Date();
    const monday = new Date(now);
    monday.setDate(now.getDate() - now.getDay() + 1 + 7);
    const weekStart = monday.toISOString().split("T")[0];
    const weekEndDate = new Date(monday);
    weekEndDate.setDate(monday.getDate() + 6);
    const weekEnd = weekEndDate.toISOString().split("T")[0];

    const taskIds: string[] = [];
    for (const task of tasks) {
      const dayOffset = Math.min(Math.max(task.dayOffset || 0, 0), 6);
      const taskDate = new Date(monday);
      taskDate.setDate(monday.getDate() + dayOffset);
      const dateStr = taskDate.toISOString().split("T")[0];

      const taskData = {
        title: task.title || "Goal task",
        description: task.description || "",
        priority: task.effort || "low",
        completed: false,
        dueDate: dateStr,
        goalId: goalId,
        // Denormalized owner so goal progress can be counted via a collection-group
        // query on (userId, goalId) across date partitions.
        userId: userId,
        added: Date.now(),
        modified: "",
        tags: [],
        subtasks: [],
        pushCount: 0,
      };

      const taskRef = await admin.firestore()
        .collection("todos").doc(userId)
        .collection("tasks").doc(dateStr)
        .collection("items")
        .add(taskData);

      await admin.firestore()
        .collection("todos").doc(userId)
        .collection("tasks").doc(dateStr)
        .set({taskOrder: admin.firestore.FieldValue.arrayUnion(taskRef.id)}, {merge: true});

      taskIds.push(taskRef.id);
    }

    await admin.firestore()
      .collection("todos").doc(userId)
      .collection("goals").doc(goalId)
      .collection("generations")
      .add({
        generatedAt: Date.now(),
        weekStart,
        weekEnd,
        taskIds,
        prompt,
        response: JSON.stringify(tasks),
        completedTaskIds: [],
        skippedTaskIds: [],
      });

    logger.info(`Generated ${taskIds.length} tasks for goal ${goalId} (user ${userId})`);

    try {
      const fcmToken = await getUserFcmToken(userId);
      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "New Goal Tasks Created",
            body: `${taskIds.length} new task${taskIds.length > 1 ? "s" : ""} for "${goalData.title}" have been added for the week of ${weekStart}`,
          },
          data: {type: "goal_tasks_generated"},
        });
        await recordNotification(userId, {
          title: "New Goal Tasks Created",
          body: `${taskIds.length} new task${taskIds.length > 1 ? "s" : ""} for "${goalData.title}" have been added for the week of ${weekStart}`,
          type: "goal_tasks_generated",
        });
      }
    } catch (notifyErr) {
      logger.warn(`Failed to send goal task notification for ${goalId} (user ${userId}):`, notifyErr);
    }
  } catch (e) {
    logger.error(`Error generating tasks for goal ${goalId} (user ${userId}):`, e);
  }
}

// ---------- Google Calendar integration ----------

function buildOAuthClient(clientId: string, clientSecret: string) {
  return new google.auth.OAuth2(clientId, clientSecret, "");
}

export const exchangeCalendarAuthCode = onCall(
  {secrets: [oauthClientSecret, oauthWebClientId]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const code = request.data?.code as string | undefined;
    if (!code) {
      throw new HttpsError("invalid-argument", "Missing auth code");
    }

    const clientId = oauthWebClientId.value();
    const clientSecret = oauthClientSecret.value();
    const oauth = buildOAuthClient(clientId, clientSecret);

    let refreshToken: string | undefined;
    try {
      const {tokens} = await oauth.getToken(code);
      refreshToken = tokens.refresh_token ?? undefined;
    } catch (e: any) {
      logger.error(`Token exchange failed for ${uid}:`, e?.response?.data || e);
      throw new HttpsError("internal", `Token exchange failed: ${e?.message || e}`);
    }

    if (!refreshToken) {
      throw new HttpsError(
        "failed-precondition",
        "Google did not return a refresh token. Disconnect from Google account permissions and try again."
      );
    }

    await admin.firestore().collection("secrets").doc(uid).set({
      calendarRefreshToken: refreshToken,
    }, {merge: true});

    await admin.firestore().collection("todos").doc(uid).set({
      calendarConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {ok: true};
  }
);

export const disconnectCalendar = onCall(
  {secrets: [oauthClientSecret, oauthWebClientId]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;

    const secretRef = admin.firestore().collection("secrets").doc(uid);
    const secretSnap = await secretRef.get();
    const refreshToken = secretSnap.data()?.calendarRefreshToken as string | undefined;

    if (refreshToken) {
      try {
        const oauth = buildOAuthClient(oauthWebClientId.value(), oauthClientSecret.value());
        await oauth.revokeToken(refreshToken);
      } catch (e: any) {
        logger.warn(`Revoke failed for ${uid} (continuing):`, e?.message || e);
      }
    }

    await secretRef.set({calendarRefreshToken: admin.firestore.FieldValue.delete()}, {merge: true});
    await admin.firestore().collection("todos").doc(uid).set({
      calendarConnectedAt: admin.firestore.FieldValue.delete(),
      calendarSyncToken: admin.firestore.FieldValue.delete(),
    }, {merge: true});

    return {ok: true};
  }
);

function eventStartDate(event: any): string | null {
  if (event.start?.date) return event.start.date;
  if (event.start?.dateTime) {
    const d = new Date(event.start.dateTime);
    if (isNaN(d.getTime())) return null;
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, "0");
    const day = d.getDate().toString().padStart(2, "0");
    return `${y}-${m}-${day}`;
  }
  return null;
}

async function findTaskByEventId(uid: string, eventId: string) {
  const today = new Date();
  const ranges: string[] = [];
  for (let i = -60; i <= 60; i++) {
    const d = new Date(today);
    d.setDate(d.getDate() + i);
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, "0");
    const day = d.getDate().toString().padStart(2, "0");
    ranges.push(`${y}-${m}-${day}`);
  }

  for (const date of ranges) {
    const q = await admin.firestore()
      .collection("todos").doc(uid)
      .collection("tasks").doc(date)
      .collection("items")
      .where("calendarEventId", "==", eventId)
      .limit(1)
      .get();
    if (!q.empty) {
      return q.docs[0].ref;
    }
  }
  return null;
}

async function processCalendarForUser(uid: string, clientId: string, clientSecret: string) {
  const secretSnap = await admin.firestore().collection("secrets").doc(uid).get();
  const refreshToken = secretSnap.data()?.calendarRefreshToken as string | undefined;
  if (!refreshToken) {
    logger.info(`User ${uid} has no refresh token; skipping`);
    return;
  }

  const userRef = admin.firestore().collection("todos").doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};
  const syncToken = userData.calendarSyncToken as string | undefined;

  const oauth = buildOAuthClient(clientId, clientSecret);
  oauth.setCredentials({refresh_token: refreshToken});
  const calendar = google.calendar({version: "v3", auth: oauth});

  let pageToken: string | undefined;
  let nextSyncToken: string | undefined;
  let imported = 0;
  let updated = 0;
  let cancelled = 0;

  try {
    do {
      const listParams: any = {
        calendarId: "primary",
        singleEvents: true,
        pageToken,
      };
      if (syncToken && !pageToken) {
        listParams.syncToken = syncToken;
      } else if (!pageToken) {
        const now = new Date();
        const end = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
        listParams.timeMin = now.toISOString();
        listParams.timeMax = end.toISOString();
      }

      const res = await calendar.events.list(listParams);
      const events = res.data.items || [];

      for (const event of events) {
        const eventId = event.id;
        if (!eventId) continue;

        if (event.status === "cancelled") {
          const ref = await findTaskByEventId(uid, eventId);
          if (ref) {
            const parentDate = ref.parent.parent;
            await ref.delete();
            if (parentDate) {
              await parentDate.set({
                taskOrder: admin.firestore.FieldValue.arrayRemove(ref.id),
              }, {merge: true});
            }
            cancelled++;
            logger.info(`[calendar-import] CANCELLED "${event.summary ?? "(no title)"}" eventId=${eventId} taskId=${ref.id}`);
          }
          continue;
        }

        const taskrId = event.extendedProperties?.private?.taskrId;
        if (taskrId) {
          logger.info(`[calendar-import] SKIPPED (taskr-owned) "${event.summary ?? "(no title)"}" eventId=${eventId} taskrId=${taskrId}`);
          continue;
        }

        const date = eventStartDate(event);
        if (!date) continue;

        const existing = await findTaskByEventId(uid, eventId);
        const taskFields: any = {
          title: event.summary || "Untitled",
          description: event.description || null,
          dueDate: date,
          priority: "info",
          completed: false,
          type: "task",
          calendarEventId: eventId,
          tags: [],
          modified: new Date().toISOString(),
        };

        if (existing) {
          await existing.update(taskFields);
          updated++;
          logger.info(`[calendar-import] UPDATED "${event.summary ?? "(no title)"}" date=${date} eventId=${eventId} taskId=${existing.id}`);
        } else {
          taskFields.added = Date.now();
          taskFields.subtasks = [];
          taskFields.pushCount = 0;
          const dateRef = admin.firestore()
            .collection("todos").doc(uid)
            .collection("tasks").doc(date);
          const newRef = await dateRef.collection("items").add(taskFields);
          await dateRef.set({
            taskOrder: admin.firestore.FieldValue.arrayUnion(newRef.id),
          }, {merge: true});
          imported++;
          logger.info(`[calendar-import] IMPORTED "${event.summary ?? "(no title)"}" date=${date} eventId=${eventId} taskId=${newRef.id}`);
        }
      }

      pageToken = res.data.nextPageToken || undefined;
      if (!pageToken && res.data.nextSyncToken) {
        nextSyncToken = res.data.nextSyncToken;
      }
    } while (pageToken);

    if (nextSyncToken) {
      await userRef.set({calendarSyncToken: nextSyncToken}, {merge: true});
    }

    logger.info(`Calendar sync for ${uid}: imported=${imported} updated=${updated} cancelled=${cancelled}`);
  } catch (e: any) {
    const code = e?.code;
    const message = e?.message || String(e);

    if (code === 410) {
      logger.warn(`Sync token expired for ${uid}; clearing and reseeding next run`);
      await userRef.set({calendarSyncToken: admin.firestore.FieldValue.delete()}, {merge: true});
      return;
    }
    if (message.includes("invalid_grant")) {
      logger.warn(`invalid_grant for ${uid}; clearing connection state`);
      await admin.firestore().collection("secrets").doc(uid).set({
        calendarRefreshToken: admin.firestore.FieldValue.delete(),
      }, {merge: true});
      await userRef.set({
        calendarConnectedAt: admin.firestore.FieldValue.delete(),
        calendarSyncToken: admin.firestore.FieldValue.delete(),
      }, {merge: true});
      return;
    }
    logger.error(`Calendar sync failed for ${uid}:`, e);
  }
}

export const importCalendarEvents = onSchedule(
  {schedule: "every 1 hours from 08:00 to 23:00", secrets: [oauthClientSecret, oauthWebClientId]},
  async () => {
    const clientId = oauthWebClientId.value();
    const clientSecret = oauthClientSecret.value();
    const todos = await admin.firestore().collection("todos").get();
    const candidates = todos.docs.filter((d) => d.data()?.calendarConnectedAt);
    logger.info(`importCalendarEvents: processing ${candidates.length} users`);

    for (const doc of candidates) {
      try {
        await processCalendarForUser(doc.id, clientId, clientSecret);
      } catch (e) {
        logger.error(`Unexpected error for ${doc.id}:`, e);
      }
    }
  }
);

export const importCalendarEventsTest = onRequest(
  {secrets: [oauthClientSecret, oauthWebClientId]},
  async (_req, res) => {
    try {
      const clientId = oauthWebClientId.value();
      const clientSecret = oauthClientSecret.value();
      const todos = await admin.firestore().collection("todos").get();
      const candidates = todos.docs.filter((d) => d.data()?.calendarConnectedAt);
      for (const doc of candidates) {
        await processCalendarForUser(doc.id, clientId, clientSecret);
      }
      res.status(200).send({processed: candidates.length});
    } catch (e: any) {
      res.status(500).send({error: e?.message || String(e)});
    }
  }
);

// --- Task Reminder Functions ---

const CLOUD_TASKS_QUEUE = "task-reminders";
const CLOUD_TASKS_LOCATION = "us-central1";
const CLOUD_TASKS_PROJECT = "taskr-1428";

const tasksClient = new CloudTasksClient();

export const scheduleReminder = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be logged in");

  const {taskId, taskDate, reminderTime, title} = request.data;
  if (!taskId || !taskDate || !reminderTime || !title) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }

  const scheduledDate = new Date(reminderTime);
  if (isNaN(scheduledDate.getTime())) {
    throw new HttpsError("invalid-argument", "Invalid reminderTime");
  }

  const queuePath = tasksClient.queuePath(
    CLOUD_TASKS_PROJECT,
    CLOUD_TASKS_LOCATION,
    CLOUD_TASKS_QUEUE
  );

  const deliverUrl = `https://${CLOUD_TASKS_LOCATION}-${CLOUD_TASKS_PROJECT}.cloudfunctions.net/deliverReminder`;

  const payload = JSON.stringify({uid, taskId, taskDate, title});
  const scheduleTimestamp = Math.floor(scheduledDate.getTime() / 1000);

  // A deterministic name makes this idempotent, the same way scheduleParkingPrompt
  // is: two devices running the recurring top-up before either has written
  // reminderTaskName back would otherwise enqueue two Cloud Tasks, and the user
  // would get the same reminder twice. Both compute the same instant, so both
  // land on the same name and the second collides harmlessly.
  //
  // The instant is part of the name deliberately. Cloud Tasks will not reuse a
  // task name for a period after that task is deleted or executed, so keying on
  // the task id alone would make rescheduling the SAME task at a new time (the
  // cancel-then-schedule in ReminderService.updateReminder) silently no-op.
  const deterministicName =
    `${queuePath}/tasks/reminder-${uid}-${taskId}-${scheduleTimestamp}`;

  let taskName = deterministicName;
  try {
    const [task] = await tasksClient.createTask({
      parent: queuePath,
      task: {
        name: deterministicName,
        httpRequest: {
          httpMethod: "POST",
          url: deliverUrl,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(payload).toString("base64"),
        },
        scheduleTime: {seconds: scheduleTimestamp},
      },
    });
    taskName = task.name!;
  } catch (e: any) {
    // 6 = ALREADY_EXISTS. Someone else scheduled this same reminder; the
    // deterministic name is the one they used, so hand it back and move on.
    if (e.code === 6) {
      logger.info(`Reminder already scheduled for task ${taskId}`);
    } else {
      throw e;
    }
  }
  logger.info(`Scheduled reminder for task ${taskId} at ${reminderTime}: ${taskName}`);

  return {reminderTaskName: taskName};
});

// --- Parking Prompt Functions ---

/**
 * Enqueues the "pay for parking?" prompt for the user's Work Train departure.
 *
 * Delivery uses a Cloud Task with an explicit schedule time rather than a cron,
 * because the prompt has to land at the task's own startTime, which varies daily.
 */
async function scheduleParkingPrompt(userId: string) {
  // Commute-local, not UTC: the task partitions are keyed by local date.
  const date = localDateIn(COMMUTE_TIMEZONE);

  try {
    const doc = await findWorkTrainTask(userId, date);
    if (!doc) {
      logger.info(`No 'work train' todos found on ${date}; no parking prompt.`);
      return {error: `No 'work train' todos found on ${date}.`};
    }

    const todo = doc.data();
    if (!todo.startTime) {
      logger.info(`Document ${doc.id} has no start time; no parking prompt.`);
      return {error: `Document ${doc.id} did not have a start time`};
    }

    const scheduleSeconds = localTimeToEpochSeconds(
      date, todo.startTime, COMMUTE_TIMEZONE
    );

    const queuePath = tasksClient.queuePath(
      CLOUD_TASKS_PROJECT,
      CLOUD_TASKS_LOCATION,
      CLOUD_TASKS_QUEUE
    );

    const deliverUrl = `https://${CLOUD_TASKS_LOCATION}-${CLOUD_TASKS_PROJECT}.cloudfunctions.net/deliverParkingPrompt`;
    const payload = JSON.stringify({uid: userId, taskId: doc.id, taskDate: date});

    // A deterministic name is what makes this idempotent: a second scheduling
    // run on the same day collides here instead of enqueuing a second prompt.
    // Two prompts would mean two chances to tap Yes.
    const taskName = `${queuePath}/tasks/parking-${userId}-${date.replace(/-/g, "")}`;

    try {
      await tasksClient.createTask({
        parent: queuePath,
        task: {
          name: taskName,
          httpRequest: {
            httpMethod: "POST",
            url: deliverUrl,
            headers: {"Content-Type": "application/json"},
            body: Buffer.from(payload).toString("base64"),
          },
          // A startTime earlier than this run is not an error — Cloud Tasks
          // dispatches a past schedule time promptly rather than rejecting it.
          scheduleTime: {seconds: scheduleSeconds},
        },
      });
    } catch (e: any) {
      // 6 = ALREADY_EXISTS. The prompt is already scheduled; nothing to do.
      if (e.code === 6) {
        logger.info(`Parking prompt already scheduled for ${userId} on ${date}`);
        return {skipped: "already scheduled"};
      }
      throw e;
    }

    logger.info(
      `Scheduled parking prompt for ${userId} at ${todo.startTime} ${COMMUTE_TIMEZONE}`
    );
    return {scheduled: scheduleSeconds, taskId: doc.id};
  } catch (e) {
    logger.error("Error scheduling parking prompt", e);
    return {error: String(e)};
  }
}

export const cancelReminder = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be logged in");

  const {reminderTaskName} = request.data;
  if (!reminderTaskName) {
    throw new HttpsError("invalid-argument", "Missing reminderTaskName");
  }

  try {
    await tasksClient.deleteTask({name: reminderTaskName});
    logger.info(`Cancelled reminder: ${reminderTaskName}`);
  } catch (e: any) {
    if (e.code === 5) {
      logger.info(`Reminder already executed or not found: ${reminderTaskName}`);
    } else {
      throw e;
    }
  }

  return {success: true};
});

export const deliverReminder = onRequest(async (req, res) => {
  try {
    const {uid, taskId, taskDate, title} = req.body;
    if (!uid || !taskId || !taskDate || !title) {
      res.status(400).send("Missing required fields");
      return;
    }

    const taskDoc = await admin.firestore()
      .collection("todos").doc(uid)
      .collection("tasks").doc(taskDate)
      .collection("items").doc(taskId)
      .get();

    if (!taskDoc.exists) {
      logger.info(`Task ${taskId} no longer exists; skipping reminder`);
      res.status(200).send("Task deleted; skipped");
      return;
    }

    const fcmToken = await getUserFcmToken(uid);
    if (!fcmToken) {
      logger.warn(`No FCM token for user ${uid}`);
      res.status(200).send("No FCM token");
      return;
    }

    const message: Message = {
      token: fcmToken,
      notification: {
        title: "Reminder",
        body: title,
      },
      android: {
        // Time-sensitive: high priority survives Doze/idle when the app is
        // closed; channelId routes to the high-importance channel the app
        // creates at runtime (otherwise Android falls back to a low-importance
        // channel with no sound/heads-up).
        priority: "high",
        notification: {
          channelId: "fcm_default_channel",
        },
      },
      data: {
        type: "task_reminder",
        taskId,
        taskDate,
        title,
      },
    };

    try {
      await admin.messaging().send(message);
    } catch (err) {
      // A rotated/uninstalled token can never receive again. Clear it and stop
      // retrying (return 200) instead of letting Cloud Tasks retry a dead send.
      if ((err as {code?: string})?.code ===
          "messaging/registration-token-not-registered") {
        logger.warn(`Dead FCM token for user ${uid}; clearing`);
        await admin.firestore().collection("todos").doc(uid)
          .update({fcmToken: admin.firestore.FieldValue.delete()});
        res.status(200).send("Dead token cleared");
        return;
      }
      throw err;
    }
    await recordNotification(uid, {
      title: "Reminder",
      body: title,
      data: {type: "task_reminder", taskId, taskDate, title},
      type: "task_reminder",
    });
    logger.info(`Reminder delivered for task ${taskId} to user ${uid}`);
    res.status(200).send("Reminder sent");
  } catch (e) {
    logger.error("Error delivering reminder:", e);
    res.status(500).send("Error delivering reminder");
  }
});

export const deliverParkingPrompt = onRequest(async (req, res) => {
  try {
    const {uid, taskId, taskDate} = req.body;
    if (!uid || !taskId || !taskDate) {
      res.status(400).send("Missing required fields");
      return;
    }

    // Re-check state that may have changed between scheduling this morning and
    // delivering it now.
    const taskDoc = await admin.firestore()
      .collection("todos").doc(uid)
      .collection("tasks").doc(taskDate)
      .collection("items").doc(taskId)
      .get();
    const userDoc = await admin.firestore().collection("todos").doc(uid).get();
    const fcmToken = taskDoc.exists ? await getUserFcmToken(uid) : null;

    const decision = parkingPromptDecision({
      taskExists: taskDoc.exists,
      parkingAlert: userDoc.data()?.parkingAlert,
      fcmToken,
    });

    if (!decision.send) {
      logger.info(`Parking prompt for ${uid}: ${decision.reason}`);
      res.status(200).send(decision.reason);
      return;
    }

    const title = "Pay for parking?";
    const body = "Your train is leaving. Want to pay for parking?";

    // The client draws this notification itself, because FCM cannot render
    // action buttons. Title and body ride in `data` so they are still available
    // to the client and to the notification centre record.
    const data = {
      type: "parking_prompt",
      taskId,
      taskDate,
      title,
      body,
      actions: JSON.stringify([
        {action: "pay-parking", title: "Yes"},
        {action: "dismiss-parking", title: "No"},
      ]),
    };

    // Data-only, deliberately: a message carrying a `notification` block is
    // auto-displayed by the Android FCM SDK whenever the app is not in the
    // foreground. That system-drawn copy has no action buttons and merely opens
    // the app, and it arrives *alongside* the one the client draws — two
    // notifications from one push, the useless one first.
    const message: Message = {
      // Non-null: decision.send is only true when a token is present.
      token: fcmToken!,
      android: {
        // High priority so it survives Doze — this lands at departure time and
        // is useless if it is held until the phone is next unlocked.
        priority: "high",
      },
      data,
    };

    try {
      await admin.messaging().send(message);
    } catch (err) {
      // A rotated/uninstalled token can never receive again. Clear it and stop
      // retrying (return 200) instead of letting Cloud Tasks retry a dead send.
      if ((err as {code?: string})?.code ===
          "messaging/registration-token-not-registered") {
        logger.warn(`Dead FCM token for user ${uid}; clearing`);
        await admin.firestore().collection("todos").doc(uid)
          .update({fcmToken: admin.firestore.FieldValue.delete()});
        res.status(200).send("Dead token cleared");
        return;
      }
      throw err;
    }

    await recordNotification(uid, {
      title,
      body,
      data,
      type: "parking_prompt",
    });
    logger.info(`Parking prompt delivered to user ${uid}`);
    res.status(200).send("Parking prompt sent");
  } catch (e) {
    logger.error("Error delivering parking prompt:", e);
    res.status(500).send("Error delivering parking prompt");
  }
});

