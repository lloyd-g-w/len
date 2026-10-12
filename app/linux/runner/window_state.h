#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Smallest usable window (toolbar + a bit of canvas), in logical pixels.
constexpr int kMinWindowWidth = 360;
constexpr int kMinWindowHeight = 400;

// Before the window is shown: applies the size, position (X11 only; Wayland
// compositors place windows themselves) and maximised state saved when Len
// last closed, from <user data dir>/<APPLICATION_ID>/window.ini, clamped to
// the monitor's work area. Then keeps track of them and saves them when the
// window is destroyed.
//
// Also serves the "len/window" channel on [view]'s engine:
// `setFullScreen(bool)` (presentation mode; lib/platform/fullscreen_native.dart)
// answers whether full screen was requested.
void window_state_attach(GtkWindow* window, FlView* view);

// Saves [window]'s state now. Closing the window quits the application
// without destroying it (Flutter's exit request), so the application's
// shutdown calls this.
void window_state_save(GtkWindow* window);

#endif  // RUNNER_WINDOW_STATE_H_
