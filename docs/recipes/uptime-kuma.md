# Uptime Kuma

Ring your iPhone when a monitor goes down. Uptime Kuma's webhook notification supports a custom body and additional headers, so it can call the API directly.

## 1. Add a notification

Settings, Notifications, Setup Notification. Choose **Webhook** as the notification type and fill in:

| Setting | Value |
| --- | --- |
| Friendly Name | `Alarmify` |
| Post URL | `https://api.alarmify.app/v1/alarms` |
| Request Body | **Custom Body** |

Custom Body (a Liquid template; Uptime Kuma 1.23 or later):

```
{% assign state = "down" %}{% if heartbeatJSON['status'] == 1 %}{% assign state = "up" %}{% endif %}
{
  "fire_in": 0,
  "title": {{ monitorJSON['name'] | append: " is " | append: state | json }}
}
```

Additional Headers:

```json
{
  "Authorization": "Bearer <API_TOKEN>",
  "Content-Type": "application/json"
}
```

`monitorJSON['name']` is the monitor name and `heartbeatJSON['status']` is `0` for DOWN and `1` for UP, so the alarm title reads `Website is down` or `Website is up`. The `json` filter JSON-encodes the title (including the quotes), so a monitor name containing a quote still produces a valid body. `{{ msg | json }}` holds Uptime Kuma's own message if you prefer the full text (the API truncates titles to 100 characters).

## 2. Attach it to monitors

Enable the notification on the monitors that should wake you, or turn on **Default enabled** and **Apply on all existing monitors** on the notification.

## 3. Test

Press **Test** on the notification. Your iPhone should ring about a minute later (the API's minimum lead time).

## UP events also ring

Uptime Kuma sends the same webhook for DOWN and UP and has no per-notification filter, so a recovery also rings, with the title `... is up`. To ring only when a monitor goes down, route the webhook through a small relay (a Cloudflare Worker, or a Home Assistant webhook trigger that calls the [Home Assistant recipe](./home-assistant.md)) that drops events whose `heartbeat.status` is `1`.

Reference: [API reference](../api.md)
