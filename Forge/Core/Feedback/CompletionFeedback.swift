import AudioToolbox
import UIKit

/// Sound + haptic feedback for habit-completion moments. Stateless by
/// design — reads the "Sound Effects" setting fresh from `UserDefaults` on
/// every call rather than caching it, since the user can flip it in
/// Settings while a completion is in flight.
///
/// Deliberately imperative, called directly from `HomeView.handleTap`
/// rather than driven by a reactive `.sensoryFeedback`/`.onChange` view
/// modifier watching `Completion` snapshots — `handleTap` already computes
/// the exact `wasComplete` → `isComplete` transition (the same
/// `count < goal` → `count >= goal` clamp logic used to decide the
/// completion state itself), so triggering feedback from there reuses that
/// one source of truth instead of re-deriving "did this just complete" a
/// second time in the view layer.
@MainActor
enum CompletionFeedback {
    /// A simple habit toggled on, or a quantity habit's increment that
    /// just crossed `count >= goal` — the one "real completion" moment.
    static func complete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        playSound(.complete)
    }

    /// Un-completing a previously-completed habit. A distinct haptic
    /// pattern from `complete()` (`.rigid` impact, not `.success`/
    /// `.warning`) so it reads as "this reversed something," not as an
    /// error — and deliberately silent rather than replaying the
    /// completion sound backwards, which would just read as confusing.
    static func uncomplete() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A quantity habit's routine increment while still below goal —
    /// subtle, repeatable feedback (a habit like "drink water" might get
    /// tapped 8 times in a row) distinct from the one-time completion
    /// moment above. No sound: an audible tick on every one of those taps
    /// would get grating fast, so the audible moment is reserved for
    /// `complete()`.
    static func incrementStep() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// `AudioServicesPlaySystemSound` IDs for short, dry system UI sounds —
    /// undocumented by Apple but stable and widely relied on by iOS apps
    /// for exactly this kind of lightweight confirmation sound, since this
    /// app ships no bundled audio asset of its own. Deliberately *not*
    /// configuring an `AVAudioSession` category anywhere in this app: the
    /// default session leaves `AudioServicesPlaySystemSound` silenced by
    /// the device's silent switch, which is what "always honor the silent
    /// switch regardless of the in-app toggle" requires — don't add an
    /// `AVAudioSession` category elsewhere without re-checking this.
    private enum SystemSound: SystemSoundID {
        case complete = 1057
    }

    private static let soundEffectsDefaultsKey = "soundEffectsEnabled"

    private static func playSound(_ sound: SystemSound) {
        // Mirrors the `@AppStorage("soundEffectsEnabled")` default of
        // `true` in `SettingsView` — reading the key directly here (rather
        // than via `@AppStorage`, which needs a View context) means a
        // never-set key must default to `true` explicitly, since
        // `UserDefaults.bool(forKey:)` alone would silently default to
        // `false` and mute this by default until the user ever opens
        // Settings.
        let enabled = (UserDefaults.standard.object(forKey: soundEffectsDefaultsKey) as? Bool) ?? true
        guard enabled else { return }
        AudioServicesPlaySystemSound(sound.rawValue)
    }
}
