# ConnectionManager — Connection Lifecycle

## Key Types
- `ConnectionManager` (actor) — connect/disconnect/reconnectAll, dedup by URL (O(1) urlIndex)
- `ConnectionHandle { id, profile, transport }` — value type, Hashable by id
- `ConnectionProfile { id, name, url }` — value type, Codable
- `InMemoryProfileStore` (actor) — non-persistent fallback

## Connect Flow
1. Check urlIndex — throw `.alreadyConnected(url)` if duplicate
2. transportFactory(profile) → RosbridgeTransport()
3. transport.connect(url:) → handle
4. Broadcast `connections: AsyncStream<[ConnectionHandle]>`

## Disconnect Flow
1. Check handles[id] — throw `.unknownHandle` if absent
2. transport.disconnect()
3. Remove from handles + urlIndex
4. Broadcast

## Files
- `ConnectionManager.swift`, `ConnectionHandle.swift`, `ConnectionProfile.swift`, `ConnectionManagerError.swift`, `ProfileStoreProtocol.swift`

## Note
Two independent ConnectionProfile types exist (ConnectionManager + ProfileStore) with identical shape. Aliased in Composition layer as ManagerProfile/StoredProfile. Keep separate — never bridge.
