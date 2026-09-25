# Manifest v1

The canonical schema is `schema/manifest.v1.schema.json`.

The manifest records filesystem metadata only: relative path, filename, byte size, timestamps, cloud-placeholder state, read-only state, and path length. It also records aggregate scan errors so an incomplete scan cannot look complete.

Schema v1 is frozen. Breaking or additive field changes require v2.
