import AppKit
import Foundation

@main
struct GenerateAppIcon {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 else {
            fputs("Usage: generate-app-icon <output-directory>\n", stderr)
            throw ExitCode.failure
        }

        let outputDirectory = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let iconsetDirectory = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        let iconFile = outputDirectory.appendingPathComponent("AppIcon.icns", isDirectory: false)

        try prepareDirectory(outputDirectory)
        try prepareDirectory(iconsetDirectory)
        try generateIconset(at: iconsetDirectory)
        try buildIcns(iconsetAt: iconsetDirectory, outputFile: iconFile)
    }

    private static func prepareDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    }

    private static func generateIconset(at directory: URL) throws {
        let variants: [(filename: String, dimension: CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        for variant in variants {
            let image = AppIconRenderer.makeApplicationIcon(size: variant.dimension)
            let fileURL = directory.appendingPathComponent(variant.filename, isDirectory: false)
            try writePNG(image: image, to: fileURL)
        }
    }

    private static func writePNG(image: NSImage, to fileURL: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExitCode.failure
        }

        try pngData.write(to: fileURL, options: .atomic)
    }

    private static func buildIcns(iconsetAt iconsetDirectory: URL, outputFile: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = [
            "-c", "icns",
            iconsetDirectory.path,
            "-o", outputFile.path,
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExitCode.failure
        }
    }
}

private enum ExitCode: Error {
    case failure
}
