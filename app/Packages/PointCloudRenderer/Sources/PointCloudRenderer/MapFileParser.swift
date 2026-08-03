import Foundation
import ImageIO
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Static Map Parser

/// Parses a ROS2 static map (.yaml + .pgm) into OccupancyGrid cells.
public struct StaticMapParser {

    public struct ParsedMap {
        public var cells: [Int]
        public let width: Int
        public let height: Int
        public let resolution: Double
        public let originX: Double
        public let originY: Double
        public let occupiedThresh: Double
        public let freeThresh: Double
    }

    /// Parse a .yaml map descriptor + .pgm image data into cells.
    public static func parse(yamlData: Data, pgmData: Data) throws -> ParsedMap {
        guard let yamlStr = String(data: yamlData, encoding: .utf8) else {
            throw MapParseError.invalidYAML("Cannot read YAML as UTF-8")
        }

        // Parse YAML fields
        var resolution: Double = 0.05
        var originX: Double = 0
        var originY: Double = 0
        var negate: Int = 0
        var occupiedThresh: Double = 0.65
        var freeThresh: Double = 0.196

        for line in yamlStr.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }

            if trimmed.hasPrefix("resolution:") {
                resolution = Double(trimmed.dropFirst("resolution:".count).trimmingCharacters(in: .whitespaces)) ?? 0.05
            } else if trimmed.hasPrefix("origin:") {
                // Parse [x, y, yaw] array
                let arr = trimmed.dropFirst("origin:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                if arr.count >= 2 {
                    originX = arr[0]
                    originY = arr[1]
                }
            } else if trimmed.hasPrefix("negate:") {
                negate = Int(trimmed.dropFirst("negate:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if trimmed.hasPrefix("occupied_thresh:") {
                occupiedThresh = Double(trimmed.dropFirst("occupied_thresh:".count).trimmingCharacters(in: .whitespaces)) ?? 0.65
            } else if trimmed.hasPrefix("free_thresh:") {
                freeThresh = Double(trimmed.dropFirst("free_thresh:".count).trimmingCharacters(in: .whitespaces)) ?? 0.196
            }
        }

        // Try P5 binary PGM first (most common ROS map format)
        if pgmData.count >= 4,
           pgmData[0] == 0x50, pgmData[1] == 0x35 { // "P5"
            var map = try parseRawPGM(data: pgmData, resolution: resolution, originX: originX, originY: originY, occupiedThresh: occupiedThresh, freeThresh: freeThresh)
            if negate != 0 {
                map.cells = map.cells.map { cell in
                    if cell == -1 { return -1 }
                    return cell == 0 ? 100 : (cell == 100 ? 0 : cell)
                }
            }
            return map
        }

        // Fallback: try ImageIO for PNG/JPEG PGMs
        guard let provider = CGDataProvider(data: pgmData as CFData),
              let cgImage = CGImage(
                pngDataProviderSource: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
              ?? CGImage(
                jpegDataProviderSource: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else {
            // Try loading as raw PGM (P5 binary format)
            return try parseRawPGM(data: pgmData, resolution: resolution, originX: originX, originY: originY, occupiedThresh: occupiedThresh, freeThresh: freeThresh)
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bitsPerPixel = cgImage.bitsPerPixel

        guard bitsPerPixel >= 8 else {
            throw MapParseError.invalidPGM("Invalid pixel format")
        }

        // Read pixel data from CGImage
        guard let pixelData = cgImage.dataProvider?.data,
              let pixels = CFDataGetBytePtr(pixelData)
        else {
            throw MapParseError.invalidPGM("Cannot read pixel data")
        }

        var cells = [Int]()
        cells.reserveCapacity(width * height)

        for row in (0..<height).reversed() { // PGM is top-down, ROS is bottom-up
            for col in 0..<width {
                let offset = row * bytesPerRow + col
                let pixelValue = Int(pixels[offset])

                // Apply negate if set
                let val = negate != 0 ? (255 - pixelValue) : pixelValue

                let cellVal: Int
                if Double(val) / 255.0 >= occupiedThresh {
                    cellVal = 100 // occupied
                } else if Double(val) / 255.0 <= freeThresh {
                    cellVal = 0 // free
                } else {
                    cellVal = -1 // unknown
                }
                cells.append(cellVal)
            }
        }

        return ParsedMap(
            cells: cells,
            width: width,
            height: height,
            resolution: resolution,
            originX: originX,
            originY: originY,
            occupiedThresh: occupiedThresh,
            freeThresh: freeThresh)
    }

    /// Parse raw P5 binary PGM format (header + pixel data, no ImageIO).
    private static func parseRawPGM(
        data: Data, resolution: Double,
        originX: Double, originY: Double,
        occupiedThresh: Double, freeThresh: Double
    ) throws -> ParsedMap {
        // P5 header format:
        //   P5\n
        //   # comment\n   (optional, can be multiple)
        //   width height\n
        //   maxval\n
        //   <binary pixel data>
        let bytes = [UInt8](data)
        var offset = 0

        // Skip "P5\n"
        guard bytes.count > 3, bytes[0] == 0x50, bytes[1] == 0x35, bytes[2] == 0x0A else {
            throw MapParseError.invalidPGM("Not a P5 PGM file")
        }
        offset = 3

        // Skip comment lines (start with '#')
        while offset < bytes.count && bytes[offset] == 0x23 { // '#'
            while offset < bytes.count && bytes[offset] != 0x0A { offset += 1 }
            offset += 1 // skip \n
        }

        // Read "width height"
        guard let dimLine = readLine(from: bytes, at: &offset) else {
            throw MapParseError.invalidPGM("Cannot read PGM dimensions")
        }
        let dims = dimLine.split(separator: " ")
        guard dims.count == 2, let width = Int(dims[0]), let height = Int(dims[1]), width > 0, height > 0 else {
            throw MapParseError.invalidPGM("Invalid PGM dimensions: \(dimLine)")
        }

        // Read "maxval"
        guard let maxvalLine = readLine(from: bytes, at: &offset) else {
            throw MapParseError.invalidPGM("Cannot read PGM maxval")
        }
        _ = Int(maxvalLine) ?? 255

        // offset now points to the start of binary pixel data
        let pixelDataStart = offset
        let expectedPixels = width * height
        guard bytes.count - pixelDataStart >= expectedPixels else {
            throw MapParseError.invalidPGM("PGM pixel data truncated: expected \(expectedPixels), got \(bytes.count - pixelDataStart)")
        }

        var cells = [Int]()
        cells.reserveCapacity(expectedPixels)
        for row in (0..<height).reversed() { // PGM is top-down, ROS is bottom-up
            for col in 0..<width {
                let pixelValue = Int(bytes[pixelDataStart + row * width + col])
                let cellVal: Int
                if Double(pixelValue) / 255.0 >= occupiedThresh {
                    cellVal = 100
                } else if Double(pixelValue) / 255.0 <= freeThresh {
                    cellVal = 0
                } else {
                    cellVal = -1
                }
                cells.append(cellVal)
            }
        }
        return ParsedMap(
            cells: cells, width: width, height: height,
            resolution: resolution, originX: originX, originY: originY,
            occupiedThresh: occupiedThresh, freeThresh: freeThresh)
    }

    /// Read a newline-terminated ASCII line from a byte buffer, advancing the offset.
    private static func readLine(from bytes: [UInt8], at offset: inout Int) -> String? {
        let start = offset
        while offset < bytes.count && bytes[offset] != 0x0A { offset += 1 }
        guard offset > start else { return nil }
        offset += 1 // skip \n
        return String(bytes: bytes[start..<offset-1], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - PLY Parser

/// Parses ASCII and binary little-endian PLY files.
public struct PLYParser {

    public struct ParsedMesh {
        public let vertices: [MMVertex]
        public let indices: [UInt32]
    }

    public static func parse(data: Data) throws -> ParsedMesh {
        guard let content = String(data: data, encoding: .utf8) else {
            throw MapParseError.invalidPLY("Cannot read PLY as UTF-8")
        }

        let lines = content.split(separator: "\n").map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "ply" else {
            throw MapParseError.invalidPLY("Not a PLY file")
        }

        // Parse header
        var format = "ascii"
        var vertexCount = 0
        var faceCount = 0
        var vertexProperties: [String] = []
        var inVertex = false
        var inFace = false
        var headerEnd = 0

        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { continue }

            switch parts[0] {
            case "format":
                if parts.count >= 2 { format = parts[1] }
            case "element":
                if parts.count >= 3 {
                    if parts[1] == "vertex" {
                        vertexCount = Int(parts[2]) ?? 0
                        inVertex = true
                        inFace = false
                    } else if parts[1] == "face" {
                        faceCount = Int(parts[2]) ?? 0
                        inVertex = false
                        inFace = true
                    }
                }
            case "property":
                if inVertex && parts.count >= 3 {
                    vertexProperties.append(parts.last!)
                }
            case "end_header":
                headerEnd = i + 1
                break
            default:
                break
            }
        }

        // Parse vertex data
        var vertices = [MMVertex]()
        vertices.reserveCapacity(vertexCount)

        if format == "ascii" {
            let dataLines = Array(lines[headerEnd...])
            for i in 0..<min(vertexCount, dataLines.count) {
                let vals = dataLines[i].split(separator: " ").map { Float($0) ?? 0 }
                var v = MMVertex(x: 0, y: 0, z: 0)
                if vals.count >= 3 {
                    v.x = vals[0]; v.y = vals[1]; v.z = vals[2]
                }
                if vals.count >= 6 {
                    v.nx = vals[3]; v.ny = vals[4]; v.nz = vals[5]
                }
                if vals.count >= 9 {
                    v.r = UInt8(vals[6]); v.g = UInt8(vals[7]); v.b = UInt8(vals[8])
                }
                vertices.append(v)
            }
        } else {
            // Binary little-endian: skip header bytes
            let headerBytes = lines[0...headerEnd-1].joined(separator: "\n").data(using: .utf8)?.count ?? 0
            let binaryData = data.subdata(in: headerBytes..<data.count)
            let stride = vertexProperties.count * 4 // all properties are 4-byte floats

            for i in 0..<vertexCount {
                let offset = i * stride
                guard offset + stride <= binaryData.count else { break }

                var v = MMVertex(x: 0, y: 0, z: 0)
                binaryData.withUnsafeBytes { ptr in
                    let base = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                    if vertexProperties.count >= 3 {
                        v.x = base[0]; v.y = base[1]; v.z = base[2]
                    }
                    if vertexProperties.count >= 6 {
                        v.nx = base[3]; v.ny = base[4]; v.nz = base[5]
                    }
                    if vertexProperties.count >= 9 {
                        v.r = UInt8(max(0, min(255, base[6])))
                        v.g = UInt8(max(0, min(255, base[7])))
                        v.b = UInt8(max(0, min(255, base[8])))
                    }
                }
                vertices.append(v)
            }
        }

        // Parse face data
        var indices = [UInt32]()
        indices.reserveCapacity(faceCount * 3)

        if format == "ascii" {
            let dataLines = Array(lines[headerEnd...])
            let faceStart = vertexCount
            for i in 0..<min(faceCount, dataLines.count - faceStart) {
                let parts = dataLines[faceStart + i].split(separator: " ").map { Int($0) ?? 0 }
                guard parts.count >= 4, parts[0] == 3 else { continue }
                indices.append(contentsOf: [UInt32(parts[1]), UInt32(parts[2]), UInt32(parts[3])])
            }
        } else {
            let headerBytes = lines[0...headerEnd-1].joined(separator: "\n").data(using: .utf8)?.count ?? 0
            let vertexDataSize = vertexCount * vertexProperties.count * 4
            let faceDataStart = headerBytes + vertexDataSize
            let faceData = data.subdata(in: faceDataStart..<data.count)
            var offset = 0

            for _ in 0..<faceCount {
                guard offset < faceData.count else { break }
                faceData.withUnsafeBytes { ptr in
                    let count = Int(ptr.load(fromByteOffset: offset, as: UInt8.self))
                    offset += 1
                    if count == 3, offset + 12 <= faceData.count {
                        let base = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
                        indices.append(contentsOf: [base[0], base[1], base[2]])
                        offset += 12
                    } else {
                        offset += count * 4
                    }
                }
            }
        }

        return ParsedMesh(vertices: vertices, indices: indices)
    }
}

// MARK: - OBJ Parser

/// Parses simple OBJ files (vertices + normals + faces).
public struct OBJParser {

    public static func parse(data: Data) throws -> PLYParser.ParsedMesh {
        guard let content = String(data: data, encoding: .utf8) else {
            throw MapParseError.invalidOBJ("Cannot read OBJ as UTF-8")
        }

        var positions = [(Float, Float, Float)]()
        var normals = [(Float, Float, Float)]()
        var vertices = [MMVertex]()
        var indices = [UInt32]()

        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { continue }

            switch parts[0] {
            case "v":
                guard parts.count >= 4 else { continue }
                let x = Float(parts[1]) ?? 0
                let y = Float(parts[2]) ?? 0
                let z = Float(parts[3]) ?? 0
                positions.append((x, y, z))
            case "vn":
                guard parts.count >= 4 else { continue }
                let nx = Float(parts[1]) ?? 0
                let ny = Float(parts[2]) ?? 0
                let nz = Float(parts[3]) ?? 0
                normals.append((nx, ny, nz))
            case "f":
                // Support triangle and quad faces (vertex//normal format)
                let faceParts = parts.dropFirst().compactMap { $0.split(separator: "/").map(String.init) }
                guard faceParts.count >= 3 else { continue }

                // Convert to triangles (fan triangulation)
                let verts = faceParts.prefix(3).map { fp -> (Int, Int) in
                    let vi = (Int(fp[0]) ?? 1) - 1
                    let ni = fp.count >= 3 ? ((Int(fp[2]) ?? 1) - 1) : -1
                    return (vi, ni)
                }

                // Simple fan for quads
                let faceVerts = faceParts.map { fp -> (Int, Int) in
                    let vi = (Int(fp[0]) ?? 1) - 1
                    let ni = fp.count >= 3 ? ((Int(fp[2]) ?? 1) - 1) : -1
                    return (vi, ni)
                }

                for i in 1..<(faceVerts.count - 1) {
                    indices.append(UInt32(vertices.count))
                    for j in [0, i, i + 1] {
                        let (vi, ni) = faceVerts[j]
                        guard vi >= 0, vi < positions.count else { continue }
                        let p = positions[vi]
                        var v = MMVertex(x: p.0, y: p.1, z: p.2)
                        if ni >= 0, ni < normals.count {
                            let n = normals[ni]
                            v.nx = n.0; v.ny = n.1; v.nz = n.2
                        }
                        vertices.append(v)
                    }
                }
            default:
                break
            }
        }

        return PLYParser.ParsedMesh(vertices: vertices, indices: indices)
    }
}

// MARK: - Errors

public enum MapParseError: Error, LocalizedError {
    case invalidYAML(String)
    case invalidPGM(String)
    case invalidPLY(String)
    case invalidOBJ(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let msg): return "Invalid YAML: \(msg)"
        case .invalidPGM(let msg):  return "Invalid PGM: \(msg)"
        case .invalidPLY(let msg):  return "Invalid PLY: \(msg)"
        case .invalidOBJ(let msg):  return "Invalid OBJ: \(msg)"
        case .fileNotFound(let msg): return "File not found: \(msg)"
        }
    }
}
