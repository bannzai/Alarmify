# How to Delete Your Account and Data

These are the steps to delete your Signalarm account (provider: bannzai) and the data stored on the Provider's servers.

## Deleting from Within the App

1. Open Signalarm and open "Settings"
2. Select "Delete Account"
3. Confirm and execute the deletion on the confirmation screen

Deletion is performed immediately and cannot be undone.

## Requesting Deletion by Email

If you cannot use the app, send an email to bannzai.app@gmail.com stating that you wish to delete your account, together with the account ID displayed on the settings screen of the app. After confirming that the request is made by you, the Provider will delete your account within 7 days.

## Data That Is Deleted

- Account identifier (anonymous user ID)
- Issued API Tokens (after deletion, all calls from external services are rejected)
- Device information (device token, device type, OS and app versions)
- History of alarm requests (sender, date and time, title, delivery results)

## Data Retained After Deletion and Retention Periods

- The purchase history of in-app purchases is retained by RevenueCat, Inc. and Apple Inc. in accordance with each company's policy, for payment processing and refund handling. The purchase information held by the Provider is linked only to anonymous identifiers, and the linkage is removed when the account is deleted
- Inquiry emails are retained as a record of the response for one year from receipt, and are then deleted
- Deleted data included in server backups is erased through backup rotation within a maximum of 30 days after deletion
- A record used to confirm that the deletion has completed (the account identifier only; it contains no other data) is normally erased automatically within 3 hours after deletion (if a cleanup run fails, it is retried every hour and the record is erased once a run succeeds)

AlarmKit alarms already registered on your device are not cancelled by account deletion. Cancel them individually from the iPhone "Clock" app or from the alarm list in Signalarm. Uninstalling the app does not delete your account or the data on the servers.
