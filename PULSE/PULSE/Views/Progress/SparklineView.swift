import SwiftUI

/// Minimal sparkline using Canvas — no Charts framework.
struct SparklineView: View {
    let values: [Double]
    var lineColor: Color = .blue
    var showFill: Bool = false

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let pts = normalizedPoints(in: size)

            // Fill area under line
            if showFill {
                var fill = Path()
                fill.move(to: CGPoint(x: pts[0].x, y: size.height))
                for pt in pts { fill.addLine(to: pt) }
                fill.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(lineColor.opacity(0.15)))
            }

            // Line
            var line = Path()
            line.move(to: pts[0])
            for pt in pts.dropFirst() { line.addLine(to: pt) }
            ctx.stroke(line, with: .color(lineColor),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Dots
            for pt in pts {
                let r: CGFloat = 3
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                         with: .color(lineColor))
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let lo = values.min()!
        let hi = values.max()!
        let range = hi - lo
        let pad: CGFloat = 4
        return values.indices.map { i in
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y: CGFloat = range == 0
                ? size.height / 2
                : size.height - pad - CGFloat((values[i] - lo) / range) * (size.height - pad * 2)
            return CGPoint(x: x, y: y)
        }
    }
}
