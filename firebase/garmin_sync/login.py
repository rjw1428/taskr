"""One-time interactive Garmin login.

Prompts for Garmin Connect credentials (and MFA code if enabled), then writes
a token blob good for ~1 year. Store it as the garmin-tokens secret:

    python login.py
    gcloud secrets create garmin-tokens --data-file=garmin_tokens.txt
"""

import getpass

from garminconnect import Garmin


def main():
    email = input("Garmin Connect email: ")
    password = getpass.getpass("Garmin Connect password: ")
    garmin = Garmin(email=email, password=password, prompt_mfa=lambda: input("MFA code: "))
    garmin.login()
    with open("garmin_tokens.txt", "w") as f:
        f.write(garmin.client.dumps())
    print("\nLogin OK. Token written to garmin_tokens.txt (keep this out of git).")
    print(f"Logged in as: {garmin.display_name}")


if __name__ == "__main__":
    main()
