# Apple Shortcuts

Use the "Get Contents of URL" action. Any Shortcuts automation (arriving somewhere, a time of day, an NFC tag, a Focus turning on) can then schedule a real alarm.

## Build the shortcut

1. Open Shortcuts and create a new shortcut.
2. Add the action **Get Contents of URL**.
3. Set the URL to:

   ```
   https://api.alarmify.app/v1/alarms
   ```

4. Expand the action (tap the arrow), set **Method** to **POST**.
5. Under **Headers**, add two fields:

   | Key | Value |
   | --- | --- |
   | `Authorization` | `Bearer <API_TOKEN>` |
   | `Content-Type` | `application/json` |

6. Under **Request Body**, choose **JSON** and add the fields:

   | Key | Type | Value |
   | --- | --- | --- |
   | `fire_in` | Number | `300` |
   | `title` | Text | `Leave now` |

7. Run the shortcut once. Your iPhone rings 5 minutes later.

## Ask for the delay each time

Put an **Ask for Input** action (Number) before the URL action, then a **Calculate** action that multiplies the input by 60 (`fire_in` is in seconds), and use the calculation result as the value of `fire_in`. One shortcut then covers "ring me in N minutes" for any N.

## Fixed time instead of a delay

Replace `fire_in` with `fire_at` and build the value with the **Format Date** action: choose **Custom** and use the format string `yyyy-MM-dd'T'HH:mm:ssZZZZZ`. Feed it a date from **Adjust Date** (for example, current date plus 1 hour).

## Cancel from a shortcut

Save the `id` from the response (**Get Dictionary Value** with key `id`) and send a second **Get Contents of URL** with Method **DELETE** to:

```
https://api.alarmify.app/v1/alarms/<id>
```

with the same `Authorization` header.

Reference: [API reference](../api.md)
