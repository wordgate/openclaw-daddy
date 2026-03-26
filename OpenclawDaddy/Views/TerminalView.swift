import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let masterFd: Int32
    var logWriter: ((Data) -> Void)?

    class Coordinator: NSObject, TerminalViewDelegate {
        var masterFd: Int32
        var readSource: DispatchSourceRead?
        var logWriter: ((Data) -> Void)?

        init(masterFd: Int32) {
            self.masterFd = masterFd
            super.init()
        }

        func startReading(terminalView: SwiftTerm.TerminalView) {
            let source = DispatchSource.makeReadSource(
                fileDescriptor: masterFd,
                queue: .global(qos: .userInteractive)
            )
            source.setEventHandler { [weak self, weak terminalView] in
                guard let self, let terminalView else { return }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = read(self.masterFd, &buffer, buffer.count)
                if bytesRead > 0 {
                    let data = buffer[0..<bytesRead]
                    self.logWriter?(Data(data))
                    DispatchQueue.main.async {
                        terminalView.feed(byteArray: data)
                    }
                } else {
                    // EOF or error (EIO when PTY slave exits) — cancel source to prevent busy loop
                    self.readSource?.cancel()
                    self.readSource = nil
                }
            }
            source.resume()
            self.readSource = source
        }

        func cleanup() {
            readSource?.cancel()
            readSource = nil
        }

        // MARK: - TerminalViewDelegate (all 10 required methods)

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0, masterFd >= 0 else { return }
            PTYManager.resize(masterFd: masterFd, cols: UInt16(newCols), rows: UInt16(newRows))
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            guard masterFd >= 0 else { return }
            let bytes = Array(data)
            bytes.withUnsafeBufferPointer { ptr in
                if let baseAddress = ptr.baseAddress {
                    write(masterFd, baseAddress, bytes.count)
                }
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        func bell(source: SwiftTerm.TerminalView) { NSSound.beep() }
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }
        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(masterFd: masterFd)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        Self.applyDarkTheme(to: terminalView)
        context.coordinator.logWriter = logWriter
        context.coordinator.startReading(terminalView: terminalView)
        return terminalView
    }

    /// Classic dark terminal theme — Tango Dark palette with Menlo font
    private static func applyDarkTheme(to tv: SwiftTerm.TerminalView) {
        tv.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1) // #1e1e1e
        tv.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1) // #d9d9d9
        tv.font = NSFont(name: "MenloRegular", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Tango Dark 16-color ANSI palette (standard + bright)
        func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
            SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
        }
        tv.installColors([
            // Standard 8
            c(0x00, 0x00, 0x00), // 0  Black
            c(0xCC, 0x00, 0x00), // 1  Red
            c(0x4E, 0x9A, 0x06), // 2  Green
            c(0xC4, 0xA0, 0x00), // 3  Yellow
            c(0x34, 0x65, 0xA4), // 4  Blue
            c(0x75, 0x50, 0x7B), // 5  Magenta
            c(0x06, 0x98, 0x9A), // 6  Cyan
            c(0xD3, 0xD7, 0xCF), // 7  White
            // Bright 8
            c(0x55, 0x57, 0x53), // 8  Bright Black
            c(0xEF, 0x29, 0x29), // 9  Bright Red
            c(0x8A, 0xE2, 0x34), // 10 Bright Green
            c(0xFC, 0xE9, 0x4F), // 11 Bright Yellow
            c(0x72, 0x9F, 0xCF), // 12 Bright Blue
            c(0xAD, 0x7F, 0xA8), // 13 Bright Magenta
            c(0x34, 0xE2, 0xE2), // 14 Bright Cyan
            c(0xEE, 0xEE, 0xEC), // 15 Bright White
        ])
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        if context.coordinator.masterFd != masterFd {
            context.coordinator.cleanup()
            context.coordinator.masterFd = masterFd
            context.coordinator.logWriter = logWriter
            context.coordinator.startReading(terminalView: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
}
