# Uptime Kuma

Ring your iPhone when a monitor goes down. Uptime Kuma's webhook notification supports a custom body and additional headers, so it can call the API directly.

## 1. Add a notification

Settings, Notifications, Setup Notification. Choose **Webhook** as the notification type and fill in:

| Setting | Value |
| --- | --- |
| Friendly Name | `Alarmify` |
| Post URL | `https://api.alarmify.app/v1/alarms` |
| Request Body | **Custom Body** |

Custom Body:

```
{
  "fire_in": 0,
  "title": "{{ monitorJSON['name'] }} is down"
}
```

Additional Headers:

```json
{
  "Authorization": "Bearer <API_TOKEN>",
  "Content-Type": "application/json"
}
```

`{{ monitorJSON['name'] }}` is the monitor name. `{{ msg }}` holds Uptime Kuma's own message if you prefer the full text (the API truncates titles to 100 characters).

## 2. Attach it to monitors

Enable the notification on the monitors that should wake you, or turn on **Default enabled** and **Apply on all existing monitors** on the notification.

## 3. Test

Press **Test** on the notification. Your iPhone should ring within a few seconds.

## Ring only on DOWN

Uptime Kuma sends the same webhook for DOWN and UP. To ring only when a monitor goes down, use `{{ heartbeatJSON['status'] }}` in the title (0 is DOWN, 1 is UP) so you can tell them apart, or route the webhook through a small relay that drops the UP events. A dedicated field for status-based filtering is not part of the API.

Reference: [API reference](../api.md)
