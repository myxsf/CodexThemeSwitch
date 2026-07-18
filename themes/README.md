# Theme catalog

`catalog.json` is the cross-platform display and compatibility catalog.

- `preview` is display-only and may point to a composite mockup.
- Runtime injection must use the validated pack-local `theme.json.image` only.
- `image: null` means a trusted color-only profile; it must never fall back to the preview image.
- `kind: original` means remove the live skin and stop the watcher while preserving the wardrobe and installed theme library.
- Remote packages must not execute arbitrary code. Future distribution should require SHA-256, publisher, package version, engine compatibility and platform metadata before atomic installation.

