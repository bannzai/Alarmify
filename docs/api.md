# Alarmify API reference

Alarmify exposes one HTTPS API. Any system that can send an HTTP request with a header can schedule or cancel a real AlarmKit alarm on your iPhone with it.

> **Planned interface.** The backend is still under development. The host name, the request shape and the error codes on this page describe the planned interface and may change before release. The in-app "Integration recipes" screen shows the same snippets with your token filled in.

- Base URL: `https://api.alarmify.app`
- Format: JSON request and response bodies, UTF-8
- Time: ISO 8601 with a time zone (`2026-09-03T07:00:00Z` or `2026-09-03T16:00:00+09:00`)
- Recipes for GitHub Actions, Home Assistant, Shortcuts, Grafana, Uptime Kuma and cron: [Integration recipes](./recipes/index.md)

## Authentication

Every request carries a personal API token as a bearer token. Issue the token from the Alarmify app; it belongs to your account and to the iPhone that runs the app.

```
Authorization: Bearer <API_TOKEN>
```

A token can be revoked from the app at any time. Requests with a missing, malformed or revoked token get `401 unauthorized`. Treat the token like a password: keep it in a secret store (GitHub Actions secrets, Home Assistant `secrets.yaml`, an environment variable) rather than in a file you commit.

## POST /v1/alarms

Schedules an alarm on your iPhone. The server delivers the request to your device as a push, and the app registers an AlarmKit alarm that rings at the requested time, through Silent mode and Focus, even when the app is closed.

### Request

```
POST /v1/alarms
Authorization: Bearer <API_TOKEN>
Content-Type: application/json
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `fire_at` | string (ISO 8601) | one of `fire_at` / `fire_in` | Absolute time to ring. Must be in the future. |
| `fire_in` | integer (seconds) | one of `fire_at` / `fire_in` | Ring this many seconds after the server receives the request. `0` rings as soon as the push arrives. Use it from tools whose templates cannot compute a date (Grafana, Uptime Kuma, Shortcuts). |
| `title` | string | no | Shown on the alarm. Up to 100 characters; longer titles are truncated. Defaults to `Alarmify`. |
| `id` | string (UUID) | no | Your own identifier for the alarm. Sending the same `id` again replaces the existing alarm instead of creating a second one, so retries are safe. When omitted the server generates one. |

Send exactly one of `fire_at` and `fire_in`.

```sh
curl -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"fire_at":"2026-09-03T07:00:00Z","title":"Deploy finished"}'
```

### Response

`201 Created`

```json
{
  "id": "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e",
  "fire_at": "2026-09-03T07:00:00Z",
  "title": "Deploy finished"
}
```

`fire_at` in the response is always UTC. Keep `id` if you want to cancel the alarm later.

### Errors

| Status | `error.code` | When |
| --- | --- | --- |
| 400 | `invalid_request` | Body is not JSON, both or neither of `fire_at` / `fire_in` are present, `fire_at` is not ISO 8601 or is in the past, `fire_in` is negative, `id` is not a UUID |
| 401 | `unauthorized` | Missing, malformed or revoked token |
| 409 | `no_device` | The account has no iPhone registered (open the app once to register the device) |
| 429 | `quota_exceeded` | The Free plan allows 20 alarms per calendar month. Upgrade to Pro for unlimited alarms |
| 429 | `rate_limited` | More than 60 requests per minute from one token. Retry after the `Retry-After` header |

## DELETE /v1/alarms/{id}

Cancels an alarm that has not fired yet. Use the `id` returned by `POST /v1/alarms` (or the `id` you supplied).

### Request

```sh
curl -X DELETE https://api.alarmify.app/v1/alarms/3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e \
  -H "Authorization: Bearer <API_TOKEN>"
```

### Response

`204 No Content`. Cancelling an alarm that has already fired or was already cancelled also returns `204`, so retries are safe.

### Errors

| Status | `error.code` | When |
| --- | --- | --- |
| 400 | `invalid_request` | `id` is not a UUID |
| 401 | `unauthorized` | Missing, malformed or revoked token |
| 404 | `not_found` | No alarm with this `id` belongs to the account |

## Error format

Every error response has the same JSON body. `message` is for humans and may change; branch on `code`.

```json
{
  "error": {
    "code": "invalid_request",
    "message": "fire_at must be in the future"
  }
}
```

## Limits

| | Free | Pro |
| --- | --- | --- |
| Alarms per calendar month | 20 | Unlimited |
| API tokens | 1 | Multiple (one per system) |
| Devices per account | 1 | Multiple |
| Alarm history in the app | Recent alarms | 30 days |

Requests are rate limited to 60 per minute per token on both plans.

## Delivery and timing

- The alarm is registered on the iPhone as soon as the push arrives, usually within a few seconds. A `201` means the server accepted the request and queued the push, not that the phone has registered the alarm yet.
- If the iPhone is offline, the push is delivered when it reconnects. An alarm whose `fire_at` has already passed by then is dropped.
- AlarmKit alarms ring through Silent mode and Focus and show on the lock screen. They require iOS 26 or later.
