import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// A browser starting Sotto as its extension's native messaging host gets
  /// the relay below — no window, no Flutter engine.
  static func main() {
    if BridgeHost.isHostLaunch(CommandLine.arguments) {
      exit(BridgeHost.run())
    }
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// The Sotto Bridge native messaging host (the Windows twin is
/// windows/runner/native/bridge.cpp). Chrome / Edge start it with the
/// extension's origin as the argument, Firefox with the manifest path and the
/// extension id. It relays framed messages (4-byte length + JSON) between
/// the browser's stdin / stdout and the running app's Unix socket
/// (services/screen/bridge_transport.dart), and reconnects whenever Sotto
/// starts again. The socket lives in a 0700 folder, and the peer must be
/// the current user (getpeereid).
enum BridgeHost {
  static let maxFrame: UInt32 = 1024 * 1024
  static let firefoxId = "bridge@sotto.app"

  static func isHostLaunch(_ args: [String]) -> Bool {
    args.dropFirst().contains { $0.hasPrefix("chrome-extension://") || $0 == "--native-host" || $0 == firefoxId }
  }

  static var socketPath: String {
    NSHomeDirectory() + "/Library/Application Support/Sotto/bridge/bridge.sock"
  }

  private static let lock = NSLock()
  private static var socketFd: Int32 = -1

  static func run() -> Int32 {
    signal(SIGPIPE, SIG_IGN)
    Thread.detachNewThread { browserToApp() }
    appToBrowser()
    return 0
  }

  private static func readExact(_ fd: Int32, _ count: Int) -> [UInt8]? {
    var buffer = [UInt8](repeating: 0, count: count)
    var got = 0
    while got < count {
      let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, count - got) }
      if n < 0 && errno == EINTR { continue }
      if n <= 0 { return nil }
      got += n
    }
    return buffer
  }

  private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var sent = 0
    while sent < bytes.count {
      let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + sent, bytes.count - sent) }
      if n < 0 && errno == EINTR { continue }
      if n <= 0 { return false }
      sent += n
    }
    return true
  }

  /// One whole frame, prefix included; nil at the end or on a bad length.
  private static func readFrame(_ fd: Int32) -> [UInt8]? {
    guard let prefix = readExact(fd, 4) else { return nil }
    let size = UInt32(prefix[0]) | UInt32(prefix[1]) << 8 | UInt32(prefix[2]) << 16 | UInt32(prefix[3]) << 24
    guard size > 0, size <= maxFrame, let body = readExact(fd, Int(size)) else { return nil }
    return prefix + body
  }

  /// stdin → socket. A frame that arrives while Sotto isn't running is
  /// dropped (the request times out on the extension's side).
  private static func browserToApp() {
    while let frame = readFrame(STDIN_FILENO) {
      lock.lock()
      if socketFd >= 0 { _ = writeAll(socketFd, frame) }
      lock.unlock()
    }
    // The browser closed the port: done.
    exit(0)
  }

  private static func connectToApp() -> Int32 {
    while true {
      let fd = socket(AF_UNIX, SOCK_STREAM, 0)
      if fd >= 0 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        if path.count <= MemoryLayout.size(ofValue: addr.sun_path) {
          withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withUnsafeBytes { dst.copyMemory(from: $0) }
          }
          let length = socklen_t(MemoryLayout<sockaddr_un>.size)
          let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
          } == 0
          var uid: uid_t = 0
          var gid: gid_t = 0
          // The app at the other end must be this user's.
          if connected && getpeereid(fd, &uid, &gid) == 0 && uid == getuid() { return fd }
        }
        close(fd)
      }
      sleep(2)  // Sotto isn't running yet.
    }
  }

  /// Tells the extension whether Sotto is at the other end (its toolbar
  /// icon and popup show it). Only this thread writes to stdout.
  private static func sayConnected(_ connected: Bool) {
    let body = Array("{\"v\":1,\"event\":\"sotto\",\"connected\":\(connected)}".utf8)
    let size = UInt32(body.count)
    let prefix: [UInt8] = [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8(size >> 24)]
    if !writeAll(STDOUT_FILENO, prefix + body) { exit(0) }
  }

  /// socket → stdout, reconnecting when the app goes away.
  private static func appToBrowser() {
    while true {
      let fd = connectToApp()
      lock.lock()
      socketFd = fd
      lock.unlock()
      sayConnected(true)
      while let frame = readFrame(fd) {
        if !writeAll(STDOUT_FILENO, frame) { exit(0) }
      }
      lock.lock()
      socketFd = -1
      close(fd)
      lock.unlock()
      sayConnected(false)
      usleep(500_000)
    }
  }
}
