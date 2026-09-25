import CoreGraphics
import Foundation

/// How an arrow-kind mark is drawn (ticket 85). Line is the plain Line tool's mark: no head.
public enum ArrowStyle: String, CaseIterable, Equatable, Sendable {
    /// A shaft tapering towards a solid head.
    case standard
    /// A tapered shaft along a curve through a middle handle; the head follows the curve's tangent.
    case curved
    /// A shaft of constant width with a solid head at each end.
    case double
    /// A constant-width line with square ends and no head.
    case line

    /// The styles the Arrow tool's style menu offers.
    public static let arrowStyles: [ArrowStyle] = [.standard, .curved, .double]

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .curved: "Curved"
        case .double: "Double"
        case .line: "Line"
        }
    }
}

/// Where a Curved arrow's middle handle sits, relative to its chord (tail to tip): `along` times the
/// chord plus `across` times the chord turned a quarter (`(-dy, dx)`), from the chord's midpoint.
/// Being relative, it keeps the curve's shape when the arrow is moved or its ends are dragged.
public struct ArrowBend: Equatable, Sendable {
    public let along: Double
    public let across: Double

    public init?(along: Double, across: Double) {
        guard along.isFinite, across.isFinite else { return nil }
        self.along = along
        self.across = across
    }

    private init(exactly along: Double, _ across: Double) {
        self.along = along
        self.across = across
    }

    /// No bend: the handle is at the chord's midpoint.
    public static let straight = ArrowBend(exactly: 0, 0)
    /// A new Curved arrow bows by a fifth of its length.
    public static let newCurve = ArrowBend(exactly: 0, -0.2)

    /// The middle handle's position for this chord.
    public func handle(tail: CGPoint, tip: CGPoint) -> CGPoint {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        return CGPoint(x: (tail.x + tip.x) / 2 + along * dx - across * dy,
                       y: (tail.y + tip.y) / 2 + along * dy + across * dx)
    }

    /// The bend that puts the middle handle at `point`, or nil for an empty chord.
    public static func through(_ point: CGPoint, tail: CGPoint, tip: CGPoint) -> ArrowBend? {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return nil }
        let mx = point.x - (tail.x + tip.x) / 2, my = point.y - (tail.y + tip.y) / 2
        return ArrowBend(along: (mx * dx + my * dy) / squared, across: (my * dx - mx * dy) / squared)
    }
}

/// The shapes an arrow-kind mark is made of, as filled polygons (ticket 85). Pure geometry, in
/// whatever units the caller passes: the painter passes output pixels, so the preview and the
/// delivered image fill the same polygons.
public enum ArrowGeometry {
    /// Points along a curve, for drawing, hit-testing and bounds.
    public static let curveSamples = 48

    /// A head's length for a line `width` points wide, in points: 12 pt at the default 2 pt.
    public static func headLength(width: Double) -> Double { 6 + 3 * width }

    /// The quadratic Bézier's control point: the curve passes through the middle handle at t = ½.
    public static func control(tail: CGPoint, tip: CGPoint, bend: ArrowBend) -> CGPoint {
        let handle = bend.handle(tail: tail, tip: tip)
        return CGPoint(x: 2 * handle.x - (tail.x + tip.x) / 2, y: 2 * handle.y - (tail.y + tip.y) / 2)
    }

    /// The mark's centre line: two points when straight, `curveSamples + 1` along a Curved arrow.
    public static func spine(style: ArrowStyle, tail: CGPoint, tip: CGPoint, bend: ArrowBend) -> [CGPoint] {
        guard style == .curved else { return [tail, tip] }
        let control = control(tail: tail, tip: tip, bend: bend)
        return (0...curveSamples).map { point(Double($0) / Double(curveSamples), tail, control, tip) }
    }

    /// The polygons to fill, each closed, in the units of the inputs. `width` is the line width and
    /// `head` the nominal head length. Polygons are filled one by one, so overlaps never cancel.
    public static func polygons(style: ArrowStyle, tail: CGPoint, tip: CGPoint, bend: ArrowBend,
                                width: Double, head: Double) -> [[CGPoint]] {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, width > 0 else { return [] }
        let control = style == .curved ? control(tail: tail, tip: tip, bend: bend)
            : CGPoint(x: (tail.x + tip.x) / 2, y: (tail.y + tip.y) / 2)
        switch style {
        case .line:
            // Square ends, as the old pen's square caps.
            let ux = dx / length * width / 2, uy = dy / length * width / 2
            return [[CGPoint(x: tail.x - ux - uy, y: tail.y - uy + ux), CGPoint(x: tip.x + ux - uy, y: tip.y + uy + ux),
                     CGPoint(x: tip.x + ux + uy, y: tip.y + uy - ux), CGPoint(x: tail.x - ux + uy, y: tail.y - uy - ux)]]
        case .standard, .curved:
            let size = min(head, 0.6 * length)
            let shaft = band(tail, control, tip, from: 0, to: size / 2, tailHalf: width / 4, tipHalf: width * 3 / 4)
            return [shaft, headTriangle(at: tip, towards: direction(from: control, to: tip, fallback: (dx, dy)), size: size)]
        case .double:
            let size = min(head, 0.4 * length)
            let shaft = band(tail, control, tip, from: size / 2, to: size / 2, tailHalf: width / 2, tipHalf: width / 2)
            return [shaft,
                    headTriangle(at: tip, towards: direction(from: control, to: tip, fallback: (dx, dy)), size: size),
                    headTriangle(at: tail, towards: direction(from: control, to: tail, fallback: (-dx, -dy)), size: size)]
        }
    }

    /// A solid head: its point at `tip`, `size` long along `towards`, and `size` wide in all.
    static func headTriangle(at tip: CGPoint, towards unit: (x: Double, y: Double), size: Double) -> [CGPoint] {
        let base = CGPoint(x: tip.x - unit.x * size, y: tip.y - unit.y * size)
        let half = size / 2
        return [tip, CGPoint(x: base.x - unit.y * half, y: base.y + unit.x * half),
                CGPoint(x: base.x + unit.y * half, y: base.y - unit.x * half)]
    }

    private static func direction(from a: CGPoint, to b: CGPoint, fallback: (Double, Double)) -> (x: Double, y: Double) {
        var x = Double(b.x - a.x), y = Double(b.y - a.y)
        var length = (x * x + y * y).squareRoot()
        if length < 1e-12 {
            (x, y) = fallback
            length = (x * x + y * y).squareRoot()
        }
        return (x / length, y / length)
    }

    private static func point(_ t: Double, _ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> CGPoint {
        let s = 1 - t
        return CGPoint(x: s * s * a.x + 2 * s * t * c.x + t * t * b.x, y: s * s * a.y + 2 * s * t * c.y + t * t * b.y)
    }

    private static func derivative(_ t: Double, _ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> (x: Double, y: Double) {
        (2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x), 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y))
    }

    /// The band around the curve from arc length `from` after the tail to `to` before the tip, its half
    /// width going linearly from `tailHalf` to `tipHalf`. A straight chord (control at its midpoint)
    /// gives a four-cornered band.
    private static func band(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, from start: Double, to end: Double,
                             tailHalf: Double, tipHalf: Double) -> [CGPoint] {
        let straight = abs(2 * c.x - a.x - b.x) < 1e-12 && abs(2 * c.y - a.y - b.y) < 1e-12
        let n = straight ? 1 : curveSamples
        // Cumulative arc length at each sample, to find the band's ends.
        let fine = (0...n).map { point(Double($0) / Double(n), a, c, b) }
        var lengths = [0.0]
        for i in 1...n { lengths.append(lengths[i - 1] + hypot(fine[i].x - fine[i - 1].x, fine[i].y - fine[i - 1].y)) }
        let total = lengths[n]
        func parameter(atLength s: Double) -> Double {
            let s = min(max(s, 0), total)
            guard let i = lengths.indices.dropFirst().first(where: { lengths[$0] >= s }) else { return 1 }
            let span = lengths[i] - lengths[i - 1]
            let f = span > 0 ? (s - lengths[i - 1]) / span : 0
            return (Double(i - 1) + f) / Double(n)
        }
        var t0 = parameter(atLength: start), t1 = parameter(atLength: total - end)
        if t1 <= t0 { (t0, t1) = (0, 1) }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let f = Double(i) / Double(n), t = t0 + (t1 - t0) * f
            let p = point(t, a, c, b)
            var d = derivative(t, a, c, b)
            var dl = (d.x * d.x + d.y * d.y).squareRoot()
            if dl < 1e-12 { d = (b.x - a.x, b.y - a.y); dl = (d.x * d.x + d.y * d.y).squareRoot() }
            let half = tailHalf + (tipHalf - tailHalf) * f
            let nx = -d.y / dl * half, ny = d.x / dl * half
            left.append(CGPoint(x: p.x + nx, y: p.y + ny))
            right.append(CGPoint(x: p.x - nx, y: p.y - ny))
        }
        return left + right.reversed()
    }
}
