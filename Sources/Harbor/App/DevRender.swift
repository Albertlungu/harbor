import AppKit
import HarborCore
import SwiftUI

/// Renders views straight to image files and quits, so artwork can be reviewed without
/// putting anything on screen. Launch with HARBOR_RENDER_PET=<folder>.
@MainActor
enum DevRender {
    static func runIfRequested() -> Bool {
        guard let folder = ProcessInfo.processInfo.environment["HARBOR_RENDER_PET"] else { return false }
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let sheet = HStack(spacing: 18) {
                ForEach(PetExpression.allCases, id: \.self) { expression in
                    VStack(spacing: 6) {
                        ForEach([32.0, 48, 96], id: \.self) { unit in
                            PetFigure(unit: unit, pose: PetPose(face: expression.face), padBottom: false)
                                .frame(width: unit, height: unit)
                        }
                        Text(expression.rawValue).font(.caption2).foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            .padding(20)
            .background(Tokens.dockSolid)
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: sheet.environment(\.colorScheme, appearance == .aqua ? .light : .dark))
                renderer.scale = 2
                if let image = renderer.cgImage,
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? data.write(to: out.appendingPathComponent("pet-\(appearance == .aqua ? "light" : "dark").png"))
                }
            }
        }
        return true
    }
}
