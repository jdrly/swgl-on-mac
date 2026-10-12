// SWGLonMacSetup: the first-run welcome window (SwiftUI, Liquid Glass). Downloads the
// official SWGL launcher from SWGL's own URL, unpacks it into the game folder and
// prepares the Wine prefix, then exits so the app can start the launcher. Never shown
// again once the launcher is in place.
//
//   SWGLonMacSetup <launcher zip URL> <game folder> <prepare command...>
//
// Exit status 0: ready to start the launcher. 1: the user quit.
// Runs from its own helper bundle, SWGL on Mac.app/Contents/Helpers/SWGL on Mac Setup.app
// (same name and icon, separate bundle ID). Run from the app's own Contents/MacOS, macOS
// would register it as the app and treat its exit as the app quitting, leaving the
// launcher that follows without the app's identity ("java" in the menu bar). Credits
// come from the app's Resources/app.properties.

import AppKit
import SwiftUI

// MARK: - Model

@MainActor @Observable
final class Setup {
  enum Phase: Equatable {
    case intro
    case downloading(received: Int64, expected: Int64)
    case unpacking
    case preparing
    case failed(String, retry: Retry)
    case done
  }
  enum Retry { case download, prepare }

  let zipURL: URL
  let gameFolder: URL
  let prepareCommand: [String]
  let credits: [String: String]
  var phase: Phase = .intro

  private var download: Download?

  init(arguments: [String]) {
    zipURL = URL(string: arguments[1])!
    gameFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
    prepareCommand = Array(arguments.dropFirst(3))
    let appResources = Bundle.main.bundleURL           // …/Contents/Helpers/SWGL on Mac Setup.app
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    credits = Setup.readProperties(appResources.appendingPathComponent("app.properties"))
  }

  var isBusy: Bool { phase == .unpacking || phase == .preparing }

  func start() {
    phase = .downloading(received: 0, expected: 0)
    let target = gameFolder.deletingLastPathComponent().appendingPathComponent("SWGLegendsLauncher.zip.download")
    download = Download(url: zipURL, saveTo: target) { [weak self] received, expected in
      self?.phase = .downloading(received: received, expected: expected)
    } completion: { [weak self] result in
      guard let self else { return }
      self.download = nil
      switch result {
      case .success(let zip): Task { await self.unpack(zip) }
      case .failure(let error as URLError) where error.code == .cancelled: self.phase = .intro
      case .failure(let error): self.phase = .failed("The download failed: \(error.localizedDescription)", retry: .download)
      }
    }
  }

  func cancel() {
    download?.cancel()
  }

  func retry(_ what: Retry) {
    switch what {
    case .download: start()
    case .prepare: Task { await prepare() }
    }
  }

  private func unpack(_ zip: URL) async {
    phase = .unpacking
    try? FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
    // lib/jre is a Windows Java runtime; the app runs the launcher on its own Java.
    let status = await run("/usr/bin/unzip", ["-q", "-n", zip.path, "-x", "lib/jre/*", "-d", gameFolder.path])
    try? FileManager.default.removeItem(at: zip)
    let exe = gameFolder.appendingPathComponent("SWGLegendsLauncher.exe")
    guard status == 0, FileManager.default.fileExists(atPath: exe.path) else {
      phase = .failed("The launcher could not be unpacked. Try downloading it again.", retry: .download)
      return
    }
    await prepare()
  }

  private func prepare() async {
    if let command = prepareCommand.first {
      phase = .preparing
      guard await run(command, Array(prepareCommand.dropFirst())) == 0 else {
        phase = .failed("Setup could not be completed. "
                        + "Details are in ~/Library/Logs/SWGLonMac/app.log.", retry: .prepare)
        return
      }
    }
    phase = .done
    try? await Task.sleep(for: .milliseconds(900))
    exit(0)
  }

  private func run(_ path: String, _ arguments: [String]) async -> Int32 {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      process.standardInput = FileHandle.nullDevice
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(returning: -1) }
    }
  }

  // Resources/app.properties (written by build.sh): version, author, github, repo.
  private static func readProperties(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
      guard let eq = line.firstIndex(of: "=") else { continue }
      values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
  }
}

// URLSession download with progress, moved to `saveTo` before the temporary file goes away.
final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let saveTo: URL
  private let progress: @MainActor (Int64, Int64) -> Void
  private let completion: @MainActor (Result<URL, Error>) -> Void
  private var session: URLSession!
  private var task: URLSessionDownloadTask!
  private var saved: URL?

  init(url: URL, saveTo: URL,
       progress: @escaping @MainActor (Int64, Int64) -> Void,
       completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
    self.saveTo = saveTo
    self.progress = progress
    self.completion = completion
    super.init()
    session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
    task = session.downloadTask(with: url)
    task.resume()
  }

  func cancel() { task.cancel() }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    MainActor.assumeIsolated { progress(totalBytesWritten, totalBytesExpectedToWrite) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { return }
    try? FileManager.default.createDirectory(at: saveTo.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: saveTo)
    if (try? FileManager.default.moveItem(at: location, to: saveTo)) != nil { saved = saveTo }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    let result: Result<URL, Error>
    if let error {
      result = .failure(error)
    } else if status != 200 {
      result = .failure(NSError(domain: "SWGLonMac", code: status, userInfo: [
        NSLocalizedDescriptionKey: "the server answered HTTP \(status). Try again later."]))
    } else if let saved {
      result = .success(saved)
    } else {
      result = .failure(NSError(domain: "SWGLonMac", code: 0, userInfo: [
        NSLocalizedDescriptionKey: "the file could not be saved."]))
    }
    session.finishTasksAndInvalidate()
    MainActor.assumeIsolated { completion(result) }
  }
}

// MARK: - Views

struct WelcomeView: View {
  let setup: Setup

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 112, height: 112)
        VStack(spacing: 6) {
          Text("Welcome to SWGL on Mac")
            .font(.title.weight(.semibold))
          Text("To get started, SWGL on Mac downloads the official SWG Legends launcher from "
               + "swglegends.com and prepares everything it needs. The launcher then installs "
               + "the game and keeps it up to date.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Label((setup.gameFolder.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
          .font(.callout)
          .foregroundStyle(.tertiary)

        StatusCard(setup: setup)
          .padding(.top, 6)

        Buttons(setup: setup)
          .padding(.top, 4)
      }
      .padding(.horizontal, 40)
      .padding(.top, 34)
      .padding(.bottom, 26)

      Footer(credits: setup.credits)
    }
    .frame(width: 540)
    .animation(.smooth, value: setup.phase)
  }
}

struct StatusCard: View {
  let setup: Setup

  var body: some View {
    Group {
      switch setup.phase {
      case .intro:
        EmptyView()
      case .downloading(let received, let expected):
        card {
          if expected > 0 {
            ProgressView(value: Double(received), total: Double(expected))
          } else {
            ProgressView().progressViewStyle(.linear)
          }
          Text(expected > 0
               ? "Downloading the SWG Legends launcher… \(mb(received)) of \(mb(expected))"
               : "Connecting to swglegends.com…")
        }
      case .unpacking:
        card { ProgressView().progressViewStyle(.linear); Text("Unpacking the launcher…") }
      case .preparing:
        card {
          ProgressView().progressViewStyle(.linear)
          Text("Getting everything ready… (first launch only, about a minute)")
        }
      case .failed(let message, _):
        card {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
        }
      case .done:
        card { Label("All set. Starting the launcher…", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
      }
    }
    .transition(.blurReplace)
  }

  private func card(@ViewBuilder _ content: () -> some View) -> some View {
    VStack(spacing: 10) { content() }
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(16)
      .frame(maxWidth: .infinity)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
  }

  private func mb(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct Buttons: View {
  let setup: Setup

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 12) {
        switch setup.phase {
        case .intro:
          quit
          Button("Download Launcher") { setup.start() }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        case .downloading:
          Button("Cancel") { setup.cancel() }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
        case .failed(_, let retry):
          quit
          Button("Try Again") { setup.retry(retry) }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        case .unpacking, .preparing, .done:
          EmptyView()
        }
      }
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }

  private var quit: some View {
    Button("Quit") { NSApp.terminate(nil) }
      .buttonStyle(.glass)
      .keyboardShortcut(.cancelAction)
  }
}

struct Footer: View {
  let credits: [String: String]

  var body: some View {
    VStack(spacing: 4) {
      Text("Unofficial. Not affiliated with or endorsed by the SWGL team.")
      HStack(spacing: 6) {
        Text("Developed by \(credits["author"] ?? "Jan Drlý")")
        if let link {
          Text("·")
          Link(link.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: link)
            .foregroundStyle(.link)
            .pointerStyle(.link)
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }

  // The repository once it is public, the author's profile until then.
  private var link: URL? {
    let repo = credits["repo"] ?? "", github = credits["github"] ?? ""
    return URL(string: repo.isEmpty ? github : repo).flatMap { $0.host == nil ? nil : $0 }
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
  var setup: Setup?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  // Quitting before the launcher is ready ends the app (exit status 1); while unpacking or
  // preparing it waits, so the game folder and the prefix are never left half done.
  @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let setup else { exit(1) }
    if setup.isBusy { return .terminateCancel }
    setup.cancel()
    exit(setup.phase == .done ? 0 : 1)
  }
}

@main
struct SetupApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  // The App value is created once, so it can own the model directly (no @State, whose
  // macro plugin only ships with Xcode, not the Command Line Tools).
  private let setup: Setup

  init() {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else {
      FileHandle.standardError.write(Data("usage: SWGLonMacSetup <launcher zip URL> <game folder> [prepare command...]\n".utf8))
      exit(2)
    }
    setup = Setup(arguments: arguments)
  }

  var body: some Scene {
    Window("Welcome to SWGL on Mac", id: "welcome") {
      WelcomeView(setup: setup)
        .onAppear {
          delegate.setup = setup
          NSApp.activate()
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .commands { CommandGroup(replacing: .newItem) {} }
  }
}
