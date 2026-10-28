import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The editor shell draws its own title bar (spec 006, T012): hide the
    // native one — its title text too, or it draws over the shell's — and
    // keep the traffic lights over the full-size content view, whose title
    // bar keeps a leading inset clear for them (macTrafficLightsInset).
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.delegate = self

    super.awakeFromNib()
  }

  /// The red close button quits the app through the same path as ⌘Q, with the
  /// window still up: the editor asks "A game is running. Stop it and quit?"
  /// (spec 007, FR-015) in this window, which it cannot do once the window is
  /// gone, so the window stays until the app actually exits.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(sender)
    return false
  }
}
