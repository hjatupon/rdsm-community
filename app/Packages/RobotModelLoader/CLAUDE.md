# RobotModelLoader — URDF Loading Orchestrator

## Pipeline
URDF XML → XacroPreprocessor (includes, properties, if/unless) → URDFXMLDelegate → RobotModel → resolveMeshURLs → MeshLoader per link → LoadedRobot

## 3-Step package:// URI Resolution (`resolveMeshURL`)
```
package://<pkg>/<rest>
→ Step 1: meshRoot/<pkg>/<rest>          (explicit mesh root from Settings)
→ Step 2: baseURL/<rest>                  (strip pkg, look next to URDF)
→ Step 3: meshRoot/<rest>                 (flat fallback, no subfolder)
→ nil → warning, link renders placeholder
```

## Key Types
- `LoadedRobot { model: RobotModel, meshes: [String: LoadedMesh], summary, warnings }`
- `RobotModelSummary { rootLink, linkCount, jointCount, links, joints }`
- `RobotModelLoader(context: MetalContext)` — owned by AppServices

## Files
- `RobotModelLoader.swift` — loadFromURDF(xml:baseURL:packagePaths:meshRoot:), loadFromFile(url:)
- URDFParser package: URDFParser, URDFXMLDelegate, XacroPreprocessor, MeshURLResolver, URDFParserError
- MeshLoader package: MeshLoader (ModelIO → MTLBuffer), LoadedMesh, Submesh, Material

## Gotchas
- No mesh cache — each load creates fresh MeshLoader. Caller (AppServices) stores `activeRobotMeshes: [String: LoadedMesh]`
- Supported formats: STL, OBJ, DAE. Normals auto-generated if missing (STL often lacks them)
- Xacro: macro/insert_block NOT supported (throws URDFParserError.unsupportedXacroFeature)
- Link meshScale + visualOrigin parsed from URDF `<mesh scale>` and `<visual><origin>`
