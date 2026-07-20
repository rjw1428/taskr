# Garmin Sync

Scheduled Firebase Function (Python, codebase `garmin` — separate from the
Node functions in `firebase/functions`) that pulls health data (sleep, body
battery, stress, steps, resting HR) from Garmin Connect via
[python-garminconnect](https://github.com/cyberjunky/python-garminconnect)
and writes one Firestore doc per day to `todos/{uid}/health/{yyyy-MM-dd}`.
Runs nightly at 9:00 AM ET.

> Note: garth (the library this was originally planned around) was deprecated
> after Garmin changed their auth flow. python-garminconnect reimplemented the
> mobile SSO flow and is actively maintained — it's the sturdiest unofficial
> option as of mid-2026.

## Setup (one time)

```sh
cd firebase/garmin_sync
uv venv --python 3.13 --seed venv   # CLI needs "venv" matching the python313 runtime
venv/bin/pip install -r requirements.txt

# 1. Interactive Garmin login (handles MFA). Produces garmin_tokens.txt,
#    valid for ~1 year.
venv/bin/python login.py

# 2. Store the token as a Firebase secret
firebase functions:secrets:set GARMINTOKENS --data-file garmin_tokens.txt

# 3. Deploy the scheduled function from the firebase/ directory
cd .. && firebase deploy --only functions:garmin
```

## Backfill history

The deployed function syncs the last `SYNC_DAYS` (7) days each night. For
deeper history, run locally:

```sh
cd firebase/garmin_sync
export GARMINTOKENS=$(cat garmin_tokens.txt)
export TASKR_EMAIL=rjw1428@gmail.com
export GOOGLE_APPLICATION_CREDENTIALS=../../service-account-key.json
venv/bin/python sync.py --days 90
```

To test against the emulator instead of prod, also set
`FIRESTORE_EMULATOR_HOST=localhost:8080`.

## Emulator note

The docker emulator image (node:20-alpine) has no Python, so the functions
emulator logs an error while loading the `garmin` codebase and skips it; the
Node functions still emulate fine. Scheduled functions don't fire in the
emulator anyway — test the sync with the local run above.

## When the token expires (~1 year)

Re-run `venv/bin/python login.py`, then
`firebase functions:secrets:set GARMINTOKENS --data-file garmin_tokens.txt`
and redeploy.
