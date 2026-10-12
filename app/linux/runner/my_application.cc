#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "window_state.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The one window of the primary instance (null until activated).
  GtkWindow* window;
  // "len/incoming_files": files another `len <file>` forwarded to this
  // instance (lib/platform/incoming_files_native.dart).
  FlMethodChannel* incoming;
  gboolean dart_ready;
  GPtrArray* pending_paths;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Sets the window icon: the PNG shipped in the bundle
// (<bundle>/share/icons/hicolor/…, see linux/CMakeLists.txt), else the themed
// icon of an installed desktop entry. (Wayland compositors take the icon from
// the .desktop file matching APPLICATION_ID instead.)
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon =
        g_build_filename(dir, "share", "icons", "hicolor", "256x256", "apps",
                         APPLICATION_ID ".png", nullptr);
    if (g_file_test(icon, G_FILE_TEST_EXISTS) &&
        gtk_window_set_icon_from_file(window, icon, nullptr)) {
      return;
    }
  }
  gtk_window_set_icon_name(window, APPLICATION_ID);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Sends the files waiting in pending_paths to Dart once it is ready.
static void send_pending_files(MyApplication* self) {
  if (!self->dart_ready || self->incoming == nullptr ||
      self->pending_paths->len == 0) {
    return;
  }
  g_autoptr(FlValue) files = fl_value_new_list();
  for (guint i = 0; i < self->pending_paths->len; i++) {
    const gchar* path =
        static_cast<const gchar*>(g_ptr_array_index(self->pending_paths, i));
    g_autofree gchar* name = g_path_get_basename(path);
    FlValue* file = fl_value_new_map();
    fl_value_set_string_take(file, "path", fl_value_new_string(path));
    fl_value_set_string_take(file, "name", fl_value_new_string(name));
    fl_value_append_take(files, file);
  }
  g_ptr_array_set_size(self->pending_paths, 0);
  fl_method_channel_invoke_method(self->incoming, "files", files, nullptr,
                                  nullptr, nullptr);
}

static void incoming_method_cb(FlMethodChannel* channel,
                               FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(method_call), "ready") == 0) {
    self->dart_ready = TRUE;
    send_pending_files(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // A second `len` without files: bring the running window forward.
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Len");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Len");
  }

  gtk_window_set_default_size(window, 1280, 800);
  gtk_widget_set_size_request(GTK_WIDGET(window), kMinWindowWidth,
                              kMinWindowHeight);
  set_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // Last size / position / maximised state; "len/window" (full screen).
  window_state_attach(window, view);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->incoming = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "len/incoming_files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->incoming, incoming_method_cb,
                                            self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  *exit_status = 0;
  if (g_application_get_is_remote(application)) {
    // Len is already running: hand it the files (or just raise it) and
    // exit, so one process owns the database.
    g_autoptr(GPtrArray) files = g_ptr_array_new_with_free_func(g_object_unref);
    for (gchar** arg = self->dart_entrypoint_arguments; *arg != nullptr;
         arg++) {
      if ((*arg)[0] != '-' && (*arg)[0] != '\0') {
        g_ptr_array_add(files, g_file_new_for_commandline_arg(*arg));
      }
    }
    if (files->len > 0) {
      g_application_open(application,
                         reinterpret_cast<GFile**>(files->pdata), files->len,
                         "");
    } else {
      g_application_activate(application);
    }
    return TRUE;
  }

  // The primary instance: Dart reads its files from the arguments.
  g_application_activate(application);
  return TRUE;
}

// Implements GApplication::open: files forwarded by a second `len <file>`.
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) g_application_activate(application);
  for (gint i = 0; i < n_files; i++) {
    gchar* path = g_file_get_path(files[i]);
    if (path != nullptr) g_ptr_array_add(self->pending_paths, path);
  }
  send_pending_files(self);
  if (self->window != nullptr) gtk_window_present(self->window);
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) window_state_save(self->window);

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->incoming);
  g_clear_pointer(&self->pending_paths, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_paths = g_ptr_array_new_with_free_func(g_free);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // One instance per user (files opened later go to the running one), unless
  // LEN_MULTI_INSTANCE is set or a non-default data directory is used
  // (XDG_DATA_HOME=$(mktemp -d), e.g. for screenshots and tests).
  GApplicationFlags flags = G_APPLICATION_HANDLES_OPEN;
  g_autofree gchar* default_data =
      g_build_filename(g_get_home_dir(), ".local", "share", nullptr);
  const gchar* data = g_getenv("XDG_DATA_HOME");
  if (g_getenv("LEN_MULTI_INSTANCE") != nullptr ||
      (data != nullptr && data[0] != '\0' &&
       g_strcmp0(data, default_data) != 0)) {
    flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
  }
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
