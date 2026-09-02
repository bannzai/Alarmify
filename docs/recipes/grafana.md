# Grafana

Add a webhook contact point so that a firing alert rings your iPhone instead of only sending a notification. Uses the contact point's **Custom Payload**, which lets you send exactly the JSON the API expects.

## 1. Create the contact point

Alerting, Contact points, Add contact point. Choose the **Webhook** integration and fill in:

| Setting | Value |
| --- | --- |
| URL | `https://api.alarmify.app/v1/alarms` |
| HTTP Method | `POST` |
| Authentication Header Scheme | `Bearer` |
| Authentication Header Credentials | `<API_TOKEN>` |

## 2. Set the payload template

Under **Optional Webhook settings**, enable **Custom Payload** and paste:

```
{
  "fire_in": 0,
  "title": "{{ .Status | toUpper }}: {{ .CommonLabels.alertname }}"
}
```

`fire_in: 0` rings as soon as the push arrives, so the alarm follows the alert without any date arithmetic in the template. `{{ .Status }}` is `firing` or `resolved`; `{{ .CommonLabels.alertname }}` is the alert rule name.

## 3. Ring only for firing alerts

A resolved notification would also ring. Either add a notification policy that routes only firing alerts to this contact point, or send a title that makes the difference visible and mute the resolved branch in the policy. If your Grafana version cannot filter resolved notifications for a contact point, use the **Disable resolved message** option on the contact point.

## Test it

Contact points, the contact point's menu, **Test**. Send a test notification; your iPhone should ring within a few seconds with the title `FIRING: TestAlert`.

## Older Grafana without Custom Payload

Versions without the Custom Payload option send Grafana's own JSON, which the API does not understand. Put a small relay in between (a Cloudflare Worker, a Home Assistant webhook trigger that calls the [Home Assistant recipe](./home-assistant.md), or a shell script on a server) that receives the Grafana payload and issues the `POST /v1/alarms` call.

Reference: [API reference](../api.md)
