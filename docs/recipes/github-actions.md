# GitHub Actions

Ring your iPhone when a workflow finishes, or only when it fails. The token lives in a repository secret; the workflow never sees it in plain text.

## 1. Store the token as a secret

From the repository directory, with the GitHub CLI:

```sh
gh secret set ALARMIFY_TOKEN --body "<API_TOKEN>"
```

Or in the browser: Settings, Secrets and variables, Actions, New repository secret, name `ALARMIFY_TOKEN`.

## 2. Add a step

Ubuntu runners have GNU `date`, so a `fire_at` a minute from now is one line. `fire_in` is simpler still and needs no date at all.

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
        run: |
          curl -sS -X POST https://api.alarmify.app/v1/alarms \
            -H "Authorization: Bearer $ALARMIFY_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"fire_in\":0,\"title\":\"${{ github.workflow }}: ${{ job.status }}\"}"
```

- `if: always()` runs the step after a failure too. Use `if: failure()` to ring only when something broke.
- `${{ github.workflow }}` and `${{ job.status }}` put the workflow name and `success` / `failure` in the alarm title.

## Ring at a fixed time instead

A rehearsal alarm one hour before a scheduled release:

```yaml
      - name: Alarm one hour before the release window
        env:
          ALARMIFY_TOKEN: ${{ secrets.ALARMIFY_TOKEN }}
        run: |
          FIRE_AT=$(date -u -d '+60 minutes' +%Y-%m-%dT%H:%M:%SZ)
          curl -sS -X POST https://api.alarmify.app/v1/alarms \
            -H "Authorization: Bearer $ALARMIFY_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"fire_at\":\"$FIRE_AT\",\"title\":\"Release window opens in 1 hour\"}"
```

Reference: [API reference](../api.md)
