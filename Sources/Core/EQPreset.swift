import Foundation

struct EQPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var preamp: Double
    var bands: [Double]
    var q: Int
    var headroom: Int
    var analogCompensation: Bool

    static let flat = EQPreset(name: "Flat", preamp: 0, bands: Array(repeating: 0, count: 10), q: 5791, headroom: 1, analogCompensation: true)

    func validated() throws -> EQPreset {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              bands.count == 10, ([preamp] + bands).allSatisfy({ $0.isFinite && (-12...12).contains($0) }),
              [2896, 5791].contains(q), [1, 2].contains(headroom) else {
            throw PresetError.invalid
        }
        return self
    }
}

enum PresetError: LocalizedError {
    case invalid, tooLarge, unsupported, noPresets
    var errorDescription: String? {
        switch self {
        case .invalid: return "This preset has invalid EQ values. It needs ten bands between −12 and +12 dB."
        case .tooLarge: return "Choose a preset file smaller than 1 MB."
        case .unsupported: return "This file is not an EarStudio preset or Android preferences export."
        case .noPresets: return "No saved EarStudio EQ presets were found in this file."
        }
    }
}

struct PresetFile: Codable {
    var format = "earstudio-companion"
    var version = 1
    var presets: [EQPreset]
    static func decode(_ data: Data) throws -> [EQPreset] {
        guard data.count <= 1_048_576 else { throw PresetError.tooLarge }
        if let file = try? JSONDecoder().decode(PresetFile.self, from: data) {
            guard file.format == "earstudio-companion", file.version == 1 else { throw PresetError.unsupported }
            guard !file.presets.isEmpty, file.presets.count <= 500 else { throw PresetError.noPresets }
            return try file.presets.map { try $0.validated() }
        }
        let reader = AndroidPresetReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.isMap else { throw PresetError.unsupported }
        var presets: [EQPreset] = []
        for slot in 1...4 {
            guard let raw = reader.strings["radsone_eq_pre\(slot)"] else { continue }
            let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard parts.count == 11, parts.allSatisfy({ $0 != nil }) else { throw PresetError.invalid }
            let values = parts.compactMap { $0 }
            let preset = EQPreset(name: reader.strings["Preset_name_\(slot)"] ?? "Android preset \(slot)",
                                  preamp: values[0], bands: Array(values.dropFirst()), q: 5791,
                                  headroom: 1, analogCompensation: true)
            presets.append(try preset.validated())
        }
        guard !presets.isEmpty else { throw PresetError.noPresets }
        return presets
    }
}

private final class AndroidPresetReader: NSObject, XMLParserDelegate {
    var strings: [String: String] = [:]
    var isMap = false
    private var key: String?
    private var value = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "map" { isMap = true }
        if elementName == "string" { key = attributeDict["name"]; value = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if key != nil { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "string", let key { strings[key] = value; self.key = nil }
    }
}

enum EQResponse {
    /// Visual estimate using peaking biquads. Device firmware remains the audio processor.
    static func decibels(at frequency: Double, gains: [Double], preamp: Double, q: Double, sampleRate: Double = 48_000) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        var sum = preamp
        for (f, gain) in zip(DeviceState.frequencies, gains) {
            let w0 = 2 * Double.pi * f / sampleRate
            let a = pow(10, gain / 40), alpha = sin(w0) / (2 * q)
            let b = [1 + alpha * a, -2 * cos(w0), 1 - alpha * a]
            let d = [1 + alpha / a, -2 * cos(w0), 1 - alpha / a]
            func power(_ c: [Double]) -> Double {
                pow(c[0] + c[1] * cos(w) + c[2] * cos(2 * w), 2) +
                pow(-c[1] * sin(w) - c[2] * sin(2 * w), 2)
            }
            sum += 10 * log10(max(1e-20, power(b)) / max(1e-20, power(d)))
        }
        return sum
    }
}
