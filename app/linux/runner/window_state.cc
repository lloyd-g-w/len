#include "window_state.h"

#include <cerrno>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

namespace {

constexpr char kGroup[] = "window";
constexpr GdkWindowState kNotNormal = static_cast<GdkWindowState>(
    GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
    GDK_WINDOW_STATE_TILED | GDK_WINDOW_STATE_ICONIFIED);

struct WindowState {
  GtkWindow* window;
  FlMethodChannel* channel;
  // The last "normal" (not maximised / tiled / full screen) geometry.
  gint width;
  gint height;
  gint x;
  gint y;
  gboolean has_size;
  gboolean has_position;
  gboolean maximized;
};

gchar* state_path() {
  return g_build_filename(g_get_user_data_dir(), APPLICATION_ID, "window.ini",
                          nullptr);
}

// Only X11 lets applications read and set their window position.
gboolean can_position(GtkWindow* window) {
#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gtk_widget_get_display(GTK_WIDGET(window)));
#else
  return FALSE;
#endif
}

void restore(WindowState* state) {
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_autofree gchar* path = state_path();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  gint width = g_key_file_get_integer(file, kGroup, "width", &error);
  gint height = error == nullptr
                    ? g_key_file_get_integer(file, kGroup, "height", &error)
                    : 0;
  if (error != nullptr || width <= 0 || height <= 0) return;
  gboolean maximized =
      g_key_file_get_boolean(file, kGroup, "maximized", nullptr);

  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(state->window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) monitor = gdk_display_get_monitor(display, 0);

  // A saved position counts only if the window's centre is on a monitor
  // that still exists (it may have been unplugged).
  gboolean has_position = FALSE;
  gint x = 0;
  gint y = 0;
  if (can_position(state->window) &&
      g_key_file_has_key(file, kGroup, "x", nullptr) &&
      g_key_file_has_key(file, kGroup, "y", nullptr)) {
    x = g_key_file_get_integer(file, kGroup, "x", nullptr);
    y = g_key_file_get_integer(file, kGroup, "y", nullptr);
    const gint n = gdk_display_get_n_monitors(display);
    for (gint i = 0; i < n; i++) {
      GdkMonitor* candidate = gdk_display_get_monitor(display, i);
      GdkRectangle area;
      gdk_monitor_get_workarea(candidate, &area);
      const gint cx = x + width / 2;
      const gint cy = y + height / 2;
      if (cx >= area.x && cx < area.x + area.width && cy >= area.y &&
          cy < area.y + area.height) {
        monitor = candidate;
        has_position = TRUE;
        break;
      }
    }
  }

  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    width = MIN(width, MAX(area.width, kMinWindowWidth));
    height = MIN(height, MAX(area.height, kMinWindowHeight));
  }
  width = MAX(width, kMinWindowWidth);
  height = MAX(height, kMinWindowHeight);

  gtk_window_set_default_size(state->window, width, height);
  if (has_position) gtk_window_move(state->window, x, y);
  if (maximized) gtk_window_maximize(state->window);

  state->width = width;
  state->height = height;
  state->has_size = TRUE;
  state->x = x;
  state->y = y;
  state->has_position = has_position;
  state->maximized = maximized;
}

void save(WindowState* state) {
  if (!state->has_size) return;
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_key_file_set_integer(file, kGroup, "width", state->width);
  g_key_file_set_integer(file, kGroup, "height", state->height);
  if (state->has_position) {
    g_key_file_set_integer(file, kGroup, "x", state->x);
    g_key_file_set_integer(file, kGroup, "y", state->y);
  }
  g_key_file_set_boolean(file, kGroup, "maximized", state->maximized);
  g_autofree gchar* path = state_path();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_autoptr(GError) error = nullptr;
  if (g_mkdir_with_parents(dir, 0700) != 0 ||
      !g_key_file_save_to_file(file, path, &error)) {
    g_warning("Could not save the window state to %s: %s", path,
              error != nullptr ? error->message : g_strerror(errno));
  }
}

GdkWindowState current_state(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  return gdk_window != nullptr ? gdk_window_get_state(gdk_window)
                               : static_cast<GdkWindowState>(0);
}

gboolean on_configure(GtkWidget* widget, GdkEvent* event, gpointer data) {
  auto* state = static_cast<WindowState*>(data);
  if ((current_state(state->window) & kNotNormal) == 0) {
    gtk_window_get_size(state->window, &state->width, &state->height);
    state->has_size = TRUE;
    if (can_position(state->window)) {
      gtk_window_get_position(state->window, &state->x, &state->y);
      state->has_position = TRUE;
    }
  }
  return FALSE;
}

gboolean on_window_state(GtkWidget* widget, GdkEventWindowState* event,
                         gpointer data) {
  auto* state = static_cast<WindowState*>(data);
  // Leaving full screen restores the earlier maximised state, so only
  // changes outside full screen count.
  if ((event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) == 0) {
    state->maximized =
        (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  }
  return FALSE;
}

void on_destroy(GtkWidget* widget, gpointer data) {
  save(static_cast<WindowState*>(data));
}

void free_state(gpointer data) {
  auto* state = static_cast<WindowState*>(data);
  g_clear_object(&state->channel);
  g_free(state);
}

void method_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<WindowState*>(data);
  g_autoptr(FlMethodResponse) response = nullptr;
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(fl_method_call_get_name(call), "setFullScreen") == 0 &&
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
    const gboolean on = fl_value_get_bool(args);
    if (on) {
      gtk_window_fullscreen(state->window);
    } else {
      gtk_window_unfullscreen(state->window);
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(on)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void window_state_save(GtkWindow* window) {
  auto* state = static_cast<WindowState*>(
      g_object_get_data(G_OBJECT(window), "len-window-state"));
  if (state != nullptr) save(state);
}

void window_state_attach(GtkWindow* window, FlView* view) {
  auto* state = g_new0(WindowState, 1);
  state->window = window;
  g_object_set_data_full(G_OBJECT(window), "len-window-state", state,
                         free_state);
  restore(state);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure), state);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_window_state),
                   state);
  g_signal_connect(window, "destroy", G_CALLBACK(on_destroy), state);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "len/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->channel, method_cb, state,
                                            nullptr);
}
