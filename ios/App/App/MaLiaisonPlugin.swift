import Foundation
import UIKit
import Photos
import AVFoundation
import CoreImage
import ImageIO
import Capacitor

/// Native helpers the web editor calls through Capacitor:
/// - instagramStory: opens Instagram's Story editor with the photo or video as background
/// - saveToPhotos: saves a finished file to the camera roll
/// - compose: builds an MP4 with animated price stickers, from a video or a still background
@objc(MaLiaisonPlugin)
public class MaLiaisonPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MaLiaisonPlugin"
    public let jsName = "MaLiaison"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "instagramStory", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveToPhotos", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "compose", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "canOpen", returnType: CAPPluginReturnPromise)
    ]

    private static let width: CGFloat = 1080
    private static let height: CGFloat = 1920
    private let ciContext = CIContext(options: nil)

    private struct Sticker {
        let image: CIImage
        let cx: CGFloat
        let cy: CGFloat
        let rot: CGFloat
        let anim: String
    }

    private struct Motion {
        var s: CGFloat = 1
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var r: CGFloat = 0
        var a: CGFloat = 1
    }

    // MARK: - Helpers

    private func fileURL(_ value: String?) -> URL? {
        guard let value = value, !value.isEmpty else { return nil }
        if value.hasPrefix("file://") { return URL(string: value) }
        return URL(fileURLWithPath: value)
    }

    private func num(_ value: JSValue?) -> CGFloat {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        if let d = value as? Double { return CGFloat(d) }
        if let f = value as? Float { return CGFloat(f) }
        if let i = value as? Int { return CGFloat(i) }
        return 0
    }

    // Same curves as motion() in the web editor, so the preview matches the export.
    private static func easeOutBack(_ p: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }

    private static func motion(_ kind: String, _ t: Double) -> Motion {
        var m = Motion()
        switch kind {
        case "pop":
            let p = min(t / 0.45, 1)
            m.s = CGFloat(p < 1 ? max(0.001, easeOutBack(p)) : 1)
            m.a = CGFloat(min(1, t / 0.15))
        case "pulse":
            m.s = CGFloat(1 + 0.07 * (0.5 - 0.5 * cos(2 * Double.pi * t / 1.3)))
        case "bounce":
            m.dy = CGFloat(-38 * abs(sin(Double.pi * t / 0.85)))
        case "float":
            m.dy = CGFloat(14 * sin(2 * Double.pi * t / 2.6))
            m.r = CGFloat(0.035 * sin(2 * Double.pi * t / 2.6 + 1.2))
        case "wiggle":
            let ph = t.truncatingRemainder(dividingBy: 2.2)
            m.r = CGFloat(ph < 0.6 ? 0.13 * sin(ph * 2 * Double.pi * 5) * (1 - ph / 0.6) : 0)
        case "slide":
            let p = min(t / 0.55, 1)
            let e = 1 - pow(1 - p, 3)
            m.dx = CGFloat(-(1 - e) * 700)
            m.a = CGFloat(min(1, p * 1.5))
        default:
            break
        }
        return m
    }

    private func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }
        return .up
    }

    private func overlay(base: CIImage, stickers: [Sticker], t: Double) -> CIImage {
        var out = base
        for st in stickers {
            let m = Self.motion(st.anim, t)
            if m.a <= 0.001 { continue }
            let w = st.image.extent.width, h = st.image.extent.height
            // Canvas coordinates grow downwards; Core Image grows upwards, so y and rotation flip.
            let tr = CGAffineTransform(translationX: -w / 2, y: -h / 2)
                .concatenating(CGAffineTransform(scaleX: m.s, y: m.s))
                .concatenating(CGAffineTransform(rotationAngle: -(st.rot + m.r)))
                .concatenating(CGAffineTransform(translationX: st.cx + m.dx, y: Self.height - (st.cy + m.dy)))
            var img = st.image.transformed(by: tr)
            if m.a < 0.999 {
                img = img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: m.a)])
            }
            out = img.composited(over: out)
        }
        return out.cropped(to: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
    }

    /// Places one video frame the way the editor shows it: `rect` is where the picture sits
    /// in the 1080x1920 story (top-left origin), over the colour gradient `bg`.
    private func frameBase(_ source: CIImage, rect: CGRect, blurBg: Bool, bg: CIImage) -> CIImage {
        let W = Self.width, H = Self.height
        let frame = CGRect(x: 0, y: 0, width: W, height: H)
        let e = source.extent
        let img = source.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        let sw = e.width, sh = e.height
        var base = bg.cropped(to: frame)
        if blurBg && sw > 0 && sh > 0 {
            let cs = max(W / sw, H / sh)
            let cover = img.transformed(by: CGAffineTransform(scaleX: cs, y: cs)
                .concatenating(CGAffineTransform(translationX: (W - sw * cs) / 2, y: (H - sh * cs) / 2)))
            let blurred = cover.clampedToExtent().applyingGaussianBlur(sigma: 60).cropped(to: frame)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.12])
            base = blurred.composited(over: base)
        }
        guard sw > 0, sh > 0 else { return base }
        let fg = img.transformed(by: CGAffineTransform(scaleX: rect.width / sw, y: rect.height / sh)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: H - rect.maxY)))
        return fg.composited(over: base).cropped(to: frame)
    }

    // MARK: - Methods

    @objc func canOpen(_ call: CAPPluginCall) {
        guard let s = call.getString("url"), let url = URL(string: s) else {
            call.reject("Missing url")
            return
        }
        DispatchQueue.main.async {
            call.resolve(["value": UIApplication.shared.canOpenURL(url)])
        }
    }

    @objc func instagramStory(_ call: CAPPluginCall) {
        guard let url = fileURL(call.getString("uri")), let data = try? Data(contentsOf: url) else {
            call.reject("File not found")
            return
        }
        let isVideo = call.getString("kind") == "video"
        let appId = call.getString("appId") ?? ""
        let key = isVideo ? "com.instagram.sharedSticker.backgroundVideo" : "com.instagram.sharedSticker.backgroundImage"
        var link = "instagram-stories://share"
        if !appId.isEmpty { link += "?source_application=" + appId }
        guard let target = URL(string: link) else {
            call.reject("Bad Instagram link")
            return
        }
        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(target) else {
                call.reject("Instagram is not installed", "NO_INSTAGRAM")
                return
            }
            UIPasteboard.general.setItems([[key: data]], options: [.expirationDate: Date().addingTimeInterval(300)])
            UIApplication.shared.open(target, options: [:]) { ok in
                call.resolve(["opened": ok])
            }
        }
    }

    @objc func saveToPhotos(_ call: CAPPluginCall) {
        guard let url = fileURL(call.getString("uri")) else {
            call.reject("File not found")
            return
        }
        let isVideo = call.getString("kind") == "video"
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                call.reject("Photos access was not allowed", "DENIED")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }, completionHandler: { ok, error in
                if ok { call.resolve() } else { call.reject(error?.localizedDescription ?? "Could not save") }
            })
        }
    }

    @objc func compose(_ call: CAPPluginCall) {
        let r = call.getObject("rect") ?? [:]
        let rect = CGRect(x: num(r["x"]), y: num(r["y"]), width: num(r["w"]), height: num(r["h"]))
        let blurBg = call.getBool("blurBg") ?? false
        // Soft vertical gradient behind the video, like the web editor: each colour matches the video's edge and darkens slightly towards the screen edge.
        func color(_ key: String, _ k: CGFloat) -> CIColor {
            let c = call.getArray(key) ?? []
            guard c.count == 3 else { return CIColor(red: 0, green: 0, blue: 0) }
            return CIColor(red: num(c[0]) / 255 * k, green: num(c[1]) / 255 * k, blue: num(c[2]) / 255 * k)
        }
        func band(_ key: String, from y0: CGFloat, to y1: CGFloat) -> CIImage? {
            CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: y0), "inputColor0": color(key, 0.78),
                "inputPoint1": CIVector(x: 0, y: y1), "inputColor1": color(key, 1)
            ])?.outputImage
        }
        // Core Image y grows upwards: the top band runs from the screen top (H) down to the video's top edge.
        let H = Self.height, W = Self.width
        let topEdge = max(0, min(H, H - rect.minY)), bottomEdge = max(0, min(H, H - rect.maxY))
        var bg = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
        if let bottom = band("bgBottom", from: 0, to: max(bottomEdge, 1)) {
            bg = bottom.cropped(to: CGRect(x: 0, y: 0, width: W, height: bottomEdge)).composited(over: bg)
        }
        if let top = band("bgTop", from: H, to: min(topEdge, H - 1)) {
            bg = top.cropped(to: CGRect(x: 0, y: topEdge, width: W, height: H - topEdge)).composited(over: bg)
        }
        var stickers: [Sticker] = []
        for value in call.getArray("stickers") ?? [] {
            guard let o = value as? JSObject,
                  let u = fileURL(o["uri"] as? String),
                  let img = CIImage(contentsOf: u) else { continue }
            let e = img.extent
            stickers.append(Sticker(image: img.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)),
                                    cx: num(o["cx"]), cy: num(o["cy"]), rot: num(o["rot"]),
                                    anim: (o["anim"] as? String) ?? "none"))
        }
        let name = (call.getString("name") ?? "ma-liaison") + ".mp4"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: out)
        if let src = fileURL(call.getString("video")) {
            composeVideo(src: src, rect: rect, blurBg: blurBg, bg: bg, stickers: stickers, out: out, call: call)
        } else if let still = fileURL(call.getString("background")) {
            composeStill(background: still, stickers: stickers, duration: call.getDouble("duration") ?? 5, out: out, call: call)
        } else {
            call.reject("Nothing to compose")
        }
    }

    private func composeVideo(src: URL, rect: CGRect, blurBg: Bool, bg: CIImage, stickers: [Sticker], out: URL, call: CAPPluginCall) {
        let asset = AVURLAsset(url: src)
        guard let track = asset.tracks(withMediaType: .video).first else {
            call.reject("This video could not be read")
            return
        }
        let pt = track.preferredTransform
        let shown = track.naturalSize.applying(pt)
        let dw = abs(shown.width), dh = abs(shown.height)
        let orient = orientation(for: pt)
        let comp = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self = self else {
                request.finish(with: NSError(domain: "MaLiaison", code: 1))
                return
            }
            var frame = request.sourceImage
            // Some iOS versions hand over frames before rotation; turn them upright if so.
            if abs(frame.extent.width - dw) > 1 || abs(frame.extent.height - dh) > 1 {
                frame = frame.oriented(orient)
            }
            let t = CMTimeGetSeconds(request.compositionTime)
            let image = self.overlay(base: self.frameBase(frame, rect: rect, blurBg: blurBg, bg: bg), stickers: stickers, t: t)
            request.finish(with: image, context: self.ciContext)
        })
        comp.renderSize = CGSize(width: Self.width, height: Self.height)
        let fps = track.nominalFrameRate > 0 ? min(track.nominalFrameRate, 60) : 30
        comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            call.reject("Video export is not available")
            return
        }
        export.outputURL = out
        export.outputFileType = .mp4
        export.videoComposition = comp
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            if export.status == .completed {
                call.resolve(["uri": out.absoluteString])
            } else {
                call.reject(export.error?.localizedDescription ?? "Video export failed")
            }
        }
    }

    private func composeStill(background: URL, stickers: [Sticker], duration: Double, out: URL, call: CAPPluginCall) {
        guard let loaded = CIImage(contentsOf: background) else {
            call.reject("Background missing")
            return
        }
        let e = loaded.extent
        let base = loaded.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(Self.width),
                    AVVideoHeightKey: Int(Self.height),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = false
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(Self.width),
                    kCVPixelBufferHeightKey as String: Int(Self.height)
                ])
                writer.add(input)
                guard writer.startWriting() else {
                    throw writer.error ?? NSError(domain: "MaLiaison", code: 2)
                }
                writer.startSession(atSourceTime: .zero)
                let fps: Int32 = 30
                let frames = max(1, Int(duration * Double(fps)))
                for i in 0..<frames {
                    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                    guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "MaLiaison", code: 3) }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let pb = buffer else { throw NSError(domain: "MaLiaison", code: 4) }
                    let image = self.overlay(base: base, stickers: stickers, t: Double(i) / Double(fps))
                    self.ciContext.render(image, to: pb)
                    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
                }
                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        call.resolve(["uri": out.absoluteString])
                    } else {
                        call.reject(writer.error?.localizedDescription ?? "Video export failed")
                    }
                }
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }
}

/// Registers the plugin above with the app's web view.
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(MaLiaisonPlugin())
    }
}
