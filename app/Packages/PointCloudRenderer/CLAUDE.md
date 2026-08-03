# PointCloudRenderer — Metal Rendering Pipeline

## Key Types
- `PointCloudRenderer` (@unchecked Sendable) — main renderer, single-pass MTLRenderCommandEncoder
- `LayeredFrameStore` (NSLock) — [topic: PointCloudFrame] dictionary, snapshot copy per frame
- `CameraBox` (NSLock) — azimuth/elevation/distance/target/roll/panOffset
- `GridRenderer` — floor sheet at Y=0, extent ±5m
- `OccupancyGridRenderer` — quad meshes, max 1M cells
- `OctomapRenderer` — voxel cubes, recursive binary octree parser
- `MeshMapRenderer` — lit triangle meshes (PLY/OBJ), diffuse + ambient

## Render Order (single pass)
1. Grid → 2. OccupancyGrid → 3. Octomap → 4. MeshMap → 5. Point cloud layers → 6. RobotModel

## Shaders
- `PointCloud.metal` — pointVertex (MVP + color modes + pointSize) + pointFragment (round sprites)
- `Grid.metal`, `OccupancyGrid.metal`, `Octomap.metal`, `MeshMap.metal`

## LOD
- Automatic stride decimation: if count > 500,000, stride = ceil(count / 500k)
- Buffer budget: 16 MB max per frame

## Gotchas
- `render()` MUST always open a render pass (even when `frames.isEmpty`) — old geometry persists otherwise
- Camera: right-handed, Y-up, roll applied around forward axis, target always origin + panOffset
- `Camera` (value type) vs `CameraState` (Viewer3DUI) — two independent implementations
- ResourcePool: power-of-two bucketed MTLBuffer reuse, max 4 per bucket
