# Control mapping audit — Companion 1.0.6

Audit date: 2026-10-07. The evidence is Android 1.9.0's `com_radsone_a_a_a_b.java` command writers and response switch, its paired disassembly, Android activities/fragments for control limits and gates, and the archived ES100 manual. [Provenance.md](Provenance.md) identifies the private evidence archive. This document records implementation checks; it does not claim every setting was exercised on physical hardware.

All offsets include the reply status byte at `b[0]`. Multi-byte values are big-endian. `V` means signed 1/256 dB; `G` means signed 0.1 dB EQ gain. Successful write ACKs are optional. Each edit waits for the specified query and compares the actual field before the next write is sent. Explicit rejection, missing/truncated readback, and a different returned value remain actionable errors. Writes are never automatically retried.

| Control | Write | Payload | Confirmation query / actual field |
| --- | --- | --- | --- |
| DCT level | `0102` | Level 0–10 | `0010`, low nibble `b[2]` |
| Analog volume | `0110` | V | `0010`, V at 7; call/USB volumes remain separate |
| Mute | `0111` | Boolean | `0010`, `b[5]` bit 7 |
| Notification volume | `0112` | V | `0000`, V at 9 |
| Call mute | `0113` | Boolean | `0010`, `b[5]` bit 6 |
| Left/right attenuation | `0114` | V left, V right | `0001`, V at 4 and 6 |
| Volume limit | `0115` | V | `0001`, V at 8 |
| Crossfeed | `0120` | Level 0–10 | `0000`, low nibble `b[13]` |
| Oversampling | `0121` | 0/1/2 = 1×/2×/4× | `0010`, `b[2]` bits 5–6 |
| DAC filter | `0123` | 0/1/2/3 | `0010`, low two bits `b[3]` |
| USB/Bluetooth jitter processing | `0125` | Write bits 0/1 | `0010`, read bits 4/5 of `b[4]` |
| EQ enabled | `0141` | Boolean | `0050`, `b[1]` |
| EQ preamp | `0142` | G | `0050`, `b[2]` |
| Individual EQ band | `0143` | **1–10** band ID, G | `0050`, `b[ID + 2]`; UI index = ID − 1 |
| All EQ gains/preset | `0144` | 11 G values, preamp first | `0050`, `b[2...12]` |
| Headroom/analog compensation | `0145` | Mode 1/2, compensation bit 4 | `0050`, `b[13]` |
| Q | `0146` | Raw 2896/5791 | `0050`, u16 at 14 |
| USB charging | `0151` | Boolean | `0010`, `b[5]` bit 0 |
| Auto power | `0153` | 0/1/2 | `0000`, `b[13]` bits 7/6 map back to 1/2 |
| Battery care | `0157` | Boolean | `0001`, `b[3]` bit 7 |
| Second-device reconnect | `0158` | Boolean | `0001`, `b[3]` bit 6 |
| Output/amplifier mode | `0160` | `01`/`41`/`00`/`20` | `0010`, `b[6]` mode bit 0 and power bits 6/5 |
| Output lock | `0161` | Boolean | `0010`, `b[6]` bit 7 |
| AAC/aptX/aptX HD permits | `0162` | SBC bit 0 always set; bits 1/2/3 | `0000`, `b[12]` bits 1/2/3; active codec is separate |
| Bluetooth buffer | `0163` | Level 1–10 | `0001`, low nibble `b[1]`; UI disabled for LDAC |
| Call microphone | `0170` | Index 0–22 + preamp bit 7 | `0010`, `b[13]` low five bits + bit 7 |
| Microphone loopback | `0171` | V | `0000`, V at 14 |
| HFP profile | `0172` | 0/1 | `0001`, `b[3]` bit 5; restart required |
| Ambient enabled | `0180` | Boolean | `0010`, `b[14]` bit 7 |
| Ambient microphone | `0181` | Index 0–22 + **write** preamp bit 7 | `0010`, `b[14]` index + **read** preamp bit 6 |
| Ambient mix | `0182` | 0–100 | `0010`, `b[15]` |
| Ambient button shortcut | `0183` | Boolean | `0010`, `b[14]` bit 5 |
| LED | `0190` | 0/1/2 = color/white/off | `0001`, low nibble `b[2]` |
| USB format | `01A0` | 0/1; 2 added at 1.4.3 | `0001`, legacy `b[3]` bit 4; 1.4.3+ `b[10]` bits 1–2 |

The microphone gain index uses the Android hardware table, with +21 dB for preamp. Boolean controls never replace adjacent packed bits. Output lock uses a separate command and blocks mode selection. Codec permits do not force the currently negotiated codec. Battery care, HFP and USB changes retain their restart guidance.

## Corrections applied

- Generalized the EQ/volume confirmation behavior to all 34 settings.
- Corrected the five full-information readback mappings (notification volume, crossfeed, auto power, codec permits, loopback). They previously refreshed audio state, which does not contain them.
- Added the full-information query before versioned packets; verified its 16-byte response on firmware 2.0.2. Short startup packets establish firmware but do not enable absent full-device fields. Confirmation verifies that the particular field exists in the reply.
- Decode extended fields using firmware versions rather than the presence of trailing bytes. Older USB format cannot be overwritten by modern-format padding.
- Added omitted firmware gates: oversampling/ambient shortcut 1.1.4; codec permits 1.1.8; DCT/crossfeed/loopback 1.2.0; auto power 1.3.0. Existing other gates have boundary coverage.
- Exposed the legacy binary USB format for 1.4.0–1.4.2, while reserving its third choice for 1.4.3+. This follows the recovered decoder; legacy physical validation remains outstanding.
- Enforced loaded groups and rejected-query dependencies in both model actions and UI controls, including volume/mute and preset application. Old firmware without a volume-limit field does not clamp positive volume to the default placeholder limit.
- Rejected nonfinite trim input. Preserved pending edits through earlier readbacks, including combined codec, microphone, jitter and headroom arguments.

## Connection validation and limits

Hardware observation: ES100 firmware 2.0.2, macOS on this development Mac. No firmware settings were changed during this audit. Two Companion copies were initially running; the opening failure was subsequently reproduced with just one copy.

At 22:30 and 22:39, SDP returned success, channel 1's async open returned success and a channel object, but neither open nor close completion arrived. Disconnecting/reconnecting **only EarStudio** in macOS Bluetooth settings restored audio. At 22:43:49, channel 14 opened; authentication succeeded at 22:44:01, followed by successful replies to `0000` (16 bytes), `0001` (11), `0010` (16), `0070` (4) and `0050` (16). Authentication keys and personal Bluetooth addresses are excluded from this record.

A clean quit/relaunch at 22:45 reproduced the stalled open on channel 14. Therefore, channel-number cache invalidation alone is insufficient. The app now requests the relevant SDP UUIDs, handles an existing open channel without requiring another callback, prevents another Companion copy from taking the channel, ignores repeated discovery, closes late opens after cancellation, retains pending async write storage, and waits for channel close before reconnect/termination.

**Reconnect Bluetooth** is explicit recovery after an opening failure. It closes the EarStudio baseband link off the main thread, briefly interrupts Bluetooth audio, and reconnects control. Cancellation suppresses the subsequent control attempt; errors/timeouts remain visible. Pairing and saved device keys remain intact. Graceful RFCOMM close alone cannot guarantee that the OS/device releases a stuck session.

## Regression coverage

`ControlMappingTests` uses literal Android packet fixtures and checks every setting's query, bit positions, signs/units, optional ACK handling, version boundaries, truncations and legacy USB layout. `AllControlsSynchronizationTests` exercises every native setting action, checks exact write bytes against an independent simulated firmware that edits packed reply bytes, and compares the entire resulting state to catch unintended neighboring changes. It also covers combined edits, ignored writes, query rejection, partial full information, preset sequencing and legacy volume bounds. Existing tests cover all ten bands, rapid edits, notifications, volume and protocol framing. Connection tests cover close/quit ordering, existing channels, duplicate callbacks, ownership leases, cancellation, explicit recovery and async write storage.

These tests establish consistency with the recovered Android protocol. They do not establish physical behavior of every setting, reboot persistence, every ES100/MK2 firmware version, or audio output accuracy. Those remain hardware validation tasks.

Final validation: **64 native Xcode tests and 28 Swift Package core tests passed** on 2026-10-07. The native run includes one additional reused-channel test proving an old async write completion cannot free a new transport's buffer, clear its delegate, or turn an old transmission error into a new connection failure. The 1.0.5 universal archive/DMG is built for arm64 and x86_64 and checked by the packaging script. The Mac locked before the final in-app recovery button could be exercised on hardware; the manual macOS disconnect/reconnect recovery and subsequent full readback were physically verified, while the new button remains covered by injected tests.

## Process ownership in 1.0.6

A process-lifetime `flock` lease is acquired before normal app startup. A second copy activates the existing app and exits; disconnected and demo windows retain ownership too. Lock files are never unlinked while in use, and the OS releases the lease after exit or a crash. Failure to open the lock reports a startup error rather than launching an unprotected owner. Hosted XCTest bypasses normal startup ownership, while each test exercises the guard using an isolated lock file. The separate RFCOMM lease and older-copy check remain in the transport.

Four additional native tests verify duplicate-startup activation/termination, retained ownership while disconnected, release with a stale lock file, and unavailable/symlink lock failures. These complement the existing connection cleanup and control-channel ownership tests.

## Connection investigation on 2026-10-10

### Confirmed cause of the reported discovery timeout

The installed 1.0.7 app reproduced a 20-second service-discovery (SDP) timeout on macOS 15.7.9 (24G830), including an attempt whose diagnostics said the Mac link was connected. The system log confirms Bluetooth privacy approval before that attempt. Authentication storage is first read after RFCOMM opens, so the Keychain-to-local-file change cannot explain this pre-authentication timeout. The 1.0.6-to-1.0.7 diff did not change `BluetoothTransport`.

A controlled API comparison against the same paired, connected ES100 isolated the discovery failure:

- `performSDPQuery(target, uuids: serviceUUIDs)` returned success but never called `sdpQueryComplete`. An initial probe waited 65 seconds; a repeated probe using the exact compacted SPP/GAIA array also received no callback in 10 seconds.
- `performSDPQuery(target)` returned success and invoked the completion with status 0 immediately (about 0.04 ms). This establishes completion, not that a new over-the-air refresh occurred; macOS may serve cached service information.
- A final comparison in one process and the same device session ran full → filtered → full with the main dispatch queue free: both full queries completed with status 0 (about 0.02–0.08 ms); the filtered query returned 0 but had no callback within three seconds.
- Git history shows the filtered overload replaced the full query in commit `0e05fa2`, which predates the local authorization-store release.

The patch restores the full SDP query and still selects the SPP/GAIA service from the returned records. Its regression fake models the filtered API accepting a request without completing it, while the full API completes synchronously. Earlier cache-first experiments were removed once this comparison identified the failing overload.

### Separate control-channel and permission findings

macOS audio being connected does not establish that the app's RFCOMM control channel is usable. An initial cached record advertised channel 1. One direct probe observed `isOpen` become true without an open callback, but did not exchange authentication messages. Subsequent channel-1 opens stalled. The patch therefore also observes channel-open state while waiting for the callback, without authenticating twice.

The in-app recovery called `closeConnection` successfully and Settings showed EarStudio disconnected. The running process nevertheless reported the old connected state and retried channel 1. After a manual device reconnect in Settings and a fresh app process, the cached channel was 14. At 12:47:58 local time, RFCOMM opened and the ES100 replied to authentication with `0302`, requesting a physical power-button press. No device settings were written. Physical confirmation was not completed before the three-minute timeout, so full readback and remembered authorization were not validated.

A later channel-14 retry failed too: at 12:55:41, the Bluetooth daemon reported RFCOMM error 913 (`0x391`), while IOBluetooth logged a missing channel and did not deliver a usable failure completion to the app. This confirms an additional serial-link failure beyond the SDP bug; its OS/firmware trigger is not established. Similar reopen failures were documented in the earlier audit before version 1.0.7. An experimental explicit baseband reopen was removed because hardware validation did not establish that it fixes recovery.

Switching between ad-hoc-signed builds also produced TCC code-requirement mismatches and permission prompts. The installed release's original mismatch was followed by `TCC is approved` before the reported timeout, so lack of permission does not explain that timeout. During later validation, a process sample showed `pairedDevices()` waiting inside the Bluetooth coordinator. Moving that synchronous initialization off the main queue keeps the interface responsive; it cannot resolve a pending system permission decision. A test verifies the main run loop remains available.

### Validation boundary

The universal Release build succeeds, and all **77 native tests pass with zero failures**. Native tests cover the full-query regression, missing open callbacks, and asynchronous paired-device loading, together with the existing connection/authentication/storage tests. Hardware probes verify the discovery API difference, and an earlier candidate exchanged real authentication messages after manual reconnect. The final build is not yet verified through physical authorization, full settings readback, and repeated reconnects. Changes remain local; the installed application and published release were not replaced.


## Follow-up: version 1.0.8 recovery candidate

After installing the first patch, the user reached RFCOMM rather than timing out in SDP. The 13:05:57 system log confirms Bluetooth permission was approved and channel 14 failed with daemon error 913. This verifies that the discovery change alone did not resolve the complete connection problem.

A device-specific recovery probe reproduced `closeConnection()` returning success while `isConnected()` remained true. Immediately calling `openConnection()` also returned success, but RFCOMM remained closed. Waiting for the link to become disconnected before explicitly reopening it allowed RFCOMM to open in repeated probes; service channel numbers changed across these connections. A final probe polled the disconnected state at 100 ms intervals instead of using a fixed delay and also opened successfully. These probes did not send authentication or setting writes.

The candidate's recovery now waits up to five seconds for the observed disconnection, propagates a timeout if it never happens, and explicitly reopens the baseband connection before the model performs full SDP and opens RFCOMM. Tests exercise delayed state changes, timeout without reopening, and propagation of close/open failures. Physical authentication and complete readback remain separate hardware validation gates.

The candidate is version **1.0.8 (9)**. Build versions are configured in `Configuration/App.xcconfig`; ordinary builds do not increment them. `Tools/build.sh` now prints the embedded version and the packaging command. `Tools/package.sh` builds a universal archive, creates a drag-install DMG under `dist`, verifies it, and generates a SHA-256 checksum. `Tools/publish-release.sh` runs both suites, packages, uploads and verifies a draft, then publishes it. No GitHub release was published during this investigation.

Validation of this follow-up: **80 native tests passed with zero failures**; the universal Release app reports 1.0.8 (9); `Tools/package.sh` produced and verified `dist/EarStudio-Companion-1.0.8-macOS-universal.dmg` and its checksum. The installed copy was not replaced by the agent. The final candidate's hardware UI run is waiting for renewed Bluetooth permission: TCC logged a code-requirement mismatch and `AUTHREQ_PROMPTING` for the local build. The computer-use tool refuses access to the system permission-dialog application, so user action is needed before continuing that run.
