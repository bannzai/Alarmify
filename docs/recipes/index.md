# Integration recipes

Copy-and-paste setups for the systems people most often want to be woken up by. Every recipe ends in the same call, `POST /v1/alarms` with your API token, so anything not listed here works the same way. The request and response are documented in the [API reference](../api).

Replace `<API_TOKEN>` with the token issued in the Signalarm app. The in-app "Integration recipes" screen shows these snippets with your token already filled in.

- [cron / shell](./cron): a one-line `curl` for scripts, crontab and CI jobs
- [GitHub Actions](./github-actions): a workflow step that rings when a job finishes or fails
- [Home Assistant](./home-assistant): a `rest_command` you can call from any automation
- [Apple Shortcuts](./shortcuts): the "Get Contents of URL" action, for Shortcuts automations
- [Grafana](./grafana): a webhook contact point that rings when an alert fires
- [Uptime Kuma](./uptime-kuma): a webhook notification that rings when a monitor goes down

> The API is still under development; the host name and request shape may change before release. See the note at the top of the [API reference](../api).
