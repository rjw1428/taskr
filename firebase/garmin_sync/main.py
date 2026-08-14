"""Firebase Functions entrypoint: nightly Garmin health sync.

Deployed as its own codebase ("garmin") so the main Node functions in
firebase/functions are unaffected. See README.md for setup and deploy.
"""

import os

from firebase_admin import initialize_app
from firebase_functions import scheduler_fn
from firebase_functions.options import MemoryOption
from firebase_functions.params import SecretParam

from sync import run_sync, notify_failure

initialize_app()

GARMINTOKENS = SecretParam("GARMINTOKENS")


@scheduler_fn.on_schedule(
    schedule="0 9 * * *",
    timezone=scheduler_fn.Timezone("America/New_York"),
    region="us-central1",
    memory=MemoryOption.MB_512,
    timeout_sec=540,
    secrets=[GARMINTOKENS],
)
def garminsync(event: scheduler_fn.ScheduledEvent) -> None:
    try:
        run_sync(int(os.environ.get("SYNC_DAYS", "7")))
    except Exception as e:  # noqa: BLE001 - alert then re-raise so Cloud marks it failed
        notify_failure(f"{type(e).__name__}: {e}"[:180])
        raise
