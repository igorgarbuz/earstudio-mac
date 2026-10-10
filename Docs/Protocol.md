# EarStudio ES100 control protocol

This is the maintained interoperability description recovered from EarStudio Android **1.9.0 / version code 35**, and maintained for Companion 1.0.6. It is not a vendor specification. [Provenance.md](Provenance.md) pins the original evidence and distinguishes static recovery, constructed tests and firmware 2.0.2 hardware observations.

## Confidence and notation

- **S - static recovery:** read from reconstructed Android code or disassembly. Most transport, command and layout details below have this status.
- **B - bytecode checked:** a particular interpretation checked against disassembly, including the volume and EQ numeric scales.
- **I - implementation policy:** Mac queue scheduling, timeouts, defaults and error handling; these are not firmware requirements.
- **H - hardware evidence:** requires device/model/firmware and an observation record. The workspace README reports basic ES100 2.0.2 connection/readback and unacknowledged EQ writes, but this archive task has no raw capture or independently reproduced hardware session. Do not generalize that report to all commands or MK2 firmware.

All multi-byte values below are big-endian. `u8`/`u16` are unsigned; `s8`/`s16` are two's-complement signed. Response offsets `b[n]` refer to the **payload**, including status at `b[0]`, not the whole frame. The preserved early `analysis/protocol.json` is incomplete and is not authoritative over this document.

## Transport (S)

Android uses Bluetooth Classic RFCOMM / Serial Port Profile. The Mac uses `IOBluetoothRFCOMMChannel`, resolving the advertised channel with SDP rather than assuming a channel number.

| Service | UUID |
| --- | --- |
| Android SPP | `00001101-0000-1000-8000-00805F9B34FB` |
| Alternate GAIA service tried by the Mac | `00001107-D102-11E1-9B23-00025B00A5A5` |

The alternate service and availability across firmware remain test items. This Android evidence does not establish iOS transport or BLE characteristics. The control link is separate from Bluetooth/USB audio; the app does not route Mac audio or install a driver.

## GAIA v1 framing (S)

| Frame offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | Start `FF` |
| 1 | 1 | Version `01` |
| 2 | 1 | Flags; bit 0 enables XOR checksum |
| 3 | 1 | Payload length `N`, excluding header/checksum; encoder maximum 254 |
| 4 | 2 | Vendor `A5 5A` (`0xA55A`) |
| 6 | 2 | Command ID |
| 8 | N | Payload |
| 8 + N | 0 or 1 | Optional XOR of every preceding frame byte |

Length is `8 + N + (flags & 1)`. A checksummed frame has XOR zero over all bytes, including checksum. Android and the Mac send flags `00`; the Mac decoder accepts flags `00`/`01`, rejecting other bits, wrong versions, oversized declared payloads and corrupt checksums.

RFCOMM callbacks can split or combine frames. `GAIAStreamDecoder` preserves partial data and resynchronizes after malformed input. A callback boundary is not a packet boundary.

The command high bit `0x8000` marks a device reply/notification; the base ID is `command & 0x7FFF`. Its first payload byte is status: `00` means success. The Mac treats a queued command's status `01` as unsupported for that session; other nonzero statuses fail the transaction. A full status enumeration is not documented here. Host command payloads do not include status.

## Authentication and initialization (S, with I timing)

1. After opening RFCOMM, send `0x0300` with the saved `u16` device key, or `0000` if none exists.
2. Successful `0x0302` indicates physical power-button confirmation is required.
3. Successful `0x0303` supplies `[status, key_hi, key_lo]`; the Mac remembers the key in a local Application Support file and begins readback. Unchanged keys are not rewritten. Storage is a Mac implementation policy, not a firmware requirement.
4. `0x0304`, or a failed `0x0300` acknowledgement, ends the attempt.
5. Empty command `0x0301` **cancels authentication**. It is not an authentication-status query.

Since 1.0.5, refresh queries are `0x0000`, `0x0001`, `0x0010`, `0x0070`, `0x0050`, serialized. Firmware loads first to establish the versioned information/EQ layouts. Editing becomes available after firmware, information, audio state and EQ have loaded. Full device controls additionally require their complete device-information fields. Explicit `0x0000` query/readback was observed on ES100 firmware 2.0.2 on 2026-10-07; other versions still require hardware validation.

I timeouts: 20 seconds for opening/service discovery, 180 for authentication, 25 for initial synchronization, 4 for a queued transaction. Initial confirmation, key reuse, rejection sequences and firmware information delivery need further recorded validation. Never archive actual keys; fixture key `0x1234` is synthetic.

## Numeric encoding (S; volume and gain scales also B)

- Volume/attenuation uses `s16(trunc(dB * 256))`, decoded by dividing by 256. This covers volume, tone volume, limits, trim and loopback. The wire's representable range is broader than the UI range.
- EQ preamp/bands use `s8(Math.round(dB / 0.1))`. Java rounds negative halves toward positive infinity; the Mac uses `floor(dB * 10 + 0.5)` and clamps to -12 through +12 dB. A -1.2 dB gain is `F4`.
- Boolean arguments are `00`/`01` unless packed with other settings.
- The Q choices are raw `u16` 2896 (displayed wide 0.7071) and 5791 (narrow 1.4142). The app sends these raw values rather than arbitrary Q.
- Microphone gain is a table index 0-22, not linear dB: `[-27, -23.5, -21, -17.5, -15, -11.5, -9, -5.5, -3, 0, 3, 6, 9, 12, 15, 18, 21.5, 24, 27.5, 30, 33.5, 36, 39.5]`. Preamp adds 21 dB to the displayed gain.

## Mac host command map (S)

Ranges/labels below describe the exposed Mac choices, not every value firmware might accept. See the firmware gates section. This table covers every `DeviceCommand` case in the source baseline.

| ID | Mac case | Host payload / exposed choices |
| --- | --- | --- |
| `0x0000` | `deviceDetails` | Empty; full information, firmware, codec enables, tones, auto power, crossfeed, loopback |
| `0x0001` | `deviceInfo` | Empty; information part 2 |
| `0x0010` | `state` | Empty; packed audio/device state |
| `0x0050` | `eq` | Empty; active graphic EQ |
| `0x0070` | `battery` | Empty; percent and millivolts |
| `0x0102` | `dct` | `u8` level 0-10 |
| `0x0110` | `volume` | `s16`; UI -60 to +6 dB, bounded by loaded volume limit |
| `0x0111` | `mute` | Boolean |
| `0x0112` | `toneVolume` | `s16`; UI -60 to 0 dB |
| `0x0113` | `callMute` | Boolean |
| `0x0114` | `trim` | Left `s16`, then right `s16`; each -6 to 0 dB |
| `0x0115` | `volumeLimit` | `s16`; UI -60 to +6 dB |
| `0x0120` | `crossfeed` | `u8` 0-10; 0 off |
| `0x0121` | `oversampling` | `u8`: 0 = 1x, 1 = 2x, 2 = 4x |
| `0x0123` | `dacFilter` | `u8`: 0 sharp, 1 slow, 2 short-delay sharp, 3 short-delay slow |
| `0x0125` | `jitter` | `u8`: bit 0 USB, bit 1 Bluetooth |
| `0x0130` | `batteryInterval` | `u16` interval; enum/encoder available but not sent by current UI; units not established here |
| `0x0141` | `eqEnabled` | Boolean |
| `0x0142` | `preamp` | One `s8` EQ gain |
| `0x0143` | `band` | One-based `u8` band number 1-10 (UI array index + 1), then `s8` gain |
| `0x0144` | `allGains` | Eleven `s8` values: preamp, then bands 0-9 |
| `0x0145` | `headroom` | `u8`: low nibble 1 = -6 dB, 2 = -12 dB; bit 4 analog compensation |
| `0x0146` | `q` | `u16` 2896 or 5791 |
| `0x0151` | `charger` | Boolean USB charging enable |
| `0x0153` | `autoPower` | `u8`: 0 normal, 1 off when charger connects, 2 off when USB power disconnects |
| `0x0157` | `batteryCare` | Boolean |
| `0x0158` | `reconnect` | Boolean second-device reconnect |
| `0x0160` | `outputMode` | Bit 0 single-ended; high-power bit 6 single-ended or bit 5 balanced |
| `0x0161` | `outputLock` | Boolean |
| `0x0162` | `codecs` | Bit 0 SBC stays set, bit 1 AAC, bit 2 aptX, bit 3 aptX HD; no LDAC toggle |
| `0x0163` | `buffer` | `u8` 1-10; disabled for LDAC in UI |
| `0x0170` | `mic` | Low five bits gain index; bit 7 preamp |
| `0x0171` | `loopback` | `s16` microphone loopback level |
| `0x0172` | `hfp` | `u8` 0/1 HFP selection |
| `0x0180` | `ambient` | Boolean |
| `0x0181` | `ambientMic` | Low five bits gain index; bit 7 preamp |
| `0x0182` | `ambientRatio` | `u8` 0-100%; UI steps of 5 |
| `0x0183` | `ambientShortcut` | Boolean |
| `0x0190` | `led` | `u8`: 0 color, 1 white, 2 off |
| `0x01A0` | `usbBits` | `u8`: 0 = 48 kHz/16-bit, 1 = 48 kHz/24-bit Mac, 2 = 44.1/48 kHz/16-bit |
| `0x0300` | `authenticate` | `u16` saved key, zero for initial confirmation |
| `0x0301` | `cancelAuthentication` | Empty |

Output-mode arguments are `01`, `41`, `00`, `20` for single-ended normal/high and balanced normal/high. Output lock is reported in bit 7 of the mode byte but changed using its separate command.

### Output mode and headphone presence

Android 1.9.0 forwards state reply `0x0010` byte 6 and notification `0x0221` byte 1 to the same output decoder (`com.radsone.earstudio.c.a.f(Integer)`). It consumes bit 0 for single-ended versus balanced, bits 6/5 for the corresponding high-power selection, and bit 7 for output lock. Its four UI states are amplifier modes, not three plug-presence states. The original help (`0x7f080041`–`0x7f080042`) permits balanced output when the 3.5 mm jack is empty and single-ended output when a 3.5 mm plug is inserted.

No independent “neither jack occupied” or balanced-plug-presence flag has been established from this decoder or the recovered notifications. This does not prove that the hardware or undocumented firmware cannot expose one. A reliable third state would require additional evidence, such as controlled status/notification captures with both sockets empty, a 3.5 mm plug, and a 2.5 mm plug, including with output lock enabled. Do not assign meanings to unused bits or infer absence from idle input, mute, volume, or balanced mode.

## Readback layouts (S)

All accepted layouts require vendor `0xA55A`, the high reply bit and status zero. Length rules below describe the Mac decoder, not every possible firmware variant.

### Information ID `0x0000`

Minimum 11 bytes. Firmware major/minor/patch are `b[6..8]`; tone volume is `s16` at 9. At 13 bytes, codec enables are in `b[12]` bits 1/2/3. At 16 bytes, `b[13]` has low-nibble crossfeed and auto-power bits 7/6; loopback is `s16` at 14. Other fields are not decoded by the Mac. Short packets can establish firmware/tone volume, but only a 16-byte packet marks the full device group loaded. Individual write confirmations also check that their required fields are present.

### Information part 2, `0x0001`

| Payload offset | Meaning |
| --- | --- |
| 1 | Low nibble Bluetooth buffer |
| 2 | Low nibble LED mode |
| 3 | Low nibble codec; bit 7 battery care; bit 6 reconnect; bit 5 HFP; legacy bit 4 USB format |
| 4, 6 | Left/right `s16` trims |
| 8 | `s16` volume limit |
| 10 | Firmware 1.4.3+: bits 1-2 USB format; bit 0 not decoded by Mac |

Minimum lengths are 3 bytes initially, 4 at firmware 1.2.4, 8 at 1.3.1, 10 at 1.4.0, 11 at 1.4.3. Fields are decoded using firmware gates, even if padding extends an older packet. Unknown firmware prevents this packet and EQ from loading; initialization must read firmware first.

### Audio/device state, `0x0010`

Minimum 16 bytes.

| Payload offset | Meaning |
| --- | --- |
| 1 | Low seven bits battery percentage, capped at 100 by Mac |
| 2 | Bit 7 DCT enable; bits 5-6 oversampling; low nibble DCT level |
| 3 | Bit 7 call active; low two bits DAC filter |
| 4 | Bits 6-7 input; bit 4 USB jitter; bit 5 Bluetooth jitter; bits 2-3 rate; pre-1.2.4 low two bits codec |
| 5 | Bit 7 mute; bit 6 call mute; bit 5 charger connected; bit 4 charging; bit 3 bit depth; bit 0 charging enabled |
| 6 | Output mode and bit 7 output lock |
| 7, 9, 11 | Main/call/USB `s16` volumes |
| 13 | Bit 7 microphone preamp; low five bits gain index |
| 14 | Bit 7 ambient enable; bit 6 ambient preamp; bit 5 shortcut; low five bits gain index |
| 15 | Ambient mix percentage |

Mac labels map input 0-3 to idle/USB/Bluetooth 1/Bluetooth 2; codec 0-4 to SBC/AAC/aptX/aptX HD/LDAC; rate 0-3 to 44.1/48/88.2/96 kHz; bit depth 0/1 to 16/24-bit. Further packed Android fields are not currently displayed.

### EQ `0x0050` and battery `0x0070`

EQ: `b[1]` enable, `b[2]` signed preamp, `b[3..12]` ten signed gains. At 1.4.0+, `b[13]` is headroom/analog compensation. At 1.4.3+, `b[14..15]` is raw Q. Minimum lengths are 13, 14 and 16 bytes respectively. No arbitrary center-frequency or per-band-Q field has been identified.

**Single-band numbering correction (2026-10-07):** Android `com_radsone_earstudio_b_c.java` constructs seekbar IDs 0 for preamp and 1-10 for the frequency bands. In `com_radsone_earstudio_b_c$6.java` (and its paired disassembly), the local DSP gets `ID - 1`, but the device command gets `ID` unchanged through `com_radsone_earstudio_c_a.a(int,float)` and the command manager's `0x0143` encoder. Thus 4 kHz uses wire number 8 and reads back at `b[10]` (UI array index 7). The initial Mac implementation and earlier version of this table incorrectly described the device number as zero-based. Version 1.0.3 corrects writes and confirmation matching. Full-array writes/readback remain preamp followed by ten frequency-ordered gains; they do not carry band IDs.

Battery: minimum four bytes, `[status, percent, millivolts_hi, millivolts_lo]`. ID `0x0200` has the same decoded layout. The Mac caps percent at 100.

## Additional decoded notifications (S)

IDs are base IDs; frames must still carry the high reply bit. These are not all emitted host commands.

| ID | Fields after status |
| --- | --- |
| `0x0200` | Battery percent and `u16` millivolts |
| `0x0202` | Charging boolean |
| `0x0220` | Input `u8`, then main/call/USB `s16` volumes |
| `0x0221` | Output mode/lock byte |
| `0x0222` | Rate, codec, bit depth, oversampling; four bytes |
| `0x0230` | Main/call/USB `s16` volumes |
| `0x0231` | Mute in bit 4, call mute in bit 0 |
| `0x0232` | Packed ambient flags/gain, then mix percent |
| `0x0250` | Call active if low nibble nonzero; other bits not decoded |
| `0x0302` | Physical confirmation required |
| `0x0303` | Returned `u16` key |
| `0x0304` | Authentication declined |
| `0x0040` | Crossfeed level |
| `0x0041` | Oversampling selection |
| `0x0043` | DAC filter selection |

Android dispatches additional IDs. Their existence alone does not identify safe host commands or justify exposing new controls.

## Firmware gates and restart behavior

| Explicit Mac gate | Minimum firmware |
| --- | --- |
| Tone volume | 1.1.3 |
| Oversampling, ambient shortcut | 1.1.4 |
| Codec enables | 1.1.8 |
| DCT, crossfeed, microphone loopback | 1.2.0 |
| Auto power mode | 1.3.0 |
| Buffer | 1.2.1 |
| LED | 1.2.2 |
| Battery care | 1.2.4 |
| Trim | 1.3.1 |
| Headroom, volume limit, reconnect, HFP, USB-format command | 1.4.0 |
| Q; three-choice USB-format UI | 1.4.3 |

These are the recovered/current source gates; unknown firmware disables them. Absence of a gate on other commands does not establish compatibility with every older version. The 1.0.5 audit added missing gates from Android controls and the archived 2018 manual, including oversampling, ambient shortcut, crossfeed and loopback. The USB command uses the binary format from 1.4.0–1.4.2; the three-choice format uses 1.4.3+. The legacy UI exposure follows the decoded legacy field; it is covered by fixtures and still needs hardware validation on those versions. USB-format and HFP changes are presented as needing restart; the app does not reboot ES100.

## EQ and preset storage

The interface exposes a **10-band graphic EQ**, at 31.5, 63, 125, 250, 500, 1,000, 2,000, 4,000, 8,000 and 16,000 Hz, with -12 through +12 dB in 0.1 dB steps and global wide/narrow Q. A native-library PEQ type does not establish a general parametric device API.

Readback supplies active EQ. Four inactive Android saved slots are phone-local SharedPreferences strings `radsone_eq_pre1` through `radsone_eq_pre4`, each eleven comma-separated gains (preamp, then ten bands); names are `Preset_name_1` through `Preset_name_4`. Q/headroom are absent. The Mac importer uses narrow Q 5791, headroom mode 1 and analog compensation enabled as I defaults. JSON format `earstudio-companion`, version 1, preserves these fields. Import changes the local library; selecting a preset sends commands.

The curve is a peaking-filter estimate, not measured firmware DSP output, and excludes headroom/analog compensation. Cross-reboot settings persistence remains unverified by the recorded hardware observations.

## Write confirmation: firmware requirement versus app policy

**Reported firmware 2.0.2 behavior:** an initial hardware report observed EQ writes taking effect without a write acknowledgement. A missing write ACK therefore cannot establish that EQ remained unchanged. Verification should explicitly query `0x0050` and compare the returned wire values to the requested change.

**Committed source baseline `012a059` (I):** one command is in flight, unsent slider edits coalesce by control/band after 150 ms, and successful setting ACKs schedule readback. Rejections/timeouts clear pending edits and restore last confirmed UI state; they do not prove that an unacknowledged write failed on the device. There are no automatic write retries. Battery is queried every 30 seconds while connected and idle; diagnostics omit keys and payload contents.

**EQ confirmation policy in 1.0.3:** EQ writes retain their transaction while a `0x0050` query is sent after a 150 ms settling interval, even without a write ACK. Returned EQ must match the requested values before the transaction completes, and later edits wait for that confirmation. Single-band matching subtracts 1 from the wire band number before indexing the readback array. Pending edits remain overlaid on confirmed state so an earlier readback does not undo a later drag. Other acknowledged settings still schedule ordinary readback.

**Volume confirmation policy in 1.0.4:** A user reported an applied `0x0110` volume write followed by the app's missing-ACK warning. Volume now uses the same serialized confirmation path with query `0x0010` after 150 ms. `0x8110` success is optional; an explicit error still fails the write. The returned system volume at `b[7..8]` must encode to the same signed 1/256 dB value as the requested payload. Notifications `0x0230`/`0x0220` update state but do not complete a pending query. Rejected or incomplete state queries and mismatched values remain errors; there are no automatic write retries. This policy is supported by constructed tests and the user report, not an archived raw-device capture.

Validation on 2026-10-07: version 1.0.4 passed 21 core tests and all 36 native Xcode tests. Added volume cases cover omitted/optional ACKs, signed wire matching, serialized volume/EQ edits, unsolicited notifications, ignored writes, rejected state queries and truncated replies. Physical validation of the new build remains pending.

## Fixtures and further validation

Synthetic fixtures in `Tests/ProtocolTests.swift` include:

```text
Authenticate with synthetic key 0x1234:
FF 01 00 02 A5 5A 03 00 12 34

Set volume -32.5 dB:
FF 01 00 02 A5 5A 01 10 DF 80

Set 250 Hz (UI index 3, device band 4) to -1.2 dB:
FF 01 00 02 A5 5A 01 43 04 F4

Set 4 kHz (UI index 7, device band 8) to +2.1 dB:
FF 01 00 02 A5 5A 01 43 08 15
```

The historical source baseline had twelve protocol/preset tests. Version 1.0.3 passed 19 core tests and 29 native Xcode tests on 2026-10-07, covering protocol fixtures, stream boundaries, corruption, signed units, packed state, truncation, firmware gates, queue coalescing, presets, microphone mapping, connection lifecycle and EQ synchronization. The native EQ tests drive all ten slider bindings against a simulated device, check untouched neighbors, and preserve rapid edits across earlier readbacks without write ACKs. These constructed fixtures are not archived device captures. Small 4 kHz/8 kHz drags were also checked in demo mode; the corrected band mapping still needs physical ES100 validation.

Further recorded validation should cover service/channel selection, initial firmware information, first/subsequent authentication, status/layout variants, small downward volume/mute/EQ changes with readback, reconnect, persistence through restart and firmware versions across ES100/MK2. Firmware flashing, factory reset, renaming and iOS transport remain outside the implemented interface.

## All-control audit in 1.0.5

All 34 exposed writable commands now retain their transaction through an explicit readback, with optional successful write ACKs and no automatic write retries. Queries are selected by the field's actual location: `0x0000` for tones/crossfeed/auto power/codec enables/loopback, `0x0001` for extended options, `0x0010` for audio/ambient/microphone/output controls, and `0x0050` for EQ. Every field compares the actual wire representation, including the different ambient preamp write/read bits. Rejected read queries disable only dependent controls. See [ControlAudit.md](ControlAudit.md) for the complete mapping and validation scope.

Hardware on 2026-10-07 reproduced a successful SDP query followed by an RFCOMM open with no completion. Disconnecting/reconnecting the macOS EarStudio link restored authentication and all five settings queries on firmware 2.0.2. Channel selection changed from 1 to 14; a subsequent relaunch also stalled on channel 14, so a stale channel number alone does not explain the issue. The app requests service-specific SDP, handles existing open channels, prevents concurrent Companion ownership, ignores duplicate discovery, closes late opens after cancellation, and retains async write storage through completion. Graceful RFCOMM close cannot guarantee that the OS/device session resets. The explicit **Reconnect Bluetooth** recovery action closes the device baseband link off the main thread, then reopens control; its UI states that Bluetooth audio briefly disconnects. Pairing and device keys are retained.
