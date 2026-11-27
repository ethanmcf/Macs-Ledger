# Mac's Ledger

A simple iPhone app for tracking what you spend.

- **Quick entry** – log an expense in a couple of taps. You can open it from Siri, the Shortcuts app, or the Action Button ("Add an expense in Mac's Ledger").
- **Dashboard** – see this month's spending, broken down by category.
- **Monthly view** – look back at any month's totals.
- **Transactions** – browse, edit, or delete past expenses.
- **Categories** – add, rename, reorder, or hide your own categories.
- **CSV import** – bring in past monthly totals from a spreadsheet.
- **Google Sheets backup** – every change is copied to a Google Sheet you own, even ones made offline.

Your data stays on your phone, plus a copy in your own Google Sheet if you turn on the backup.

## Install the app on your iPhone

The script `scripts/install-on-phone.sh` builds the app and installs it on your phone over Wi-Fi.

With a free Apple ID, the app stops opening when its signing profile expires, usually **7 days** after it was built. The script reinstalls it with a fresh profile before then. Your data is kept.

### One-time setup

1. **Sign in to Xcode.** Open Xcode → Settings → Accounts and add your Apple ID.
2. **Pair your phone.** Plug the iPhone into your Mac with a cable. In Xcode, open Window → Devices and Simulators, select the phone, and tick **Connect via network**. You can unplug it afterwards.
3. **Save your phone's ID.**
   ```sh
   cp .env.example .env
   xcrun devicectl list devices
   ```
   ```
   IPHONE_UDID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
   ```

### Install or refresh the app

Make sure your phone is unlocked and on the same Wi-Fi as your Mac (or plugged in with a cable), then run:

```sh
./scripts/install-on-phone.sh --force
```

Without `--force`, the script only reinstalls once the app on your phone has **4 days or fewer** left before its profile expires. With a 7-day profile, that's 3 days after each install. It reads the expiry date from the app, but never assumes more than 7 days after a build, even if the profile says longer (a profile can say 1 year if your team once had a paid membership). Before rebuilding, it clears Xcode's cached profile so the new build gets a fresh one.

### Automatic reinstall

Set up a background job that runs the script when you log in to your Mac, and every hour after that:

```sh
./scripts/install-schedule.sh              # turn it on (run again after moving the repo)
./scripts/install-schedule.sh --uninstall  # turn it off
```

Most runs finish instantly ("good until …, nothing to do"). Once the app has 4 days or fewer left, every run tries to reinstall, which gives about 4 days of hourly retries before it expires. You can follow it in the log:

```sh
tail -f ~/Library/Logs/macs-ledger-install.log
```

**Does the phone need to be unlocked?** Not necessarily, but it needs to be reachable. A locked, idle iPhone often stops responding over Wi-Fi, and that run is skipped ("isn't reachable"). Any hour your phone is awake on the same Wi-Fi is enough. **Leaving it charging overnight** on the same Wi-Fi is the most reliable option. The Mac needs to be logged in, and on or asleep (not shut down).

## Back up to a Google Sheet

The app can copy every expense and category to a Google Sheet. If you delete the app or get a new phone, you can restore everything from the sheet. You can also view and edit your data in Google Sheets.

A small script attached to the sheet (`scripts/google-sheet/Code.gs`) receives the changes. You don't need to host a server.

### One-time setup

1. **Make up a token.** It works like a password between the app and the sheet. Generate one in Terminal:
   ```sh
   openssl rand -hex 24
   ```
2. **Create a Google Sheet**, then open **Extensions → Apps Script**. Delete what's there, paste in the contents of `scripts/google-sheet/Code.gs`, and save.
3. **Add the token to the script.** In Apps Script, click the gear (**Project Settings**) → **Script Properties** → **Add script property**. Name: `TOKEN`. Value: your token.
4. **Deploy it.** Click **Deploy → New deployment**, then the gear → **Web app**:
   - Execute as: **Me**
   - Who has access: **Anyone**

   Click **Deploy** and allow access to your sheet. Google warns that the app is unverified, because it's your own script: choose **Advanced → Go to project**. Copy the **Web app URL**. It ends in `/exec`.
5. **Connect the app.** On your phone, tap the gear → **Backup to Google Sheet**. Paste the URL and the token, then tap **Save**.
6. **Tap Back Up Everything.** The sheet gets two tabs, **Transactions** and **Categories**, filled with your data.

Keep the URL and token private. Together they give read and write access to your spending data. The app stores them in the iPhone's Keychain.

### How it works

- **Automatic.** Each change uploads a couple of seconds after you make it. You don't need to tap anything.
- **Offline.** Changes wait on the phone (Settings › Backup shows "Waiting to upload") and upload by themselves when you're back online.
- **Back Up Now** sends anything still waiting. **Back Up Everything** re-sends all your data. Use it the first time, or to repair the sheet.
- **Update from Google Sheet** brings the sheet's data into the app. Use it to restore after a reinstall, or after editing rows in the sheet. When the app and the sheet disagree, the newer change wins.

### Editing in the sheet

- You can edit amounts, dates, notes and categories directly in the sheet, then tap **Update from Google Sheet** in the app.
- You can type in new rows. They get an ID automatically.
- **To delete a row, set its `deleted` column to `TRUE`.** Don't remove the row; a removed row gets uploaded again on the next update.
- If you mark a category deleted while it still has expenses in the app, the app hides it instead. To decide what happens to its expenses, delete it in the app under Settings › Categories.
- Don't rename or reorder the columns. You can add your own columns to the right, or extra tabs.
- Deleted rows stay in the sheet, so leave them out of your own totals, e.g. `=SUMIFS(Transactions!D:D, Transactions!H:H, FALSE)`.

### Changing things later

- **Finding the web app URL again:** in Apps Script, open **Deploy → Manage deployments** and copy it there. Don't create a new deployment, because that gives you a different URL.
- **After editing `Code.gs`:** open **Deploy → Manage deployments**, edit the deployment, and choose **Version: New version**. The URL stays the same.
- **Changing the token:** update it in Script Properties *and* in the app. Until both match, backups fail with "Wrong token".
