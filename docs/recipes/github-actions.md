# GitHub Actions

Ring your iPhone when a workflow finishes, or only when it fails. The token lives in a repository secret; the workflow never sees it in plain text.

## 1. Store the token as a secret

From the repository directory, with the GitHub CLI. Omit `--body` so that `gh` prompts for the value: the token then never appears in your shell history or in the process list.

```sh
gh secret set ALARMIFY_TOKEN
# ? Paste your secret: <API_TOKEN>
```

Or in the browser: Settings, Secrets and variables, Actions, New repository secret, name `ALARMIFY_TOKEN`.

## 2. Add a step

`fire_in` needs no date arithmetic. The request body is built with `jq` (preinstalled on GitHub-hosted runners) so a workflow name containing quotes or backslashes still produces valid JSON, and the values come in through `env` so the shell never parses them.

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh

      - name: Ring my iPhone
        if: always()
        env:
          ALARMIFY_TOKEN: ${{ secrets.ALARMIFY_TOKEN }}
          WORKFLOW: ${{ github.workflow }}
          STATUS: ${{ job.status }}
        run: |
          curl -sS --fail-with-body -X POST https://api.alarmify.app/v1/alarms \
            -H "Authorization: Bearer $ALARMIFY_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -cn --arg title "$WORKFLOW: $STATUS" '{fire_in: 0, title: $title}')"
```

- `if: always()` runs the step after a failure too. Use `if: failure()` to ring only when something broke.
- `WORKFLOW` and `STATUS` put the workflow name and `success` / `failure` in the alarm title.
- `--fail-with-body` makes the step fail (and print the API's error body) when the token is invalid, the monthly quota is used up, or the API returns an error, instead of leaving a green step with no alarm.

## Ring at a fixed time instead

A rehearsal alarm one hour before a scheduled release:

```yaml
      - name: Alarm one hour before the release window
        env:
          ALARMIFY_TOKEN: ${{ secrets.ALARMIFY_TOKEN }}
        run: |
          FIRE_AT=$(date -u -d '+60 minutes' +%Y-%m-%dT%H:%M:%SZ)
          curl -sS --fail-with-body -X POST https://api.alarmify.app/v1/alarms \
            -H "Authorization: Bearer $ALARMIFY_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -cn --arg fire_at "$FIRE_AT" '{fire_at: $fire_at, title: "Release window opens in 1 hour"}')"
```

Reference: [API reference](../api.md)
