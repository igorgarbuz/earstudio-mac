# Protocol and reference provenance

Recorded on 2026-10-07. This document identifies the evidence supporting the independent Mac implementation and its limits. [Protocol.md](Protocol.md) describes command formats, layouts, firmware gates and remaining validation.

## Pinned research archive

- Private repository: [igorgarbuz/earstudio-research](https://github.com/igorgarbuz/earstudio-research).
- Evidence commit: [`1195d17b9c3ccdf27f0aae442c47550264c7c08b`](https://github.com/igorgarbuz/earstudio-research/tree/1195d17b9c3ccdf27f0aae442c47550264c7c08b).
- [Artifact manifest](https://github.com/igorgarbuz/earstudio-research/blob/1195d17b9c3ccdf27f0aae442c47550264c7c08b/artifact-manifest.json): sizes/SHA-256 for 289 files, comprising eight PDFs and 281 Android evidence files.
- [PDF catalog](https://github.com/igorgarbuz/earstudio-research/blob/1195d17b9c3ccdf27f0aae442c47550264c7c08b/docs/catalog.json): original filenames, titles, dates, metadata, scope and hashes.

The Mac build does not depend on this archive. Original evidence requires access to the private repository. Update the pinned commit deliberately when adding evidence; a moving branch alone does not identify which source supported a protocol conclusion.

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

The [Android archive description](https://github.com/igorgarbuz/earstudio-research/blob/1195d17b9c3ccdf27f0aae442c47550264c7c08b/android/1.9.0/README.md) explains scope: 181 reconstructed Java files, 86 disassemblies, decoded resources and selected original DEX/resource/manifest/native-library inputs. This is neither original compilable source nor a complete APK. Preserved DEX enables future independent extraction. Native libraries are references and never linked into the Mac app.

## Evidence-to-implementation map

Android paths below are relative to `android/1.9.0/analysis/` at the pinned commit. Consult the [decompiled directory](https://github.com/igorgarbuz/earstudio-research/tree/1195d17b9c3ccdf27f0aae442c47550264c7c08b/android/1.9.0/analysis/decompiled), including available paired disassemblies.

| Evidence | Android files | Mac interpretation |
| --- | --- | --- |
| Framing/transport | `decompiled/com_radsone_a_a_a_a.java`, `..._d.java`, `..._e.java`, `..._f.java` | [GAIA.swift](../Sources/Core/GAIA.swift), [BluetoothTransport.swift](../Sources/App/BluetoothTransport.swift) |
| Commands, units, response fields | `decompiled/com_radsone_a_a_a_b.java`, nested enums and `com_radsone_a_a_a_b.disassembly.txt` | [GAIA.swift](../Sources/Core/GAIA.swift), [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Authentication and connection | `decompiled/com_radsone_earstudio_c_a.java`, `com_radsone_earstudio_b_c.java`, related service/helpers | [StudioModel.swift](../Sources/App/StudioModel.swift), [DeviceKeyStore.swift](../Sources/App/DeviceKeyStore.swift) |
| EQ options/limits/gates | `decompiled/com_radsone_earstudio_activity_EQSettingActivity.java`, helpers, `com_radsone_earstudio_d_h.java`, `fragment_eq.xml`, `activity_eqsetting.xml` | [EqualizerView.swift](../Sources/UI/EqualizerView.swift), [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Android saved presets | `decompiled/com_radsone_earstudio_d_d.java`, EQ activity helpers | [EQPreset.swift](../Sources/Core/EQPreset.swift) |
| Microphone steps | `decompiled/com_radsone_earstudio_d_l.java` | [DeviceState.swift](../Sources/Core/DeviceState.swift) |
| Other controls and labels | Audio input/output, battery and miscellaneous activities; `strings.json` | [SettingsViews.swift](../Sources/UI/SettingsViews.swift), [StudioModel.swift](../Sources/App/StudioModel.swift) |

The [historical protocol extraction](https://github.com/igorgarbuz/earstudio-research/blob/1195d17b9c3ccdf27f0aae442c47550264c7c08b/android/1.9.0/analysis/protocol.json) is preserved unchanged. It omits implemented commands/layouts and retains early questions subsequently traced further; it is not the maintained specification.

## Resolving decompiler ambiguities

Reconstructed Java prints `1132462080` where float volume scaling is used. Disassembly's `const/high16` plus float operations identify its bits as `256.0`. Similarly, wide constant `4591870180066957722` is double `0.1` for EQ conversion. Treating the pseudocode integers literally would create incorrect packets. These interpretations were checked against the retained disassembly during documentation work.

The cancel handler emits decimal 769 (`0x0301`), supporting cancellation rather than an authentication-status query. The response dispatcher retains packed offsets and version branches for future audit. Static recovery establishes what this Android revision does, not universal device/firmware support.

## Reference PDF collection

The local `EarStudio ES100 Docs` folder was found under `Documents/Manuals`. Eight PDFs were copied without moving or altering the originals; original names and bytes were retained. Hashes were checked after copying and against staged Git blobs. No duplicate PDF content was found.

The collection contains two manuals and six Radsone technical notes on filtering, preamplifier use, single-ended performance, architecture/features, analog volume and DualDrive. **No standalone AK4375A or CSR8675 component datasheet was found in that folder.** The original-ES100 material dates mainly to 2017-2018 and does not establish MK2 board identity, firmware behavior or packet layouts.

Cover dates and metadata-derived dates are distinguished in the catalog. Original download URLs were not recoverable from the available copies. Opaque filenames were not converted into guessed URLs, and publisher contact links were not substituted for download locations.

Several PDFs have imperfect text/font mappings. Poppler omitted some headings, while Apple Quartz rendered the affected inspected covers correctly. Extracted text misread the performance-report cover year; visual inspection established 21 June 2017. Original PDFs were retained rather than repaired or re-exported.

Physical PDF page references for the manual: channel trim/output estimates 14, microphone preamp/loopback 15, saved EQ presets 16, filters/crossfeed 17, oversampling 18, ambient microphone 19. Its older-firmware requirements reveal additional minimums not currently encoded by the Mac; Protocol.md records that discrepancy. Manufacturer performance claims have not been independently reproduced.

## Reported hardware finding and concurrent work

During this task, concurrent changes appeared in the Mac workspace's README, app version settings, `StudioModel.swift`, `GAIA.swift` and tests. The README reports an ES100 firmware **2.0.2** session confirming connection/settings readback and EQ writes taking effect without a write acknowledgement. The local implementation adds explicit EQ readback confirmation and six additional constructed tests.

This is a report from concurrent work, not a hardware session performed by this documentation task. No raw capture, device model/revision record or device-key material was added to this archive. Broader firmware/MK2 validation and restart persistence are not established. Protocol.md separates the original committed source behavior from the concurrent local changes; these unrelated code/version/README edits are excluded from this documentation commit.

Future hardware evidence should record model, firmware, sanitized bytes, expected/observed behavior and scope before receiving a hardware-validated label. Keep actual keys and personal Bluetooth identifiers out of reference fixtures.

## Ownership and repository boundaries

The Mac is an independent Swift implementation. Authored documentation/source/tests are in `earstudio-mac`; unchanged vendor PDFs, Android binaries and reconstructed evidence are in private `earstudio-research`. No rights to redistribute vendor material are asserted. Neither archive access nor a future Mac open-source license automatically covers those originals; visibility changes require a separate decision.
