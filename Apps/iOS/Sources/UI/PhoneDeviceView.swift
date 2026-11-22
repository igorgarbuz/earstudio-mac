import SwiftUI
import EarStudioCore
import EarStudioSession
import EarStudioUI

struct PhoneDeviceView: View {
    @EnvironmentObject private var model: IOSStudioModel
    @State private var showingConnection = false
    private var session: DeviceSession { model.session }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    DeviceImage()
                        .frame(height: 165)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityHidden(true)
                    Text("ES100 / ES100 MK2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudioTheme.green)
                    Text(session.deviceName).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Label(session.phase.rawValue, systemImage: session.canEdit ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundStyle(session.canEdit ? StudioTheme.green : .secondary)
                    if session.isBusy {
                        ProgressView().accessibilityLabel(session.phase.rawValue)
                    }
                    if session.phase == .confirmation {
                        Text("Briefly press the ES100 power button to authorize this app.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                if session.isBusy {
                    Button("Cancel connection", role: .cancel) { session.cancelConfirmation(); model.stopDiscovery() }
                        .frame(minHeight: 44)
                } else if session.phase == .connected {
                    Button("Refresh settings") { session.refresh() }.frame(minHeight: 44)
                    Button("Disconnect", role: .destructive) { model.disconnect() }.frame(minHeight: 44)
                } else {
                    Button {
                        showingConnection = true
                    } label: {
                        Label("Find EarStudio", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("device.connect")
                }
            } footer: {
                Text("The companion controls settings. Choose your audio output separately in iPhone Control Center.")
            }
            SessionMessageSection()
            Section("Analog volume") {
                PhoneSlider(title: "Headphone volume", value: session.doubleBinding(\.volume, .volume, range: -60...6), range: -60...6, identifier: "device.volume")
                    .disabled(!session.available(.audio, .volume))
                Toggle("Mute", isOn: session.boolBinding(\.muted, .mute))
                    .disabled(!session.available(.audio, .mute))
            }
            Section("Signal & battery") {
                PhoneReadout(title: "Input", value: session.canEdit ? session.state.inputName : "—")
                PhoneReadout(title: "Codec", value: session.canEdit && session.state.input > 1 ? session.state.codecName : "—")
                PhoneReadout(title: "Sample rate", value: session.canEdit ? session.state.rateName : "—")
                PhoneReadout(title: "Output mode", value: session.canEdit ? session.state.outputName : "—")
                PhoneReadout(title: "Battery", value: session.state.loaded.contains(.battery) ? "\(session.state.battery)%" : "—")
                PhoneReadout(title: "Firmware", value: session.state.firmware ?? "—")
            }
        }
        .navigationTitle("ES100 Control")
        .sheet(isPresented: $showingConnection) { PhoneConnectionSheet() }
        .accessibilityIdentifier("screen.device")
    }
}

private struct PhoneConnectionSheet: View {
    @EnvironmentObject private var model: IOSStudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(IOSStudioModel.compatibilityNotice).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Turn on your EarStudio and keep it nearby. Close other EarStudio controllers before connecting.")
                        .fixedSize(horizontal: false, vertical: true)
                    if model.scanning { ProgressView("Looking for EarStudio…") }
                    if let message = model.connectionMessage {
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Nearby devices") {
                    if model.devices.isEmpty {
                        Text(model.scanning ? "Waiting for a device…" : "No EarStudio found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { device in
                        Button {
                            model.connect(device)
                            dismiss()
                        } label: {
                            Label(device.name, systemImage: "hifispeaker")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("device.result.\(device.id)")
                    }
                }
                Section {
                    Button("Search again") { model.startDiscovery() }
                        .frame(minHeight: 44).disabled(model.scanning)
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { model.startDiscovery() }
        .onDisappear { model.stopDiscovery() }
    }
}
