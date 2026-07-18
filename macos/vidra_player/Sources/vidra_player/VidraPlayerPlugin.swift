import Cocoa
import FlutterMacOS
import AVFoundation

public class VidraPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "vidra_player", binaryMessenger: registrar.messenger)
    let instance = VidraPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private var originalFrame: NSRect?
  private var isPip = false
  
  // Thumbnail generators keyed by url. Keyed (not a single instance) so
  // multiple live PlayerControllers in the same engine (grid preview, or a main
  // + mini player) don't clobber each other's generator, and disposing one
  // controller never tears down another's active generator.
  private var imageGenerators: [String: AVAssetImageGenerator] = [:]

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let window = NSApplication.shared.windows.first { window in
        return window.contentViewController is FlutterViewController
    }

    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "isFullscreen":
      let isFull = window?.styleMask.contains(NSWindow.StyleMask.fullScreen) ?? false
      result(isFull)
    case "toggleFullscreen":
      window?.toggleFullScreen(nil)
      let isFull = window?.styleMask.contains(NSWindow.StyleMask.fullScreen) ?? false
      result(isFull)
    case "enterFullscreen":
      if let win = window, !win.styleMask.contains(NSWindow.StyleMask.fullScreen) {
        win.toggleFullScreen(nil)
      }
      result(nil)
    case "exitFullscreen":
      if let win = window, win.styleMask.contains(NSWindow.StyleMask.fullScreen) {
        win.toggleFullScreen(nil)
      }
      result(nil)
    case "enterPip":
      if let win = window, !isPip {
        originalFrame = win.frame
        isPip = true
        win.level = NSWindow.Level.floating
        
        // Mini size (16:9)
        let miniWidth: CGFloat = 500
        let miniHeight: CGFloat = 280
        let screenFrame = win.screen?.visibleFrame ?? .zero
        let newFrame = NSRect(
            x: screenFrame.maxX - miniWidth - 20,
            y: screenFrame.minY + 20,
            width: miniWidth,
            height: miniHeight
        )
        win.setFrame(newFrame, display: true, animate: true)
      }
      result(nil)
    case "exitPip":
      if let win = window, isPip {
        isPip = false
        win.level = NSWindow.Level.normal
        if let frame = originalFrame {
          win.setFrame(frame, display: true, animate: true)
        }
      }
      result(nil)
    case "minimize":
      window?.miniaturize(nil)
      result(nil)
    case "maximize":
      if let win = window, !win.isZoomed {
        win.zoom(nil)
      }
      result(nil)
    case "restore":
        if let win = window {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            } else if win.isZoomed {
                win.zoom(nil)
            }
        }
        result(nil)
    case "close":
      window?.close()
      result(nil)
    case "setTitle":
      if let args = call.arguments as? [String: Any],
         let title = args["title"] as? String {
        window?.title = title
      }
      result(nil)
    case "prepareThumbnailGenerator":
      if let args = call.arguments as? [String: Any],
         let urlString = args["url"] as? String {
        prepareThumbnailGenerator(url: urlString)
      }
      result(nil)
    case "getThumbnail":
      if let args = call.arguments as? [String: Any],
         let urlString = args["url"] as? String,
         let time = args["time"] as? Double {
        getThumbnail(url: urlString, at: time, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "url and time are required", details: nil))
      }
    case "disposeThumbnailGenerator":
        let urlString = (call.arguments as? [String: Any])?["url"] as? String
        disposeThumbnailGenerator(url: urlString)
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepareThumbnailGenerator(url urlString: String) {
    if imageGenerators[urlString] != nil {
      return
    }

    guard let url = URL(string: urlString) else { return }
    let asset = AVAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)

    // Memory Optimization: Limit thumbnail size
    generator.maximumSize = CGSize(width: 320, height: 180)
    // Accuracy: Use zero tolerance for precise frames
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true

    imageGenerators[urlString] = generator
    print("[VidraPlayerPlugin] Thumbnail generator prepared for: \(urlString)")
  }

  private func getThumbnail(url urlString: String, at timeSeconds: Double, result: @escaping FlutterResult) {
    guard let generator = imageGenerators[urlString] else {
      result(FlutterError(code: "NOT_PREPARED", message: "Thumbnail generator not prepared", details: nil))
      return
    }
    
    let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
    
    // Memory Optimization & Prevention of Leaks: Use [weak self]
    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] (requestedTime, image, actualTime, resultStatus, error) in
        DispatchQueue.main.async {
            guard self != nil else { return }
            
            if resultStatus == .succeeded, let cgImage = image {
                let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
                if let tiffData = nsImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                    result(FlutterStandardTypedData(bytes: jpegData))
                    return
                }
            }
            
            if let error = error {
                print("[VidraPlayerPlugin] Thumbnail generation error: \(error.localizedDescription)")
            }
            result(nil)
        }
    }
  }
  
  private func disposeThumbnailGenerator(url urlString: String?) {
      if let urlString = urlString {
          // Remove only this controller's generator.
          imageGenerators.removeValue(forKey: urlString)
          print("[VidraPlayerPlugin] Thumbnail generator disposed for: \(urlString)")
      } else {
          // Legacy/no-url call: clear all (matches old behavior).
          imageGenerators.removeAll()
          print("[VidraPlayerPlugin] All thumbnail generators disposed")
      }
  }

  deinit {
      imageGenerators.removeAll()
  }
}
