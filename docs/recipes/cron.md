# cron / shell

The simplest integration: one `curl` call. Put it at the end of any script, or in a crontab, and your iPhone rings.

## Ring in 5 minutes

`fire_in` counts seconds from the moment the server receives the request, so you do not have to compute a date.

```sh
curl -sS -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"fire_in":300,"title":"Backup finished"}'
```

## Ring at a fixed time

Use `fire_at` with an ISO 8601 time. `date` can produce it for you; pick the variant for your platform.

GNU date (Linux):

```sh
FIRE_AT=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
```

BSD date (macOS):

```sh
FIRE_AT=$(date -u -v+10M +%Y-%m-%dT%H:%M:%SZ)
```

Then send it:

```sh
curl -sS -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d "{\"fire_at\":\"$FIRE_AT\",\"title\":\"Backup finished\"}"
```

## Keep the token out of the script

Export the token once (for example in `~/.profile` or in your CI's secret store) and reference it.

```sh
export ALARMIFY_TOKEN="<API_TOKEN>"
curl -sS -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer $ALARMIFY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fire_in":0,"title":"Job failed"}'
```

## Ring only when a command fails

Keep the command's exit status so that a CI job or a calling script still sees the failure after the alarm has been sent. Running the command inside `if` also keeps a shell with `set -e` from exiting before the alarm is sent.

```sh
if ./deploy.sh; then status=0; else status=$?; fi
if [ "$status" -ne 0 ]; then
  curl -sS --fail-with-body -X POST https://api.alarmify.app/v1/alarms \
    -H "Authorization: Bearer $ALARMIFY_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"fire_in":0,"title":"Deploy failed"}' || echo "alarm request failed" >&2
fi
exit "$status"
```

## crontab

Wake up at 06:30 only on days when a long job has not finished by then: schedule the alarm from the job that is supposed to finish, and cancel it when it does.

```sh
# Next 06:30 in the server's time zone: today if it has not passed yet, otherwise tomorrow
# (GNU date; "tomorrow 06:30" is a calendar date, so it stays 06:30 across DST changes)
next=$(date -d '06:30' +%s)
[ "$next" -gt "$(date +%s)" ] || next=$(date -d 'tomorrow 06:30' +%s)
FIRE_AT=$(date -d "@$next" +%Y-%m-%dT%H:%M:%S%:z)

# Schedule the alarm before the job starts; do not start the job if the alarm was not accepted
response=$(curl -sS --fail-with-body -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer $ALARMIFY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -cn --arg fire_at "$FIRE_AT" '{fire_at: $fire_at, title: "Nightly job is still running"}')") \
  || { echo "alarm request failed: $response" >&2; exit 1; }
ID=$(printf '%s' "$response" | jq -r '.id // empty')
[ -n "$ID" ] || { echo "no alarm id in response: $response" >&2; exit 1; }

./nightly-job.sh

# The job finished: cancel the alarm. --fail-with-body makes a rejected cancellation
# (revoked token, server error) fail the script instead of leaving the alarm scheduled silently
curl -sS --fail-with-body -X DELETE "https://api.alarmify.app/v1/alarms/$ID" \
  -H "Authorization: Bearer $ALARMIFY_TOKEN"
```

Reference: [API reference](../api)
