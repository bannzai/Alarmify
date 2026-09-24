# How to Delete Your Account and Data

These are the steps to delete your Signalarm account (provider: bannzai) and the data stored on the Provider's servers.

## Deleting from Within the App

1. Open Signalarm and open "Settings"
2. Select "Delete Account"
3. Confirm and execute the deletion on the confirmation screen
4. If Sign in with Apple is linked, you are asked to authenticate with Sign in with Apple before deletion. After you authenticate, the Apple token is revoked and then the account is deleted. If you close the authentication sheet, or if revoking the token fails, the account is not deleted<!-- source: Alarmify/Account/AccountSession.swift: deleteAccount() runs revokeAppleToken() (a fresh Sign in with Apple to obtain an authorization code, then Auth.auth().revokeToken(withAuthorizationCode:)) when appleIDLinked before calling apiClient.deleteAccount(), and throws without deleting when revocation fails. Alarmify/Settings/SettingsView.swift: ASAuthorizationError.canceled from the closed sheet is treated as the deletion being abandoned -->

Deletion is performed immediately and cannot be undone.

## Requesting Deletion by Email

If you cannot use the app, send an email to bannzai.app@gmail.com stating that you wish to delete your account, together with the account ID displayed on the settings screen of the app. After confirming that the request is made by you, the Provider will delete your account within 7 days.

## Data That Is Deleted

- Account identifier (the anonymous user ID, or the user ID of the account when Sign in with Apple is linked; a linked Apple token is revoked)
- Issued API Tokens (after deletion, all calls from external services are rejected)
- Device information (device token, device type, OS and app versions)
- History of alarm requests (sender, date and time, title, delivery results)

## Data Retained After Deletion and Retention Periods

- The purchase history of in-app purchases is retained by RevenueCat, Inc. and Apple Inc. in accordance with each company's policy, for payment processing and refund handling. Because the account identifier of the Service is registered with RevenueCat as the purchaser identifier, the purchase history remains with RevenueCat, Inc. linked to the identifier of the deleted account. The paid plan status stored on the Provider's servers is deleted together with the account<!-- source: Alarmify/Features/Purchase/ProEntitlement.swift: Purchases.logIn is called with the Firebase Auth uid, which becomes the RevenueCat App User ID. firebase/functions/src/account/deleteAccount.ts: deleteUserAccount removes users/{uid} (including plan) with recursiveDelete and does not delete the RevenueCat customer -->
- Inquiry emails are retained as a record of the response for one year from receipt, and are then deleted
- Deleted data included in server backups is erased through backup rotation within a maximum of 30 days after deletion
- A record used to confirm that the deletion has completed (the account identifier only; it contains no other data) is normally erased automatically within 3 hours after deletion (if a cleanup run fails, it is retried every hour and the record is erased once a run succeeds)

AlarmKit alarms already registered on your device are not cancelled by account deletion. Cancel them individually from the iPhone "Clock" app or from the alarm list in Signalarm. Uninstalling the app does not delete your account or the data on the servers.
