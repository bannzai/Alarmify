# Alarmify API reference

Alarmify exposes one HTTPS API. Any system that can send an HTTP request with a header can schedule or cancel a real AlarmKit alarm on your iPhone with it.

> **Pre-release.** `https://api.alarmify.app` is the planned host name. Until that domain is set up, the API is served at `https://asia-northeast1-alarmify-prod.cloudfunctions.net/alarmsApi` (the in-app "Integration recipes" screen fills in the current host and your token for you). The request and response shapes below match the backend implementation in this repository (`functions/src/api/externalApi.ts`) and may still change before release.

- Base URL: `https://api.alarmify.app` (planned; see the note above)
- Format: JSON request and response bodies, UTF-8
- Time: ISO 8601 with a time zone (`2026-09-03T07:00:00Z` or `2026-09-03T16:00:00+09:00`)
- Recipes for GitHub Actions, Home Assistant, Shortcuts, Grafana, Uptime Kuma and cron: [Integration recipes](./recipes/)

## Authentication

Every request carries a personal API token as a bearer token. Issue the token from the Alarmify app; it belongs to your account and to the iPhone that runs the app.

```
Authorization: Bearer <API_TOKEN>
```

A token can be revoked from the app at any time. Requests with a missing, malformed or revoked token get `401 unauthenticated`. Treat the token like a password: keep it in a secret store (GitHub Actions secrets, Home Assistant `secrets.yaml`, an environment variable) rather than in a file you commit.

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
| `fire_at` | string (ISO 8601, seconds precision, with a time zone) | one of `fire_at` / `fire_in` | Absolute time to ring. At least 30 seconds ahead and at most 365 days ahead (see the lead time below). |
| `fire_in` | integer (seconds) | one of `fire_at` / `fire_in` | Ring this many seconds after the server receives the request, at most 365 days. `0` rings as soon as possible (see the lead time below). Use it from tools whose templates cannot compute a date (Grafana, Uptime Kuma, Shortcuts). |
| `title` | string | no | Shown on the alarm. 1 to 200 characters; longer titles are rejected with `400`. When omitted the app shows `Alarmify`. |
| `id` | string (UUID) | no | Your own identifier for the alarm. Sending the same `id` again replaces the existing alarm instead of creating a second one, so a retry never rings twice. When omitted the server generates one. |

Send exactly one of `fire_at` and `fire_in`.

**Retries.** A repeated request with the same `id` replaces the alarm with the schedule in the new request. With `fire_in` the delay is measured from the new request, so a retry of a timed-out request would move the alarm later. If the exact time matters, compute `fire_at` once and send that same value on every retry.

**Lead time.** The alarm time must be at least 30 seconds after the server receives the request, so the push can reach the phone before the alarm time (an AlarmKit alarm whose time has already passed cannot be registered). A `fire_at` closer than that is rejected with `400`; a `fire_in` below 30 is raised to 30, and the response shows the effective `fire_at`. In practice `fire_in: 0` rings about half a minute after the request.

```sh
curl -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"fire_at":"2026-09-03T07:00:00Z","title":"Deploy finished"}'
```

### Response

`201 Created` for a new alarm, `200 OK` when the request replaced or repeated an alarm with the same `id`.

```json
{
  "id": "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e",
  "status": "scheduled",
  "fire_at": "2026-09-03T07:00:00.000Z",
  "title": "Deploy finished",
  "delivery": { "success_count": 1, "failure_count": 0 }
}
```

`fire_at` in the response is always UTC. `delivery` counts the devices the push was handed to; a `failure_count` above 0 means a device could not be reached. The alarm record stays scheduled on the server, but the push is not retried automatically: send the same request again (same `id`) to redeliver it. Keep `id` if you want to cancel the alarm later.

### Errors

| Status | `error.code` | When |
| --- | --- | --- |
| 400 | `invalid_argument` | Body is not JSON, both or neither of `fire_at` / `fire_in` are present, `fire_at` is not ISO 8601, less than 30 seconds ahead or more than 365 days ahead, `fire_in` is negative or more than 365 days, `title` is empty or longer than 200 characters, `id` is not a UUID |
| 401 | `unauthenticated` | Missing, malformed or revoked token |
| 403 | `plan_limit_exceeded` | The Free plan allows 20 alarms per calendar month. Upgrade to Pro for unlimited alarms |
| 409 | `no_device_registered` | The account has no iPhone registered (open the app once to register the device) |
| 413 | `payload_too_large` | The request body is too large |
| 429 | `rate_limited` | More than 60 requests per minute from one token |

## DELETE /v1/alarms/{id}

Cancels an alarm that has not fired yet. Use the `id` returned by `POST /v1/alarms` (or the `id` you supplied).

### Request

```sh
curl -X DELETE https://api.alarmify.app/v1/alarms/3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e \
  -H "Authorization: Bearer <API_TOKEN>"
```

### Response

`200 OK` with the same body as `POST /v1/alarms`, with `"status": "canceled"`. Cancelling an alarm that was already cancelled returns the same response, so retries are safe.

### Errors

| Status | `error.code` | When |
| --- | --- | --- |
| 400 | `invalid_argument` | `id` is not a UUID |
| 401 | `unauthenticated` | Missing, malformed or revoked token |
| 404 | `not_found` | No alarm with this `id` belongs to the account (alarms are kept for 30 days after they fire or are cancelled) |
| 429 | `rate_limited` | More than 60 requests per minute from one token |

## Error format

Every error response has the same JSON body. `message` is for humans and may change; branch on `code`.

```json
{
  "error": {
    "code": "invalid_argument",
    "message": "fire_at: fire_at には 30 秒以上先の日時を指定してください"
  }
}
```

Unexpected server failures use `500` with `"code": "internal"`.

## Limits

| | Free | Pro |
| --- | --- | --- |
| Alarms per calendar month | 20 | Unlimited |
| API tokens | 1 | Multiple (one per system) |
| Devices per account | 1 | Multiple |
| Alarm history in the app | Recent alarms | 30 days |

Requests are rate limited to 60 per minute per token on both plans. Alarm records (for history and cancellation) are kept for 30 days after the alarm fires or is cancelled.

## Delivery and timing

- The alarm is registered on the iPhone as soon as the push arrives, usually within a few seconds; the alarm time itself is at least 30 seconds after the request (see the lead time above). A `201` means the server accepted the request and queued the push, not that the phone has registered the alarm yet.
- If the iPhone is offline, the push is delivered when it reconnects. An alarm whose `fire_at` has already passed by then is dropped.
- AlarmKit alarms ring through Silent mode and Focus and show on the lock screen. They require iOS 26 or later.
