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

{% raw %}
```liquid
{% case heartbeatJSON['status'] %}{% when 0 %}{% assign state = "down" %}{% when 1 %}{% assign state = "up" %}{% when 2 %}{% assign state = "pending" %}{% else %}{% assign state = "in maintenance" %}{% endcase %}
{
  "fire_in": 0,
  "title": {{ monitorJSON['name'] | append: " is " | append: state | json }}
}
```
{% endraw %}

Additional Headers:

```json
{
  "Authorization": "Bearer <API_TOKEN>",
  "Content-Type": "application/json"
}
```

{% raw %}`monitorJSON['name']` is the monitor name and `heartbeatJSON['status']` is `0` for DOWN, `1` for UP, `2` for PENDING and `3` for MAINTENANCE, so the alarm title reads `Website is down`, `Website is up`, `Website is pending` or `Website is in maintenance`. The `json` filter JSON-encodes the title (including the quotes), so a monitor name containing a quote still produces a valid body. `{{ msg | json }}` holds Uptime Kuma's own message if you prefer the full text (the API rejects titles longer than 200 characters).{% endraw %}

## 2. Attach it to monitors

Enable the notification on the monitors that should wake you, or turn on **Default enabled** and **Apply on all existing monitors** on the notification.

## 3. Test

Press **Test** on the notification. Your iPhone should ring within a minute (the API's minimum lead time is 30 seconds).

## UP events also ring

Uptime Kuma sends the same webhook for DOWN and UP and has no per-notification filter, so a recovery also rings, with the title `... is up`. To ring only when a monitor goes down, route the webhook through a small relay (a Cloudflare Worker, or a Home Assistant webhook trigger that calls the [Home Assistant recipe](./home-assistant)) that drops events whose `heartbeat.status` is not `0`.

Reference: [API reference](../api)
