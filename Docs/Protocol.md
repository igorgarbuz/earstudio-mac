# EarStudio ES100 control protocol

This is the maintained interoperability description recovered from EarStudio Android **1.9.0 / version code 35**, with the Mac command/decoder baseline at commit `012a059`. It is not a vendor specification. [Provenance.md](Provenance.md) pins the original evidence and distinguishes static recovery from a reported firmware 2.0.2 hardware test and concurrent implementation work.

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
3. Successful `0x0303` supplies `[status, key_hi, key_lo]`; the Mac saves the key in Keychain and begins readback.
4. `0x0304`, or a failed `0x0300` acknowledgement, ends the attempt.
5. Empty command `0x0301` **cancels authentication**. It is not an authentication-status query.

Refresh queries are `0x0001`, `0x0010`, `0x0070`, `0x0050`, serialized. Editing becomes available after information, audio state and EQ have loaded. The Mac also decodes ID `0x0000` for firmware/device information but does not explicitly query it in refresh. Its startup delivery/order remains important to check because firmware gates depend on it.

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
| `0x0143` | `band` | Zero-based `u8` index 0-9, then `s8` gain |
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

## Readback layouts (S)

All accepted layouts require vendor `0xA55A`, the high reply bit and status zero. Length rules below describe the Mac decoder, not every possible firmware variant.

### Information ID `0x0000`

Minimum 11 bytes. Firmware major/minor/patch are `b[6..8]`; tone volume is `s16` at 9. At 13 bytes, codec enables are in `b[12]` bits 1/2/3. At 16 bytes, `b[13]` has low-nibble crossfeed and auto-power bits 7/6; loopback is `s16` at 14. Other fields are not decoded by the Mac.

### Information part 2, `0x0001`

| Payload offset | Meaning |
| --- | --- |
| 1 | Low nibble Bluetooth buffer |
| 2 | Low nibble LED mode |
| 3 | Low nibble codec; bit 7 battery care; bit 6 reconnect; bit 5 HFP; legacy bit 4 USB format |
| 4, 6 | Left/right `s16` trims |
| 8 | `s16` volume limit |
| 10 | Firmware 1.4.3+: bits 1-2 USB format; bit 0 not decoded by Mac |

Minimum lengths are 3 bytes initially, 4 at firmware 1.2.4, 8 at 1.3.1, 10 at 1.4.0, 11 at 1.4.3. Optional present fields are also decoded when a shorter minimum applies. Unknown firmware does not establish which version layout is correct.

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
| Buffer | 1.2.1 |
| LED | 1.2.2 |
| Battery care | 1.2.4 |
| Trim | 1.3.1 |
| Headroom, volume limit, reconnect, HFP, USB-format command | 1.4.0 |
| Q; three-choice USB-format UI | 1.4.3 |

These are the recovered/current source gates; unknown firmware disables them. Absence of a gate on other commands does not establish compatibility with every older version. The archived 2018 manual additionally specifies 1.1.4 for oversampling/ambient shortcut and 1.2.0 for crossfeed/microphone loopback. Those extra minimums are not currently encoded by the Mac; this discrepancy remains a compatibility task. USB-format and HFP changes are presented as needing restart; the app does not reboot ES100.

## EQ and preset storage

The interface exposes a **10-band graphic EQ**, at 31.5, 63, 125, 250, 500, 1,000, 2,000, 4,000, 8,000 and 16,000 Hz, with -12 through +12 dB in 0.1 dB steps and global wide/narrow Q. A native-library PEQ type does not establish a general parametric device API.

Readback supplies active EQ. Four inactive Android saved slots are phone-local SharedPreferences strings `radsone_eq_pre1` through `radsone_eq_pre4`, each eleven comma-separated gains (preamp, then ten bands); names are `Preset_name_1` through `Preset_name_4`. Q/headroom are absent. The Mac importer uses narrow Q 5791, headroom mode 1 and analog compensation enabled as I defaults. JSON format `earstudio-companion`, version 1, preserves these fields. Import changes the local library; selecting a preset sends commands.

The curve is a peaking-filter estimate, not measured firmware DSP output, and excludes headroom/analog compensation. Cross-reboot settings persistence remains unverified by this archive task.

## Write confirmation: firmware requirement versus app policy

**Reported firmware 2.0.2 behavior:** the concurrent workspace README says EQ writes can take effect without a write acknowledgement. A missing write ACK therefore cannot establish that EQ remained unchanged. Verification should explicitly query `0x0050` and compare the returned wire values to the requested change.

**Committed source baseline `012a059` (I):** one command is in flight, unsent slider edits coalesce by control/band after 150 ms, and successful setting ACKs schedule readback. Rejections/timeouts clear pending edits and restore last confirmed UI state; they do not prove that an unacknowledged write failed on the device. There are no automatic write retries. Battery is queried every 30 seconds while connected and idle; diagnostics omit keys and payload contents.

**Concurrent local implementation (not part of this documentation commit):** EQ writes retain their transaction while a `0x0050` query is sent after a 150 ms settling interval, even without a write ACK. Returned EQ must match the requested values before the transaction completes, and later edits wait for that confirmation. This policy is visible in working-tree `confirmationReadback`, `matchesEQReadback` and queue changes. It should be documented against its own source commit when those changes are committed. Other acknowledged settings still schedule ordinary readback.

## Fixtures and further validation

Synthetic fixtures in `Tests/ProtocolTests.swift` include:

```text
Authenticate with synthetic key 0x1234:
FF 01 00 02 A5 5A 03 00 12 34

Set volume -32.5 dB:
FF 01 00 02 A5 5A 01 10 DF 80

Set zero-based band 3 to -1.2 dB:
FF 01 00 02 A5 5A 01 43 03 F4
```

The source baseline has twelve protocol/preset tests covering fixtures, stream boundaries, corruption, signed units, packed state, truncation, firmware gates, queue coalescing, presets and microphone mapping. Concurrent local tests add EQ readback confirmation cases. Those constructed fixtures are not archived device captures; this documentation task did not rerun or certify the concurrent code changes.

Further recorded validation should cover service/channel selection, initial firmware information, first/subsequent authentication, status/layout variants, small downward volume/mute/EQ changes with readback, reconnect, persistence through restart and firmware versions across ES100/MK2. Firmware flashing, factory reset, renaming and iOS transport remain outside the implemented interface.
