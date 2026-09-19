package tv.livebuy.flutter

import java.util.concurrent.CopyOnWriteArrayList

/**
 * Opt-in `onPictureInPictureModeChanged` bridge for the Flutter Android bridge, mirroring the
 * shape of [LivebuyPiPUserLeaveHint]. Introduced by flutter-android-pip-video-surface-detach-core
 * (2026-09-17); current scope set by flutter-android-texture-layer-composition-core.
 *
 * WHAT IT DOES: `LivebuyPlayerViewFactory` registers a forward on view create that calls —
 * synchronously, with no Dart round-trip — the existing core seam
 * `LivebuyPlayerView.notifyPictureInPictureModeChanged(isInPictureInPictureMode)`
 * (android-view-mode-pip-forward-core, the same seam RN / native Android View-mode hosts call):
 * watch-time (`person_time` / `person_duration`) gating while in PiP, plus
 * `reassertPiPControlsLock()` (IVS native controls re-lock) on enter. Nothing else. The forward is
 * unregistered on view dispose. The Dart-facing
 * `LivebuyPlayerController.notifyPictureInPictureModeChanged` (flutter-android-pip-mode-forward-core)
 * reaches the same idempotent seam through the method channel; this native path is the
 * synchronous, host-wiring-optional alternative and coexists with it.
 *
 * WHY THIS EXISTS: `Activity.onPictureInPictureModeChanged(boolean, Configuration)` is delivered
 * ONLY to the Activity that overrides it — same platform limitation as `onUserLeaveHint()` — so a
 * Flutter plugin cannot observe it unassisted; the host forwards it with one line.
 *
 * HISTORY: the original version of this forward ALSO detached / reattached the video surface
 * around the PiP transition, to dodge the MediaCodec teardown/rebuild churn that Flutter's Hybrid
 * Composition caused by re-creating the embedded view's `TextureView` for every intermediate PiP
 * window size (`docs/reference-ui/parity-debt-ledger.md` #35). That detach wiring was removed by
 * flutter-android-texture-layer-composition-core: the Flutter Android player mounts via Texture
 * Layer composition again (`initSurfaceAndroidView`, with a `SurfaceView`-free native view tree),
 * so a PiP transition is a plain window resize and the `Player`'s render surface stays bound for
 * the whole transition — the PiP thumbnail keeps showing video, exactly like RN / native hosts.
 *
 * HOST WIRING:
 * ```kotlin
 * override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
 *     super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
 *     LivebuyPiPModeChangeHint.notifyModeChanged(isInPictureInPictureMode)
 * }
 * ```
 *
 * This bridge is ADDITIVE / OPT-IN: a host that never calls [notifyModeChanged] gets byte-identical
 * behavior to a build without it (PiP gating then relies on the Dart-side forward, if wired).
 */
object LivebuyPiPModeChangeHint {

    // CopyOnWriteArrayList: registration/unregistration happen on the main thread at view
    // create/dispose; notify fan-out iterates a stable snapshot without locking.
    private val listeners = CopyOnWriteArrayList<(Boolean) -> Unit>()

    /** Register a forward (the bridge's synchronous `notifyPictureInPictureModeChanged` relay).
     *  Pair with [unregister] on dispose. */
    fun register(cb: (Boolean) -> Unit) {
        listeners.add(cb)
    }

    /** Remove a previously-registered forward. */
    fun unregister(cb: (Boolean) -> Unit) {
        listeners.remove(cb)
    }

    /**
     * Fan-out to every registered forward. Call from the host
     * `MainActivity.onPictureInPictureModeChanged()` override (after calling `super`). No-op
     * when nothing is registered.
     */
    fun notifyModeChanged(isInPictureInPictureMode: Boolean) {
        listeners.forEach { it(isInPictureInPictureMode) }
    }
}
