import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let masterFd: Int32

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
            PTYManager.resize(masterFd: masterFd, cols: UInt16(newCols), rows: UInt16(newRows))
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
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
        terminalView.configureNativeColors()
        context.coordinator.startReading(terminalView: terminalView)
        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        if context.coordinator.masterFd != masterFd {
            context.coordinator.cleanup()
            context.coordinator.masterFd = masterFd
            context.coordinator.startReading(terminalView: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
}
