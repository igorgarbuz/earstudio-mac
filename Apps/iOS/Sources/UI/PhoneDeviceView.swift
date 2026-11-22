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
                    HStack(spacing: 8) {
                        if session.isBusy {
                            ProgressView().controlSize(.small)
                                .accessibilityHidden(true)
                            Text(session.phase.rawValue)
                        } else {
                            Label(session.phase.rawValue, systemImage: session.canEdit ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(session.canEdit ? StudioTheme.green : .secondary)
                    if session.phase == .confirmation {
                        Text("Briefly press the ES100 power button to authorize this app.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 8)
            } footer: {
                Text("The companion controls settings. Choose your audio output separately in iPhone Control Center.")
            }
            if session.phase != .connected {
                Section {
                    if session.isBusy {
                        Button("Cancel connection", role: .cancel) { session.cancelConfirmation(); model.stopDiscovery() }
                            .frame(minHeight: 44)
                    } else {
                        Button {
                            showingConnection = true
                        } label: {
                            Label("Find EarStudio", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("device.connect")
                    }
                }
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
            if session.phase == .connected {
                Section {
                    Button("Disconnect", role: .destructive) { model.disconnect() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("device.disconnect")
                }
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
                    Text(IOSStudioModel.compatibilityNotice)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Nearby devices") {
                    if model.scanning {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                                .accessibilityHidden(true)
                            Text(model.connectionMessage ?? "Looking for nearby EarStudio devices…")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let message = model.connectionMessage {
                        Text(message).font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if model.devices.isEmpty {
                        Text("No EarStudio found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { device in
                        Button {
                            model.connect(device)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hifispeaker")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Tap to connect").font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Connect to \(device.name)")
                        .accessibilityIdentifier("device.result.\(device.id)")
                    }
                }
                if !model.scanning {
                    Section {
                        Button("Search again") { model.startDiscovery() }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { model.startDiscovery() }
        .onDisappear { model.stopDiscovery() }
    }
}
