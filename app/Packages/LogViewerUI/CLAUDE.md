# LogViewerUI — Log Panel

## Key Types
- `LogViewerView.swift` (641 lines) — filter bar, log list (ScrollView+LazyVStack), auto-scroll
- `LogViewerViewModel` (@MainActor @Observable) — entries/filteredEntries, append-time filtering, warn/error counts

## UI Features
- Severity pills (toggleable), node search, message search, auto-scroll toggle, newest-at-top toggle
- Warning/error count badges (orange/red)
- Max entries picker (100/500/1000/2000/5000/10000)
- Jump-to-latest floating button (appears when scrolled away from bottom)
- Search highlighting: yellow background via components(separatedBy:)
- Zebra striping: index%2==0 → clear, odd → white.opacity(0.02)

## Persisted Settings (@AppStorage)
- logPanel.maxEntries, logPanel.minSeverity, logPanel.nodeFilter, logPanel.messageFilter
- logPanel.autoScroll, logPanel.newestAtTop

## Gotchas
- Auto-scroll: scroll geometry change detects distance < 8px from bottom (or < 8px from top for newestAtTop)
- Filtering applied at append time AND recomputed from full entries on filter change
- warnCount/errorCount from full entries (not filtered) — badges show totals
