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
{{ coll.Dict "fire_in" 0 "title" (printf "%s: %s" (.Status | toUpper) .CommonLabels.alertname) | data.ToJSON }}
```

`coll.Dict` and `data.ToJSON` build the JSON, so an alert name containing a quote or a backslash is escaped correctly. `fire_in: 0` rings within a minute of the alert (the API's minimum lead time is 30 seconds) without any date arithmetic in the template. `.Status` is `firing` or `resolved`; `.CommonLabels.alertname` is the alert rule name.

## 3. Do not ring when the alert resolves

Grafana sends a second notification when the alert resolves, which would ring again. Turn on **Disable resolved message** on the contact point so only firing alerts reach Alarmify. If you do want a resolved alarm, leave it off; the title starts with `RESOLVED:` so you can tell them apart.

## Test it

Contact points, the contact point's menu, **Test**. Send a test notification; your iPhone should ring within a minute with the title `FIRING: TestAlert`.

## Older Grafana without Custom Payload

Versions without the Custom Payload option send Grafana's own JSON, which the API does not understand. Put a small relay in between (a Cloudflare Worker, a Home Assistant webhook trigger that calls the [Home Assistant recipe](./home-assistant.md), or a shell script on a server) that receives the Grafana payload and issues the `POST /v1/alarms` call.

Reference: [API reference](../api.md)
