# Protocol and reference provenance

Recorded on 2026-10-07. This document identifies the evidence supporting the independent Mac implementation and its limits. [Protocol.md](Protocol.md) describes command formats, layouts, firmware gates and remaining validation.

## Preserved research evidence

Original Android artifacts and eight manufacturer PDFs are preserved separately in a private research archive, pinned to evidence commit `1195d17b9c3ccdf27f0aae442c47550264c7c08b`. Its artifact manifest records sizes and SHA-256 hashes for 289 files: eight PDFs and 281 Android evidence files. The PDF catalog records original filenames, titles, dates, metadata and hashes.

The Mac source, tests, authored documentation and vector artwork are independently authored. The README also links to eight unchanged manufacturer PDFs in `Docs/Reference` and uses the original Android app's product photo in `Docs/Images/es100.png`. These reference assets are third-party materials, outside the project's MIT license, and are not bundled into the release app. Android binaries and reconstructed Java remain in the private research archive. Access to that archive is not required to build or run the Mac app. Update the pinned evidence identity deliberately when adding research.

## Input identity and limitations

| Field | Recorded value |
| --- | --- |
| Android package | `com.radsone.earstudio` |
| App version / version code | `1.9.0` / `35` |
| DEX SHA-256 | `22a0f715938374a975f6fdcb69f3c7837dea2ae4acb1d64c4f811387dcde12ec` |
| Input form | Existing local unpacked Android app and static extraction |
| APK/store acquisition | Original APK, APK-level hash, store URL and acquisition details were not available in the inspected workspace |
| Extraction tools | Decompiler/version and original extraction scripts were not recorded; exact pseudocode regeneration is not claimed |
| Mac source baseline | [`012a059f778f6eb8951fa520fb589f6cac16e731`](https://github.com/igorgarbuz/earstudio-mac/tree/012a059f778f6eb8951fa520fb589f6cac16e731) |

The archived Android collection contains 181 reconstructed Java files, 86 disassemblies, decoded resources and selected original DEX/resource/manifest/native-library inputs. This is neither original compilable source nor a complete APK. Preserved DEX enables future independent extraction. Native libraries are references and never linked into the Mac app.

## Evidence-to-implementation map

The evidence filenames below identify records in the separately preserved Android analysis. Paired disassembly is used to resolve ambiguous reconstructed Java.

| Evidence | Android files | Mac interpretation |
| --- | --- | --- |
| Framing/transport | `decompiled/com_radsone_a_a_a_a.java`, `..._d.java`, `..._e.java`, `..._f.java` | [GAIA.swift](../Sources/Core/GAIA.swift), [BluetoothTransport.swift](../Sources/App/BluetoothTransport.swift) |
| Commands, units, response fields | `decompiled/com_radsone_a_a_a_b.java`, nested enums and `com_radsone_a_a_a_b.disassembly.txt` | [GAIA.swift](../Sources/Core/GAIA.swift), [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Authentication and connection | `decompiled/com_radsone_earstudio_c_a.java`, `com_radsone_earstudio_b_c.java`, related service/helpers | [StudioModel.swift](../Sources/App/StudioModel.swift), [DeviceKeyStore.swift](../Sources/App/DeviceKeyStore.swift) |
| EQ options/limits/gates | `decompiled/com_radsone_earstudio_activity_EQSettingActivity.java`, helpers, `com_radsone_earstudio_d_h.java`, `fragment_eq.xml`, `activity_eqsetting.xml` | [EqualizerView.swift](../Sources/UI/EqualizerView.swift), [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Single-band wire numbering | `decompiled/com_radsone_earstudio_b_c.java`, `com_radsone_earstudio_b_c$6.java` and paired disassembly, `com_radsone_earstudio_c_a.java`, command manager | IDs 1-10 on the wire; array index 0-9 locally. Version 1.0.3 corrects [GAIA.swift](../Sources/Core/GAIA.swift) and [StudioModel.swift](../Sources/App/StudioModel.swift) |
| Android saved presets | `decompiled/com_radsone_earstudio_d_d.java`, EQ activity helpers | [EQPreset.swift](../Sources/Core/EQPreset.swift) |
| Microphone steps | `decompiled/com_radsone_earstudio_d_l.java` | [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Other controls and labels | Audio input/output, battery and miscellaneous activities; `strings.json` | [SettingsViews.swift](../Sources/UI/SettingsViews.swift), [StudioModel.swift](../Sources/App/StudioModel.swift) |

The historical `protocol.json` extraction is preserved unchanged in the research archive. It omits implemented commands/layouts and retains early questions subsequently traced further; it is not the maintained specification.

## Resolving decompiler ambiguities

Reconstructed Java prints `1132462080` where float volume scaling is used. Disassembly's `const/high16` plus float operations identify its bits as `256.0`. Similarly, wide constant `4591870180066957722` is double `0.1` for EQ conversion. Treating the pseudocode integers literally would create incorrect packets. These interpretations were checked against the retained disassembly during documentation work.

The cancel handler emits decimal 769 (`0x0301`), supporting cancellation rather than an authentication-status query. The response dispatcher retains packed offsets and version branches for future audit. Static recovery establishes what this Android revision does, not universal device/firmware support.

Following the reported cross-band slider problem, the EQ fragment and seekbar listener were traced on 2026-10-07. The Android UI labels frequency controls with IDs 1-10, subtracts 1 only for its local DSP, and sends the unchanged ID to the single-band encoder. The earlier Mac mapping and protocol table incorrectly used zero-based device IDs. Constructed tests now cover all ten IDs and exercise real Mac bindings against an independent simulated device, including readback without write ACKs and rapid edits. This correction is based on static source/disassembly and simulated-device tests, not a new physical-device capture.

## Reference PDF collection

Eight supplied PDFs were preserved without altering their original names or bytes. Hashes were checked after copying and against archived Git blobs. No duplicate PDF content was found.

Copies are now linked directly from the [README's manuals and technical references](../README.md#manuals-and-technical-references). The copies in `Docs/Reference` have descriptive filenames; their bytes match the SHA-256 hashes recorded in the research archive's `docs/catalog.json`.

The collection contains two manuals and six Radsone technical notes on filtering, preamplifier use, single-ended performance, architecture/features, analog volume and DualDrive. **No standalone AK4375A or CSR8675 component datasheet was found in that folder.** The original-ES100 material dates mainly to 2017-2018 and does not establish MK2 board identity, firmware behavior or packet layouts.

Cover dates and metadata-derived dates are distinguished in the catalog. Original download URLs were not recoverable from the available copies. Opaque filenames were not converted into guessed URLs, and publisher contact links were not substituted for download locations.

Several PDFs have imperfect text/font mappings. Poppler omitted some headings, while Apple Quartz rendered the affected inspected covers correctly. Extracted text misread the performance-report cover year; visual inspection established 21 June 2017. Original PDFs were retained rather than repaired or re-exported.

Physical PDF page references for the manual: channel trim/output estimates 14, microphone preamp/loopback 15, saved EQ presets 16, filters/crossfeed 17, oversampling 18, ambient microphone 19. Its older-firmware requirements informed the additional minimum-version gates checked in the control audit; Protocol.md records the current gates and their evidence. Manufacturer performance claims have not been independently reproduced.

## Hardware reports and validation scope

An ES100 firmware **2.0.2** session confirmed connection/settings readback and reported EQ writes taking effect without a write acknowledgement. No raw capture or device model/revision record was preserved for that initial report. Broader firmware/MK2 validation and restart persistence are not established.

Hardware evidence should record model, firmware, sanitized bytes, expected/observed behavior and scope before receiving a hardware-validated label. Actual keys and personal Bluetooth identifiers must be excluded from fixtures.

The user subsequently reported that changing output volume audibly took effect while the Mac displayed "No reply to volume". Version 1.0.4 removes the requirement for a separate volume write ACK and confirms the system volume through the decoded `0x0010` state layout. Android's `a(Float)` encoder sends `0x0110` with signed 1/256 dB units; the state decoder and notification dispatcher supply distinct system/call/USB levels. Tests simulate omitted write ACKs, later queued volume/EQ edits, unchanged values and failed/truncated readbacks without Bluetooth or Keychain writes. No raw capture or new physical session was performed for this fix.

The 1.0.5 audit on 2026-10-07 extended confirmation to all exposed controls and corrected their readback groups, versioned layouts and firmware gates. [ControlAudit.md](ControlAudit.md) records each setting and the evidence scope. Its fixtures are literal transcriptions and independently edited simulated firmware packets, not hardware captures.

A physical read-only ES100 firmware 2.0.2 session was performed during this audit. SDP/RFCOMM stalled after app reopening while macOS Bluetooth audio remained connected. Disconnecting/reconnecting the EarStudio link through macOS restored control. Authentication and explicit queries `0000`, `0001`, `0010`, `0070`, `0050` then succeeded; the full information response contained 16 bytes. A later app relaunch reproduced the stalled open even on the correctly advertised channel 14. These observations support the full-information query and a stuck control-session recovery path, but do not prove its underlying OS/firmware cause. No EQ, volume, codec or other firmware-setting writes were performed. Personal addresses and authentication keys were excluded from the observation record. The new in-app baseband reset is additionally covered by injected recovery/cancellation/error tests; its physical validation is recorded separately in ControlAudit.md.

## Ownership and repository boundaries

The Mac is an independent Swift implementation. Authored documentation/source/tests are in `earstudio-mac`; Android binaries and reconstructed evidence remain in private `earstudio-research`. The Mac repository also includes reference copies of the eight vendor PDFs and the README product photo. The MIT license applies only to the independently authored Mac materials, not these third-party originals.

## In-app explanations and original artwork

The companion's Info page and contextual help are independently worded explanations based on the recovered Android 1.9.0 `analysis/strings.json` and drawable resources in the original unpacked workspace. They are available without connecting a device. The original's universal claims about balanced output, restored detail, and guaranteed audio improvement were not adopted.

| Companion help | Recovered string IDs |
| --- | --- |
| Balanced/single-ended wiring, jack detection, output lock | `0x7f08003b`–`0x7f080042` |
| Balanced-output comparison (rewritten with qualified language) | `0x7f080048`–`0x7f080049` |
| Four amplifier modes and high-voltage caution | `0x7f080141`–`0x7f080155` |
| Balanced pin order | `0x7f080166`–`0x7f080167` and `res/drawable/balanced_pin_map.png` (tip → sleeve: R−, R+, L+, L−) |
| Analog/source volume and local tones | `0x7f080032`–`0x7f080035`, `0x7f08019b`, `0x7f08019f`–`0x7f0801a0`, `0x7f0801a9` |
| EQ Q, headroom, and device persistence | `0x7f0800c6`–`0x7f0800ce` |
| DAC filter choices, oversampling, crossfeed, and DCT | `0x7f08008e`, `0x7f080091`–`0x7f080095`, `0x7f0800a8`–`0x7f0800ac`, `0x7f08015f` |
| Jitter troubleshooting | `0x7f0801a2` |
| Ambient/microphone/call loopback | `0x7f080030`, `0x7f080132`, `0x7f080134` |
| Battery care and self-powered mode | `0x7f08004c`–`0x7f08004d`, `0x7f080169`–`0x7f08016a` |

The current Mac source uses an original SwiftUI vector illustration of the device in `Sources/UI/Components.swift`; its green ring is decorative, while the adjacent status badge reports connection state. The app icon is also independently drawn by `Tools/generate_icon.swift`. The README instead uses an unchanged copy of the original Android resource `res/drawable-xxhdpi-v4/intro_earstudio.png`, matching the product photo requested by the user. That photo is third-party artwork and is not covered by the project's MIT license.
