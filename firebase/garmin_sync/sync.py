"""Sync Garmin Connect health data into Firestore.

Pulls per-day sleep, body battery, stress, and activity metrics via the
garminconnect library and writes them to todos/{uid}/health/{yyyy-MM-dd},
matching the journal collection layout so the app can key both off the
selected date.

Environment:
    GARMINTOKENS      token blob from login.py (required; read natively by
                      the garminconnect library)
    TASKR_EMAIL       Firebase Auth email of the taskr user to write under
                      (required unless TASKR_UID is set)
    TASKR_UID         Firebase Auth uid, overrides TASKR_EMAIL lookup
    SYNC_DAYS         how many days back to sync (default 7; use 90 for backfill)
    GOOGLE_APPLICATION_CREDENTIALS  service-account key path for local runs
                      (Cloud Run uses its runtime service account automatically)

Usage:
    python sync.py            # sync last SYNC_DAYS days
    python sync.py --days 90  # explicit backfill
"""

import argparse
import os
import sys
from datetime import date, timedelta

import firebase_admin
from firebase_admin import auth, firestore
from garminconnect import Garmin


def resolve_uid() -> str:
    uid = os.environ.get("TASKR_UID")
    if uid:
        return uid
    email = os.environ.get("TASKR_EMAIL")
    if not email:
        sys.exit("Set TASKR_EMAIL or TASKR_UID")
    return auth.get_user_by_email(email).uid


def fetch_day(garmin: Garmin, day: date) -> dict | None:
    """Return the health doc for one day, or None if Garmin has no data."""
    day_str = day.isoformat()
    doc = {"date": day_str}

    try:
        summary = garmin.get_user_summary(day_str)
    except Exception:
        summary = None
    if summary:
        doc.update(
            steps=summary.get("totalSteps"),
            floorsClimbed=summary.get("floorsAscended"),
            activeCalories=summary.get("activeKilocalories"),
            restingHeartRate=summary.get("restingHeartRate"),
            stressAvg=summary.get("averageStressLevel"),
            stressMax=summary.get("maxStressLevel"),
            bodyBatteryHigh=summary.get("bodyBatteryHighestValue"),
            bodyBatteryLow=summary.get("bodyBatteryLowestValue"),
            bodyBatteryCharged=summary.get("bodyBatteryChargedValue"),
            bodyBatteryDrained=summary.get("bodyBatteryDrainedValue"),
        )

    sleep = garmin.get_sleep_data(day_str)
    dto = (sleep or {}).get("dailySleepDTO") or {}
    if dto.get("sleepTimeSeconds"):
        scores = dto.get("sleepScores") or {}
        doc.update(
            sleepSeconds=dto.get("sleepTimeSeconds"),
            deepSeconds=dto.get("deepSleepSeconds"),
            lightSeconds=dto.get("lightSleepSeconds"),
            remSeconds=dto.get("remSleepSeconds"),
            awakeSeconds=dto.get("awakeSleepSeconds"),
            sleepScore=(scores.get("overall") or {}).get("value"),
        )

    # Garmin reports stress/body battery as -1 or -2 on days without enough data
    doc = {k: v for k, v in doc.items() if v is not None and not (isinstance(v, int) and v < 0)}
    # Only keep days where something was actually recorded
    if "sleepSeconds" not in doc and not doc.get("steps") and "stressAvg" not in doc:
        return None
    return doc


def notify_failure(summary: str) -> None:
    """Best-effort FCM alert to the taskr user when a sync run fails.

    Scheduled-function failures surface nowhere the user would notice, which is
    how a dead token went unseen for weeks. This pushes a high-priority
    notification so a broken sync is caught the next morning, not the next month.
    Never raises: alerting must not mask or replace the original error.
    """
    try:
        from firebase_admin import messaging

        db = firestore.client()
        uid = resolve_uid()
        token = (db.collection("todos").document(uid).get().to_dict() or {}).get("fcmToken")
        if not token:
            print("notify_failure: no fcmToken on user; skipping alert", flush=True)
            return
        messaging.send(messaging.Message(
            token=token,
            notification=messaging.Notification(
                title="Garmin sync failed",
                body=summary,
            ),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(channel_id="fcm_default_channel"),
            ),
            data={"type": "garmin_sync_error"},
        ))
        print("notify_failure: alert sent", flush=True)
    except Exception as e:  # noqa: BLE001 - alerting is best-effort
        print(f"notify_failure: could not send alert: {e}", flush=True)


def run_sync(days: int) -> None:
    """Sync the last `days` days. Assumes firebase_admin is initialized and
    GARMINTOKENS is set in the environment."""
    garmin = Garmin()
    garmin.login()  # reads GARMINTOKENS

    db = firestore.client()
    uid = resolve_uid()
    collection = db.collection("todos").document(uid).collection("health")

    today = date.today()
    synced = skipped = 0
    for offset in range(days):
        day = today - timedelta(days=offset)
        try:
            doc = fetch_day(garmin, day)
        except Exception as e:  # keep going: one bad day shouldn't kill the run
            print(f"{day}: FAILED {e}", flush=True)
            continue
        if doc is None:
            skipped += 1
            continue
        doc["updatedAt"] = firestore.SERVER_TIMESTAMP
        collection.document(doc["date"]).set(doc, merge=True)
        synced += 1
        print(f"{day}: ok", flush=True)

    print(f"Done. {synced} days written, {skipped} empty days skipped.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=int(os.environ.get("SYNC_DAYS", 7)))
    args = parser.parse_args()

    if not os.environ.get("GARMINTOKENS"):
        sys.exit("Set GARMINTOKENS (run login.py to generate the token blob)")
    firebase_admin.initialize_app()
    run_sync(args.days)


if __name__ == "__main__":
    main()
