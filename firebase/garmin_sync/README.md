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

## Token storage

Garmin **rotates the refresh token on every refresh**, and the access token only
lasts about a day. A blob kept solely in the `GARMINTOKENS` secret is therefore
spent the first time it is used: the function refreshes, gets a new refresh
token, and loses it when the instance dies, so every later run presents a
consumed token and fails with `API Error 401`.

So the live tokens are kept in Firestore at `secrets/garmin` and rewritten after
every login. `GARMINTOKENS` is only the seed, read when that document does not
exist yet. The doc is unreadable from the app — `/secrets/**` is denied to all
clients in `firestore.rules`, and the function reaches it through the admin SDK.

Note that any local run also rotates the token and updates the same document.
That is fine, and is why local runs no longer invalidate the deployed function.

## When login stops working

The refresh token is long-lived but not immortal, and a Garmin password change
invalidates it. `notify_failure` sends an FCM alert on any failed run, so this
surfaces the next morning. To recover:

```sh
venv/bin/python login.py
firebase functions:secrets:set GARMINTOKENS --data-file garmin_tokens.txt
```

then delete the `secrets/garmin` document so the seed is picked up again, and
redeploy. Leaving the stale document in place means the seed is ignored.
