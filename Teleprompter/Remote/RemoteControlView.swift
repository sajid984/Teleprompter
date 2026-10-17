import CoreImage.CIFilterBuiltins
import SwiftUI

/// Turns the web remote on or off and shows how to connect: address, QR code and pairing code.
struct RemoteControlView: View {
    @Environment(RemoteServer.self) private var server
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var server = server
        NavigationStack {
            Form {
                Section {
                    Toggle("Allow remote control", isOn: $server.isEnabled)
                } footer: {
                    Text("Control the prompter from a Mac, iPhone or another iPad on the same Wi-Fi, using Safari or Chrome. Only devices on your local network can connect, and they need the code below. Nothing goes over the internet.")
                }

                if server.isEnabled {
                    statusSection
                }
            }
            .navigationTitle("Remote Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { server.refreshAddresses() }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch server.status {
        case .running:
            if let display = server.displayURL, let pairing = server.pairingURL {
                Section("On your Mac or iPhone, open") {
                    HStack {
                        Text(display)
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = display
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    LabeledContent("Code") {
                        Text(server.code)
                            .font(.title.monospacedDigit().weight(.bold))
                            .kerning(4)
                            .foregroundStyle(.primary)
                    }
                    LabeledContent("Connected devices", value: "\(server.connectedDevices)")
                }

                Section {
                    HStack {
                        Spacer()
                        if let image = Self.qrImage(for: pairing) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 220, height: 220)
                                .padding(12)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("QR code for the remote control page")
                        }
                        Spacer()
                    }
                } header: {
                    Text("iPhone: scan with the Camera")
                } footer: {
                    Text("The QR code already contains the code, so the iPhone connects straight away.")
                }

                Section {
                    Button("Make a new code", role: .destructive) { server.newCode() }
                } footer: {
                    Text("Devices using the old code are disconnected until they enter the new one.")
                }
            } else {
                Section {
                    Label("Connect the iPad to Wi-Fi to use the remote.", systemImage: "wifi.exclamationmark")
                }
            }
        case .starting:
            Section { ProgressView("Starting…") }
        case .waiting(let message), .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
            } footer: {
                Text("If iOS asked for Local Network access, allow it in Settings → Privacy & Security → Local Network → Teleprompter.")
            }
        case .off:
            Section { Text("The remote is paused while the app is in the background.") }
        }
    }

    private static func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
