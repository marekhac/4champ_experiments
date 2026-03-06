//
//  CarPlayController+ImageHelpers.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import UIKit

extension CarPlayController {

    // MARK: - Image helpers

    private static let formatLabelAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 10),
        .foregroundColor: UIColor.darkText
    ]

    func controlIcon(named name: String) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func moduleIcon(for module: MMD) -> UIImage? {
        guard let base = UIImage(named: "modicon") else { return nil }
        return UIGraphicsImageRenderer(size: base.size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            if let format = module.type, !format.isEmpty {
                drawFormatLabel(format, in: base.size)
            }
        }
    }

    // Must be called from within an active UIGraphicsImageRenderer context.
    private func drawFormatLabel(_ format: String, in size: CGSize) {
        let text = format.uppercased() as NSString
        let textSize = text.size(withAttributes: Self.formatLabelAttrs)
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: size.height - textSize.height - 8
        )
        text.draw(at: origin, withAttributes: Self.formatLabelAttrs)
    }
}
