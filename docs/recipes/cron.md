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

Use `fire_at` with an ISO 8601 time. `date` can produce it for you.

```sh
# GNU date (Linux)
FIRE_AT=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
# BSD date (macOS)
FIRE_AT=$(date -u -v+10M +%Y-%m-%dT%H:%M:%SZ)

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

Keep the command's exit status so that a CI job or a calling script still sees the failure after the alarm has been sent.

```sh
./deploy.sh; status=$?
if [ "$status" -ne 0 ]; then
  curl -sS -X POST https://api.alarmify.app/v1/alarms \
    -H "Authorization: Bearer $ALARMIFY_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"fire_in":0,"title":"Deploy failed"}'
fi
exit "$status"
```

## crontab

Wake up at 06:30 only on days when a long job has not finished by then: schedule the alarm from the job that is supposed to finish, and cancel it when it does.

```sh
# Compute the next 06:30 in the server's time zone (GNU date; for macOS see "Ring at a fixed time" above)
FIRE_AT=$(date -d 'tomorrow 06:30' +%Y-%m-%dT%H:%M:%S%:z)

# Schedule the alarm when the job starts and keep the id
ID=$(curl -sS -X POST https://api.alarmify.app/v1/alarms \
  -H "Authorization: Bearer $ALARMIFY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"fire_at\":\"$FIRE_AT\",\"title\":\"Nightly job is still running\"}" | jq -r .id)

./nightly-job.sh

# The job finished: cancel the alarm
curl -sS -X DELETE "https://api.alarmify.app/v1/alarms/$ID" \
  -H "Authorization: Bearer $ALARMIFY_TOKEN"
```

Reference: [API reference](../api.md)
