// The app-update window (SwiftUI, Liquid Glass), part of libswglmenus.dylib in the launcher's
// Java process. src/native/swglupdates.m drives it from Sparkle's user-driver callbacks and
// keeps Sparkle's types to itself; this file only knows what to show.
//
// The launcher's java claims the current SDK (build.sh), so AppKit and SwiftUI give this
// window the current design; Sparkle's own windows looked dated next to the rest of the app.

import AppKit
import SwiftUI

// MARK: - Model

@MainActor @Observable
final class UpdateModel {
  enum Phase: Equatable {
    case checking
    case found
    case downloading(received: UInt64, expected: UInt64)
    case extracting(Double)
    case ready
    case installing
    case held
    case upToDate(String)
    case failed(String)
  }

  // What the update window offers for a found update (stage: Sparkle's notDownloaded,
  // downloaded or installing).
  struct Update: Equatable {
    var version: String
    var notes: String
    var notesFormat: String  // "markdown", "html" or "plain"
    var readyToInstall: Bool
  }

  let currentVersion: String
  let icon: NSImage
  var phase: Phase = .checking
  var update: Update?

  // The pending Sparkle reply or acknowledgement for the buttons on screen.
  var onInstall: (() -> Void)?
  var onLater: (() -> Void)?
  var onSkip: (() -> Void)?
  var onCancel: (() -> Void)?
  var onAcknowledge: (() -> Void)?

  init(currentVersion: String, icon: NSImage) {
    self.currentVersion = currentVersion
    self.icon = icon
  }

  func clearActions() {
    onInstall = nil; onLater = nil; onSkip = nil; onCancel = nil; onAcknowledge = nil
  }
}

// MARK: - Window controller (called from Objective-C)

// Public so the generated Objective-C header (SWGLMenus-Swift.h) declares it.
@objc(SWGLUpdateWindow)
@MainActor
public final class UpdateWindow: NSObject, NSWindowDelegate {
  private let model: UpdateModel
  private var window: NSWindow?

  // iconPath: the app's AppIcon.icns (the process's own icon is Java's).
  @objc public init(currentVersion: String, iconPath: String) {
    model = UpdateModel(currentVersion: currentVersion,
                        icon: NSImage(contentsOfFile: iconPath) ?? NSApp.applicationIconImage)
    super.init()
  }

  // Sparkle's choices as plain values: install 0, later 1, skip 2.
  @objc public func showChecking(cancel: @escaping () -> Void) {
    model.clearActions()
    model.update = nil
    model.onCancel = cancel
    show(.checking)
  }

  @objc public func showFound(version: String, notes: String, notesFormat: String, readyToInstall: Bool,
                       reply: @escaping (Int) -> Void) {
    model.clearActions()
    model.update = .init(version: version, notes: notes, notesFormat: notesFormat, readyToInstall: readyToInstall)
    var replied = false
    let once: (Int) -> Void = { choice in
      guard !replied else { return }
      replied = true
      reply(choice)
    }
    model.onInstall = { once(0) }
    model.onLater = { once(1) }
    model.onSkip = { once(2) }
    show(.found)
  }

  // Release notes Sparkle downloaded separately (an item with a release notes link).
  @objc public func showNotes(_ notes: String, format: String) {
    model.update?.notes = notes
    model.update?.notesFormat = format
  }

  @objc public func showDownloading(cancel: @escaping () -> Void) {
    model.clearActions()
    model.onCancel = cancel
    show(.downloading(received: 0, expected: 0))
  }

  @objc public func setExpectedLength(_ expected: UInt64) {
    if case .downloading(let received, _) = model.phase { model.phase = .downloading(received: received, expected: expected) }
  }

  @objc public func addReceived(_ length: UInt64) {
    if case .downloading(let received, let expected) = model.phase {
      model.phase = .downloading(received: received + length, expected: expected)
    }
  }

  @objc public func showExtracting(_ progress: Double) {
    model.clearActions()
    show(.extracting(progress))
  }

  @objc public func showReadyToInstall(reply: @escaping (Int) -> Void) {
    model.clearActions()
    var replied = false
    model.onInstall = { if !replied { replied = true; reply(0) } }
    model.onLater = { if !replied { replied = true; reply(1) } }
    show(.ready)
  }

  // Install was chosen while the game runs (swglupdates.m holds it until the game quits).
  @objc public func showHeld() {
    model.clearActions()
    model.onAcknowledge = { [weak self] in self?.close() }
    show(.held)
  }

  @objc public func showInstalling() {
    model.clearActions()
    show(.installing)
  }

  @objc public func showUpToDate(_ message: String, acknowledge: @escaping () -> Void) {
    model.clearActions()
    model.onAcknowledge = { [weak self] in acknowledge(); self?.close() }
    show(.upToDate(message))
  }

  @objc public func showError(_ message: String, acknowledge: @escaping () -> Void) {
    model.clearActions()
    model.onAcknowledge = { [weak self] in acknowledge(); self?.close() }
    show(.failed(message))
  }

  @objc public func bringToFront() {
    guard let window else { return }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  @objc public func close() {
    model.clearActions()
    window?.delegate = nil
    window?.close()
    window = nil
  }

  private func show(_ phase: UpdateModel.Phase) {
    withAnimation(.smooth) { model.phase = phase }
    if window == nil {
      let hosting = NSHostingController(rootView: UpdateView(model: model))
      hosting.sizingOptions = [.preferredContentSize]
      let window = NSWindow(contentViewController: hosting)
      window.styleMask = [.titled, .closable, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.title = "Software Update"
      window.isReleasedWhenClosed = false
      window.delegate = self
      // Center at the content's real size; centred while still empty, the window would grow
      // from there and end up low on the screen.
      hosting.view.layoutSubtreeIfNeeded()
      window.setContentSize(hosting.view.fittingSize)
      window.center()
      self.window = window
    }
    bringToFront()
  }

  // The close button: whatever stands for "not now" in the current state.
  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    let action = model.onCancel ?? model.onLater ?? model.onAcknowledge
    model.clearActions()
    window = nil
    action?()
    return true
  }
}

// MARK: - Views

struct UpdateView: View {
  let model: UpdateModel

  var body: some View {
    VStack(spacing: 18) {
      Header(model: model)
      if let update = model.update, model.phase != .checking {
        NotesCard(update: update)
      }
      StatusCard(phase: model.phase)
      UpdateButtons(model: model)
    }
    .padding(.horizontal, 32)
    .padding(.top, 30)
    .padding(.bottom, 24)
    .frame(width: 540)
    .animation(.smooth, value: model.phase)
  }
}

private struct Header: View {
  let model: UpdateModel

  var body: some View {
    HStack(spacing: 16) {
      Image(nsImage: model.icon)
        .resizable()
        .frame(width: 64, height: 64)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title2.weight(.semibold))
        if let subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var title: String {
    switch model.phase {
    case .checking: "Checking for updates…"
    case .upToDate: "You're up to date"
    case .failed: "Couldn't update SWGL on Mac"
    default: "A new version of SWGL on Mac is available"
    }
  }

  private var subtitle: String? {
    switch model.phase {
    case .checking: nil
    case .upToDate(let message), .failed(let message): message
    default: model.update.map { "Version \($0.version). You have \(model.currentVersion)." }
    }
  }
}

private struct NotesCard: View {
  let update: UpdateModel.Update

  var body: some View {
    ScrollView {
      ReleaseNotes(text: update.notes, format: update.notesFormat)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }
    .frame(height: 220)
    .glassEffect(.regular, in: .rect(cornerRadius: 18))
  }
}

// The notes as release.sh embeds them (Markdown from release-notes/<version>.md): headings,
// bullet lists and paragraphs with inline formatting and links. HTML and plain text too.
private struct ReleaseNotes: View {
  let text: String
  let format: String

  var body: some View {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text("No release notes for this version.").foregroundStyle(.secondary)
    } else if format == "html" {
      Text(html)
    } else if format == "markdown" {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .heading(let level, let text):
            Text(inline(text))
              .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
              .padding(.top, 4)
          case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text("•").foregroundStyle(.secondary)
              Text(inline(text))
            }
          case .paragraph(let text):
            Text(inline(text))
          }
        }
      }
      .textSelection(.enabled)
    } else {
      Text(text).textSelection(.enabled)
    }
  }

  private enum Block { case heading(Int, String), bullet(String), paragraph(String) }

  private var blocks: [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    func flush() {
      if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
      paragraph = []
    }
    for raw in text.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flush()
      } else if line.hasPrefix("#") {
        flush()
        let level = line.prefix { $0 == "#" }.count
        blocks.append(.heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
        flush()
        blocks.append(.bullet(String(line.dropFirst(2))))
      } else if raw.hasPrefix("  "), case .bullet(let previous)? = blocks.last, paragraph.isEmpty {
        blocks[blocks.count - 1] = .bullet(previous + " " + line)  // a wrapped list item
      } else {
        paragraph.append(line)
      }
    }
    flush()
    return blocks
  }

  private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }

  private var html: AttributedString {
    guard let data = text.data(using: .utf8),
          let string = try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    else { return AttributedString(text) }
    return AttributedString(string.string)
  }
}

private struct StatusCard: View {
  let phase: UpdateModel.Phase

  var body: some View {
    Group {
      switch phase {
      case .checking:
        card { ProgressView().progressViewStyle(.linear) }
      case .downloading(let received, let expected):
        card {
          if expected > 0 {
            ProgressView(value: Double(received), total: Double(max(expected, received)))
            Text("Downloading the update… \(bytes(received)) of \(bytes(expected))")
          } else {
            ProgressView().progressViewStyle(.linear)
            Text("Downloading the update…")
          }
        }
      case .extracting(let progress):
        card {
          ProgressView(value: progress)
          Text("Preparing the update…")
        }
      case .ready:
        card { Label("The update is ready to install.", systemImage: "checkmark.circle.fill") }
      case .installing:
        card {
          ProgressView().progressViewStyle(.linear)
          Text("Installing the update. SWGL on Mac will open again in a moment.")
        }
      case .held:
        card {
          Label("The update will be installed when you quit the game. SWGL on Mac then opens "
                + "again by itself.", systemImage: "gamecontroller.fill")
            .multilineTextAlignment(.leading)
        }
      case .found, .upToDate, .failed:
        EmptyView()
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

  private func bytes(_ count: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }
}

private struct UpdateButtons: View {
  let model: UpdateModel

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 12) {
        if let skip = model.onSkip {
          Button("Skip This Version", action: skip)
            .buttonStyle(.glass)
        }
        Spacer(minLength: 0)
        if let cancel = model.onCancel {
          Button("Cancel", action: cancel)
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
        }
        if let later = model.onLater {
          Button("Remind Me Later", action: later)
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
        }
        if let install = model.onInstall {
          Button(model.phase == .ready || model.update?.readyToInstall == true
                 ? "Install and Relaunch" : "Install Update", action: install)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        if let acknowledge = model.onAcknowledge {
          Button("OK", action: acknowledge)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
      }
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }
}
