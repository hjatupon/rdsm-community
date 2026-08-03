# ProfileStore — Connection Profile Persistence

## Key Types
- `ProfileStore` (actor) — JSON file CRUD at `~/Library/Application Support/ROS2Studio/profiles.json`
- `ConnectionProfile { id: UUID, name, url }` — Codable, Identifiable

## Dedup Logic
- `save()`: same id → update in place. Same url, different id → update name only. Otherwise → append.
- `list()`: groups by url, keeps shorter name (alphabetical tiebreak). If dedup reduced count, writes cleaned list back to disk.

## Files
- `ProfileStore.swift`, `ConnectionProfile.swift`, `ProfileStoreError.swift`

## Errors
- `profileNotFound`, `encodingFailed`, `decodingFailed`, `ioFailed`
