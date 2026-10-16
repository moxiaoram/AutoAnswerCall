# AutoAnswerCall 1.9.0

Package: com.autoanswer.call. BuildID is supplied in the delivery report using the compiled commit and successful CI run. No installation, live system-setting change, calls, or device runtime validation performed for 1.9.0.

## 1.9 changes and explicit limits

- Delay is now a PSEditTextCell with a custom finite ASCII decimal parser, range 0..60 seconds, no slider. Invalid edits preserve the old value. Readback uses a decimal numeric string. Delay starts at the first eligible observed incoming CallKit delegate event, NOT measured audible ringing and NOT a startup snapshot. At expiry the call is looked up again and Enabled/mode/state/exclusions are reread. Unknown/unobserved calls do not schedule work.
- Stop plugin action writes Enabled=false and emits a plugin-only stop notification. Phone-side receipt increments a generation token to invalidate all unsubmitted old timers, and stops local playback. Notification delivery is not confirmed by posting. Already submitted transactions cannot be revoked. This action never changes the independent iOS native switch.
- Native pane button immediately attempts the existing accessibility deep link, without the old preliminary alert. It remains UNVERIFIED on iOS17.3: URL completion confirms only that iOS accepted the URL, not arrival at the exact pane. Manual route: Settings > Accessibility > Touch > Call Audio Routing > Auto-Answer Calls. No guessed Preferences internal controller push is used.
- Native read/off adapter uses exact independently published AXSettings methods: +sharedInstance, -(bool)callAudioRoutingAutoAnswerEnabled, -(void)setCallAudioRoutingAutoAnswerEnabled:(bool). Source: https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/AccessibilityUtilities.framework/AXSettings.h (2018 header, not iOS17.3 evidence). Apple does not publish these as a supported public API; iOS17.3-specific runtime header portal is human-verification gated. Adapter dlopens the actual framework and requires exact argument counts, object factory return, B getter, v/B setter ABI on device before invoking anything. Missing/wrong ABI/exception => explicit unavailable, no write. Off re-reads after 0.4 seconds and reports only accessor readback. Persistence and native notification are owned by the native setter; NO guessed CFPreferences key/domain or notify name is written. Device ABI availability, cross-process cache invalidation and real effect are untested. This is guarded code, NOT a claim that one-click off works on the user's 17.3 device.
- Audio import preserves the coordinated asCopy/security-scoped/bounded 5MB-per-file pipeline that user confirmed works in 1.8. Multiple selection and repeated imports append UUID-named files; existing files are never replaced. audio-library.plist stores id/path/name/size/duration with SelectedAudioID. Existing audio.plist/AudioPath is registered in place without moving the old file. First import into an empty library selects the first entry; later imports retain selection. Settings audio list displays file name, size, duration, readability and selected checkmark. Tap a readable row to select, accessory button to preview/stop or confirm individual deletion. Deletion preserves files still referenced by another entry and selects the next entry when selected entry is deleted (or clears selected metadata if empty). Selected-only audio.plist/AudioPath/AudioName/AudioSize remain compatible; configuration export does not export all library entries/audio bytes. Library remains in the Settings sandbox; MobilePhone access/uplink is not solved.
- Tests are portable policy unit tests and source/structure checks plus a real CI compile/link/sign/package. They are not UIKit interaction, device observer, import migration or live native-setting tests. No pong was observed here; screenshot or local preview is not call-function evidence.

## Modes

- Scheme 2 (Mode=2, default): plugin exclusion whitelist priority. Enabled is read separately and on delayed revalidation. Disable iOS native Auto-Answer Calls manually first: Settings > Accessibility > Touch > Call Audio Routing > Auto-Answer Calls. Only the separate guarded native-off action may invoke the system setter; ordinary plugin policy never changes it. Full normalized numbers match exactly; formatting spaces, parentheses, dots, dashes and an initial + are removed. Country prefixes are not inferred, suffix/substring/wildcard matching is not supported. Comma, Chinese comma, semicolon and newline separate entries. Invalid entries cause refusal; unknown caller with a nonempty whitelist also causes refusal.
- Scheme 1 (Mode=1): native iOS fallback guidance. The plugin submits no answer transaction. Open the system settings with the button or follow the manual path above. The deep link is unverified and may fail. Native iOS auto-answer applies to all calls and is independent of the plugin Enabled switch, delay and whitelist. Switching the plugin off cannot turn off the system feature.

## Actual answer implementation

MobilePhone alone retains a CXCallObserver and a delegate implementing callObserver:callChanged: with CXCall. Incoming/outgoing, connected, ended and UUID use public properties. Each UUID schedules at most one outstanding delay and at most one transaction attempt; delayed work looks up the current call again and rereads preferences. It submits CXAnswerCallAction with that UUID through CXCallController requestTransaction:completion:. Completion failures include domain, code and description. Transaction acceptance is not connection success. Connection observed without a pending request is labelled manual/system/other; connection during a pending request is logged as correlation only, because manual/system answering can coincide. Pending observations time out after 15 seconds.

CXCall has no public number property. Optional phoneNumber/callerNumber selectors are only called when an existing getter has exactly two Objective-C ABI arguments and object return type, and its result is an NSString; otherwise the number is unknown. These are not guaranteed to exist. With a nonempty exclusion list this normally means fail closed until a validated number source exists on the actual device. No guessed CTCall/IOBluetooth hooks remain. Public CallKit transactions do not guarantee cellular answering permissions. Retaining an observer in MobilePhone cannot prevent suspension; background/lockscreen delivery is not guaranteed. Injection scope remains com.apple.MobilePhone.

## Audio

Import uses UIDocumentPicker asCopy:YES, starts/stops security scope, coordinates reads on a background worker, and reads at most 5MB + 1 byte. Empty, oversized or unsupported files fail with source-read, destination-write or audio-decoder details. Successful files go into the actual Settings process Application Support/AutoAnswerCall directory, followed by an independent audio.plist. Local AVAudioPlayer preview retains the player and checks prepare/play return values. The settings diagnostic displays imported name, byte count and path. Export persistent configuration uses the share sheet to export configuration.plist.

The AudioPath preference is also published as configuration. This does not grant MobilePhone access to the Settings sandbox. Phone-side local playback is optional, default off, and logs inaccessible/unsupported files. It only attempts local playback following an observed request-associated connection when transaction acceptance has already arrived. A callback ordering race can skip playback. No RootHide shared path is invented; no libroot headers were verified for runtime shared storage, so no fixed /var/jb is used. No audio bytes are pushed through CFPreferences. Local AVAudioPlayer is NOT call uplink injection and cannot promise the remote party hears it.

## Diagnostics

Settings logs persist to its own Application Support/AutoAnswerCall/settings.log with error reporting. Those records prove only the Settings module. Phone logs use NSLog plus a separate CFPreferences domain com.autoanswer.call.phone; writes report failure and cross-sandbox visibility is not guaranteed. Phone diagnostics explicitly show missing/inaccessible data. Darwin ping/pong probes only whether MobilePhone responds at that moment; absence can mean suspension, no injection or notification restrictions, and a pong does not validate call privileges. No settings preview is claimed to prove phone loading or call functionality.

## Rebuild and validation

Theos RootHide commit cfba89a53a05b4a1b822121158acc3669c20602f, Apple clang 15.0.0 (clang-1500.3.9.4), Xcode 15.4 iPhoneOS SDK 17.5, target arm64e, minimum iOS 17.0, roothide scheme. ldid was invoked by Theos; successful signing stage does not establish trust on a target device.

On macOS with Xcode and RootHide Theos:

```
brew install ldid dpkg ripgrep
cc -std=c11 tests/policy.c -lm -o /tmp/aac-policy
/tmp/aac-policy
python3 tests/source_checks.py
make clean package FINALPACKAGE=1 ARCHS=arm64e THEOS=/path/to/roothide/theos THEOS_PACKAGE_SCHEME=roothide
```

Both policy regressions and source checks passed locally and in CI. Compilation, link, signing and packaging passed. Package metadata and file contents were checked, and Mach-O headers/signature-region presence were inspected. Icons are RGBA 29/58/87 px with four transparent corners. No runtime installation or phone call was made. A successful source build is not evidence that the device grants answer transactions, obtains caller numbers, delivers locked-screen callbacks or shares imported audio.
