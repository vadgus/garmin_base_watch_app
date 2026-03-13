# garmin_base_watch_app

A minimal Garmin Connect IQ watch app example that:
- receives JSON-like payloads from a phone bridge,
- canonicalizes CIQ transport containers into plain data,
- renders a native Garmin menu tree from the payload,
- lets you browse nested objects and arrays on the watch.

## Render Rule

If the incoming root object contains a `menu` key, the app renders that node as the main watch menu.

If `menu` is missing, the app renders the canonical root payload itself.

This makes it possible to keep other payload sections next to the visible menu, for example `meta`, `actions`, or transport fields.

## Example Payload

A complete generic example is included in [example_snapshot_payload.json](example_snapshot_payload.json).

Key parts of the example:
- `menu`: the branch rendered as the watch menu
- `actions`: a generic dictionary that demonstrates metadata living next to the menu
- transport fields such as `snapshot_ts_ms`, `probe`, and `server_connected`

Example shape:

```json
{
  "snapshot_ts_ms": 1760000000123,
  "probe": false,
  "server_connected": true,
  "menu": {
    "overview": {
      "title": "Example Payload",
      "status": "connected"
    },
    "items": [
      {
        "id": "row-001",
        "label": "Alpha"
      }
    ]
  },
  "actions": {
    "open_alpha": {
      "text": "Open Alpha",
      "action": "open",
      "url": "https://example.invalid/actions/open-alpha"
    }
  }
}
```

## Build

```sh
CIQ_DEV_KEY_PATH=/path/to/developer_key.pem ./build_releases.sh
```

The build output is written to `build/garmin_base_watch_app.prg`.

## Toolchain

This public example was validated with the following local toolchain:

- Garmin Connect IQ SDK: `connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa`
- `monkeyc`: from the SDK above
- Java runtime: `OpenJDK 17.0.18`
- Target device profile: `venu3`
- Manifest `minApiLevel`: `5.2.0`

## Notes

- This repository is intentionally generic and public-safe.
- It contains no business-specific payload semantics.
- It uses native Garmin `Menu2` UI for browsing incoming payloads.
- The app is read-only. It does not execute `actions`.

## Maintenance Status

This repository is archived.

The author moved to Wear OS and does not plan to continue maintaining this Garmin repository.

The key reason is that Garmin did not fit the required product direction, especially because the watch -> phone command path through Connect IQ companion messaging proved unreliable in practice.

See [watch_to_phone_transport_postmortem.txt](watch_to_phone_transport_postmortem.txt) for the technical summary of that conclusion.
