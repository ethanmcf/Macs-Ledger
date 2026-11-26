# Mac's Ledger

A simple iPhone app for tracking what you spend.

- **Quick entry** – log an expense in a couple of taps. You can open it from Siri, the Shortcuts app, or the Action Button ("Add an expense in Mac's Ledger").
- **Dashboard** – see this month's spending, broken down by category.
- **Monthly view** – look back at any month's totals.
- **Transactions** – browse, edit, or delete past expenses.
- **Categories** – add, rename, reorder, or hide your own categories.
- **CSV import** – bring in past monthly totals from a spreadsheet.

Your data stays on your phone. 

## Install the app on your iPhone

The script `scripts/install-on-phone.sh` builds the app and installs it on your phone over Wi-Fi.

With a free Apple ID, the app stops opening after **7 days**. Run the script again before then to reset the clock. Your data is kept.

### One-time setup

1. **Sign in to Xcode.** Open Xcode → Settings → Accounts and add your Apple ID.
2. **Pair your phone.** Plug the iPhone into your Mac with a cable. In Xcode, open Window → Devices and Simulators, select the phone, and tick **Connect via network**. You can unplug it afterwards.
3. **Save your phone's ID.**
   ```sh
   cp .env.example .env
   xcrun devicectl list devices
   ```
   Copy your phone's identifier from the list into `.env`:
   ```
   IPHONE_UDID=your-phone-identifier
   ```

### Install or refresh the app

Make sure your phone is unlocked and on the same Wi-Fi as your Mac, then run:

```sh
./scripts/install-on-phone.sh
```

