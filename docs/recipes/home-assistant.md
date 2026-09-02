# Home Assistant

Define one `rest_command` and call it from any automation: a door sensor at night, a washing machine that finished, a leak detector, a calendar event.

## 1. Put the token in `secrets.yaml`

```yaml
# secrets.yaml
alarmify_authorization: "Bearer <API_TOKEN>"
```

## 2. Define the command in `configuration.yaml`

```yaml
# configuration.yaml
rest_command:
  alarmify_alarm:
    url: "https://api.alarmify.app/v1/alarms"
    method: post
    headers:
      authorization: !secret alarmify_authorization
    content_type: "application/json"
    payload: '{"fire_in": {{ fire_in | default(0) }}, "title": {{ title | default("Home Assistant") | to_json }}}'
```

`to_json` JSON-encodes the title (including the surrounding quotes), so a title containing a quote or a backslash still produces a valid request body. Restart Home Assistant (or reload the REST command integration) after editing.

## 3. Call it from an automation

Ring (about a minute later, the API's minimum lead time) when the front door opens between midnight and 6am:

```yaml
# automations.yaml
- alias: "Alarm when the front door opens at night"
  triggers:
    - trigger: state
      entity_id: binary_sensor.front_door
      to: "on"
  conditions:
    - condition: time
      after: "00:00:00"
      before: "06:00:00"
  actions:
    - action: rest_command.alarmify_alarm
      data:
        fire_in: 0
        title: "Front door opened"
```

Ring 10 minutes after the dryer finishes, so you have time to get to it before the clothes wrinkle:

```yaml
    - action: rest_command.alarmify_alarm
      data:
        fire_in: 600
        title: "Dryer finished"
```

## Fixed time with `fire_at`

If you would rather send an absolute time, add a second command that takes `fire_at` and build it with a template:

```yaml
rest_command:
  alarmify_alarm_at:
    url: "https://api.alarmify.app/v1/alarms"
    method: post
    headers:
      authorization: !secret alarmify_authorization
    content_type: "application/json"
    payload: '{"fire_at": {{ fire_at | to_json }}, "title": {{ title | to_json }}}'
```

```yaml
    - action: rest_command.alarmify_alarm_at
      data:
        fire_at: "{{ (utcnow() + timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ') }}"
        title: "Leave for the airport"
```

Reference: [API reference](../api.md)
