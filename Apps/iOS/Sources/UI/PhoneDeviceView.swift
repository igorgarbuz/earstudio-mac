import SwiftUI
import EarStudioCore
import EarStudioSession
import EarStudioUI

struct PhoneDeviceView: View {
    @EnvironmentObject private var model: IOSStudioModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    Text(session.phase == .disconnected ? (model.rememberedDevice?.name ?? session.deviceName) : session.deviceName).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if session.canEdit {
                        if dynamicTypeSize >= .xxxLarge {
                            VStack(alignment: .leading, spacing: 8) {
                                connectionStatus
                                batteryReadout
                            }
                        } else {
                            HStack(spacing: 16) {
                                connectionStatus
                                Spacer(minLength: 8)
                                batteryReadout
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        connectionStatus
                    }
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
                    if session.isBusy || model.scanning {
                        Button("Cancel connection", role: .cancel) { model.cancelConnection() }
                            .frame(minHeight: 44)
                    } else {
                        Button {
                            model.requestConnection()
                        } label: {
                            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
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
            Section("Device details") {
                PhoneReadout(title: "Input", value: session.canEdit ? session.state.inputName : "—")
                PhoneReadout(title: "Codec", value: session.canEdit && session.state.input > 1 ? session.state.codecName : "—")
                PhoneReadout(title: "Sample rate", value: session.canEdit ? session.state.rateName : "—")
                PhoneReadout(title: "Output mode", value: session.canEdit ? session.state.outputName : "—")
                PhoneReadout(title: "Firmware", value: session.state.firmware ?? "—")
            }
            if !session.isBusy && !model.scanning && (model.rememberedDevice != nil || session.phase == .connected) {
                Section {
                    Button("Change device") { model.changeDevice() }
                        .frame(minHeight: 44).accessibilityIdentifier("device.change")
                }
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
        .sheet(isPresented: $model.showDevicePicker, onDismiss: { model.stopDiscovery() }) { PhoneConnectionSheet() }
        .accessibilityIdentifier("screen.device")
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            if session.isBusy || model.scanning {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
                Text(model.scanning ? "Looking for EarStudio…" : session.phase.rawValue)
            } else {
                Image(systemName: session.canEdit ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                    .accessibilityHidden(true)
                Text(session.phase.rawValue)
            }
        }
        .font(.subheadline)
        .foregroundStyle(session.canEdit ? StudioTheme.green : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var batteryReadout: some View {
        if session.canEdit {
            PhoneBatteryReadout(level: session.state.loaded.contains(.battery) ? Int(session.state.battery) : nil)
        }
    }
}

private struct PhoneBatteryReadout: View {
    let level: Int?

    private var filledBars: Int {
        guard let level, level > 0 else { return 0 }
        return min(3, (level * 3 + 99) / 100)
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { bar in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.foreground)
                            .opacity(bar < filledBars ? 1 : 0.18)
                    }
                }
                .padding(3)
                .frame(width: 27, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1.5))
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: 6)
            }
            .accessibilityHidden(true)
            Text(level.map { "\($0)%" } ?? "—")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(level == nil ? Color.secondary : ((level ?? 100) <= 33 ? Color.orange : StudioTheme.green))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(level.map { "\($0) percent" } ?? "Updating")
        .accessibilityIdentifier("device.battery")
    }
}

private struct PhoneConnectionSheet: View {
    @EnvironmentObject private var model: IOSStudioModel
    @Environment(\.dismiss) private var dismiss

    private func connectionLabel(for device: IOSDevice) -> String {
        var label = "Connect to \(device.name)"
        if model.devices.filter({ $0.name == device.name }).count > 1 {
            label += ", device \(device.id.uuidString.suffix(6))"
        }
        if device.id == model.rememberedDevice?.id { label += ", last used" }
        return label
    }

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
                                    Text(device.id == model.rememberedDevice?.id ? "Last used · Tap to connect" : "Tap to connect")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if model.devices.filter({ $0.name == device.name }).count > 1 {
                                        Text("Device \(device.id.uuidString.suffix(6))")
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel(connectionLabel(for: device))
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
        .onDisappear { model.stopDiscovery() }
    }
}
