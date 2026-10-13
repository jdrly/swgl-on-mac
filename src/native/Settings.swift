// SWGLonMacSettings: the Settings window (SwiftUI, Liquid Glass), opened from the launcher's
// SWGL on Mac → Settings… (⌘,). Reads and writes settings.conf through the app's
// Resources/settings.sh, like the maintenance menu.
//
//   SWGLonMacSettings [launcher pid]
//
// Its own helper bundle, SWGL on Mac.app/Contents/Helpers/SWGL on Mac Settings.app, built
// against the current SDK: the launcher's Java is linked against the macOS 11 SDK, so a
// window in its process would get the old design. An accessory app (LSUIElement): no Dock
// icon, and the launcher's menus stay in the menu bar. It quits with its window, or when
// the launcher it was opened from quits.

import AppKit
import SwiftUI

// MARK: - Model

@MainActor @Observable
final class Settings {
  // Mouse-look speed: Windows mickeys per mouse count (MOUSE_SPEED in common.sh).
  static let speedLimits = 0.1...10.0
  static let sliderLimits = 0.25...4.0

  private let script: URL
  private(set) var values: [String: String] = [:]
  private var pendingSpeed: Task<Void, Never>?
  // settings.sh rewrites the whole file, so its runs must not overlap.
  private let saves = DispatchQueue(label: "io.github.jdrly.swglonmac.settings.save")

  init() {
    let resources = Bundle.main.bundleURL           // …/Contents/Helpers/SWGL on Mac Settings.app
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    script = resources.appendingPathComponent("settings.sh")
    values = Settings.parse(Settings.run(script, []))
  }

  func toggle(_ key: String) -> Binding<Bool> {
    Binding(get: { self.values[key] == "on" },
            set: { self.save(key, $0 ? "on" : "off") })
  }

  var mouseSpeed: Double {
    get { Double(values["MOUSE_SPEED"] ?? "") ?? 1 }
    set {
      let value = Settings.format(min(max(newValue, Settings.speedLimits.lowerBound), Settings.speedLimits.upperBound))
      values["MOUSE_SPEED"] = value
      // A slider drag changes it many times a second; save once it settles.
      pendingSpeed?.cancel()
      pendingSpeed = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        self.save("MOUSE_SPEED", value)
      }
    }
  }

  // The slider runs on a log scale, so 1× sits in the middle and halving and doubling are
  // the same distance; it snaps to 0.05.
  var mouseSpeedSlider: Double {
    get { log2(min(max(mouseSpeed, Settings.sliderLimits.lowerBound), Settings.sliderLimits.upperBound)) }
    set { mouseSpeed = (pow(2, newValue) * 20).rounded() / 20 }
  }

  private func save(_ key: String, _ value: String) {
    values[key] = value
    let script = script
    saves.async {
      let output = Settings.run(script, [key, value])
      if output.isEmpty { NSLog("SWGL on Mac: could not save %@=%@", key, value) }
    }
  }

  static func format(_ speed: Double) -> String {
    var text = String(format: "%.2f", speed)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }

  // settings.sh prints KEY=value lines; with "KEY value" it changes one setting first.
  nonisolated private static func run(_ script: URL, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    guard (try? process.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
  }

  private static func parse(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
      guard let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
      values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
  }
}

// MARK: - Views

struct SettingsView: View {
  @Bindable var settings: Settings

  var body: some View {
    Form {
      Section("Graphics") {
        Toggle(isOn: settings.toggle("RETINA")) {
          Text("Retina Mode")
          Text("Renders the game at your display's full resolution. Sharper, at some cost in frame rate.")
        }
        Toggle(isOn: settings.toggle("FPS_HUD")) {
          Text("Show Metal HUD")
          Text("Apple's overlay with the frame rate and GPU details, over the game.")
        }
      }

      Section("Game") {
        Toggle(isOn: settings.toggle("GAME_MODE")) {
          Text("Game Mode")
          Text("While the game is in full screen, macOS gives it priority on the CPU and GPU and "
               + "lowers the latency of Bluetooth controllers and headphones.")
        }
      }

      Section("Mouse") {
        MouseSpeedRow(settings: settings)
      }

      Section("Troubleshooting") {
        Toggle(isOn: settings.toggle("DEBUG")) {
          Text("Debug Mode")
          Text("Much more detailed logs for bug reports, at some cost in performance. Turn it on "
               + "only when asked to, and off again afterwards.")
        }
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Text("Changes apply the next time the game starts.")
        .font(.callout)
        .foregroundStyle(.red)
        .padding(.bottom, 18)
    }
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct MouseSpeedRow: View {
  @Bindable var settings: Settings

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Mouse-Look Speed")
          Text("How fast the camera turns when you steer with the mouse. At 1× it turns as fast as "
               + "on Windows; the in-game mouse sensitivity applies on top.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 16)
        // As wide as the widest value, so the description doesn't rewrap while dragging.
        Text("0.00×")
          .monospacedDigit()
          .hidden()
          .overlay(alignment: .trailing) {
            Text(Settings.format(settings.mouseSpeed) + "×")
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .contentTransition(.numericText(value: settings.mouseSpeed))
              .animation(.snappy, value: settings.mouseSpeed)
          }
      }
      HStack(alignment: .top, spacing: 12) {
        // Ticks at halvings and doublings, evenly spaced on the log scale; the fill grows
        // from 1×.
        Slider(value: $settings.mouseSpeedSlider,
               in: log2(Settings.sliderLimits.lowerBound)...log2(Settings.sliderLimits.upperBound),
               neutralValue: 0) {
          Text("Mouse-Look Speed")
        } ticks: {
          SliderTick("0.25×", -2.0)
          SliderTick("0.5×", -1.0)
          SliderTick("1×", 0.0)
          SliderTick("2×", 1.0)
          SliderTick("4×", 2.0)
        }
        .labelsHidden()
        Button("Reset") { settings.mouseSpeed = 1 }
          .buttonStyle(.glass)
          .pointerStyle(.link)
          .disabled(settings.mouseSpeed == 1)
          .help("Back to 1×, the same speed as on Windows")
      }
    }
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var launcherExit: DispatchSourceProcess?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  // Opened from the launcher: go when it does.
  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = CommandLine.arguments
    guard arguments.count > 1, let pid = pid_t(arguments[1]), pid > 0 else { return }
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    launcherExit = source
    if kill(pid, 0) != 0 { NSApp.terminate(nil) }
  }
}

@main
struct SettingsApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  // The App value is created once, so it can own the model directly.
  private let settings = Settings()

  var body: some Scene {
    Window("SWGL on Mac Settings", id: "settings") {
      SettingsView(settings: settings)
        .onAppear { NSApp.activate() }
    }
    .windowResizability(.contentSize)
    .commands { CommandGroup(replacing: .newItem) {} }
  }
}
