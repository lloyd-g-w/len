#include "include/pasteboard/pasteboard_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <vector>

#define GNOME_COPIED_FILES gdk_atom_intern_static_string ("x-special/gnome-copied-files")

#define PASTEBOARD_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pasteboard_plugin_get_type(), \
                              PasteboardPlugin))

struct _PasteboardPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(PasteboardPlugin, pasteboard_plugin, g_object_get_type())

static void gtk_clipboard_request_uris_callback(
    GtkClipboard *clipboard,
    gchar **uris,
    gpointer user_data
) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);

  g_autoptr(FlValue) result = fl_value_new_list();
  for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_autoptr(GFile) file = g_file_new_for_uri(*uri);
    auto *file_path = g_file_get_path(file);
    if (file_path) {
      fl_value_append(result, fl_value_new_string(file_path));
    }
  }
  fl_method_call_respond_success(method_call, result, nullptr);
}

static void gtk_clipboard_get_file_uri(GtkClipboard *clipboard,
                                       GtkSelectionData *selection_data,
                                       guint info,
                                       gpointer user_data_or_owner) {
  auto target = gtk_selection_data_get_target(selection_data);
  auto **uris = reinterpret_cast<gchar **>(user_data_or_owner);
  if (gtk_targets_include_uri(&target, 1)) {
    gtk_selection_data_set_uris(selection_data, reinterpret_cast<gchar **>(user_data_or_owner));
  } else if (gtk_targets_include_text(&target, 1)) {
    g_autoptr(GString) string = g_string_new(nullptr);
    bool should_insert_new_line = false;
    for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
      if (should_insert_new_line) {
        g_string_append_c(string, '\n');
      }
      g_string_append(string, *uri);
      should_insert_new_line = true;
    }
    gtk_selection_data_set_text(selection_data, string->str, int(string->len));
  } else if (target == GNOME_COPIED_FILES) {
    g_autoptr(GString) string = g_string_new("copy");
    for (auto uri = uris; uri != nullptr && *uri != nullptr; uri++) {
      g_string_append(string, "\n");
      g_string_append(string, *uri);
    }
    gtk_selection_data_set(selection_data, target, 8, (const guchar *) string->str, int(string->len));
  } else {
    g_critical("unsupported action: gdk_atom_name(target) = %s", gdk_atom_name(target));
  }

}

static void gtk_clipboard_clear(GtkClipboard *clipboard,
                                gpointer user_data_or_owner) {
  auto **uris = reinterpret_cast<gchar **>(user_data_or_owner);
  delete[] uris;
}

static void clipboard_request_image_callback(
    GtkClipboard *clipboard,
    GdkPixbuf *pixbuf,
    gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);

  if (!pixbuf) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  gchar *buffer = nullptr;
  gsize buffer_size = 0;
  GError *error = nullptr;

  gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, "png", &error, nullptr);
  if (error) {
    fl_method_call_respond_error(method_call, "0", error->message, nullptr, nullptr);
    return;
  }

  if (!buffer) {
    fl_method_call_respond_error(method_call, "0", "failed to get image", nullptr, nullptr);
    return;
  }

  fl_method_call_respond_success(method_call,
                                 fl_value_new_uint8_list(reinterpret_cast<const uint8_t *>(buffer), buffer_size),
                                 nullptr);

}

static void clipboard_request_html_callback(
    GtkClipboard *clipboard,
    GtkSelectionData *selection_data,
    gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);
  gint length = 0;
  const guchar *data = selection_data == nullptr
      ? nullptr
      : gtk_selection_data_get_data_with_length(selection_data, &length);
  if (data == nullptr || length <= 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  // Raw bytes: some apps (Firefox) offer UTF-16, decoded on the Dart side.
  fl_method_call_respond_success(method_call,
                                 fl_value_new_uint8_list(data, length),
                                 nullptr);
}

// "peek" (added in Len's copy): the kinds of content the clipboard offers
// ("image", "text", "html", "files"), from its targets alone.
static void clipboard_request_targets_callback(GtkClipboard *clipboard,
                                               GdkAtom *atoms,
                                               gint n_atoms,
                                               gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = static_cast<FlMethodCall *>(user_data);
  g_autoptr(FlValue) kinds = fl_value_new_list();
  if (atoms != nullptr && n_atoms > 0) {
    if (gtk_targets_include_image(atoms, n_atoms, FALSE)) {
      fl_value_append_take(kinds, fl_value_new_string("image"));
    }
    if (gtk_targets_include_text(atoms, n_atoms)) {
      fl_value_append_take(kinds, fl_value_new_string("text"));
    }
    GdkAtom html = gdk_atom_intern_static_string("text/html");
    for (gint i = 0; i < n_atoms; i++) {
      if (atoms[i] == html) {
        fl_value_append_take(kinds, fl_value_new_string("html"));
        break;
      }
    }
    if (gtk_targets_include_uri(atoms, n_atoms)) {
      fl_value_append_take(kinds, fl_value_new_string("files"));
    }
  }
  fl_method_call_respond_success(method_call, kinds, nullptr);
}

// What "write" put on the clipboard (added in Len's copy): a PNG and / or
// plain text, offered in every format GTK can convert them to.
struct ClipContent {
  GBytes *png;        // Or null.
  GdkPixbuf *pixbuf;  // [png] decoded, for other image formats; lazily.
  gchar *text;        // Or null.
};

enum ClipTarget : guint { kClipPng = 1, kClipImage = 2, kClipText = 3 };

static void clip_content_free(ClipContent *content) {
  if (content->png) g_bytes_unref(content->png);
  if (content->pixbuf) g_object_unref(content->pixbuf);
  g_free(content->text);
  delete content;
}

static GdkPixbuf *clip_content_pixbuf(ClipContent *content) {
  if (content->pixbuf || !content->png) return content->pixbuf;
  gsize size = 0;
  auto *data = static_cast<const guchar *>(g_bytes_get_data(content->png, &size));
  GdkPixbufLoader *loader = gdk_pixbuf_loader_new_with_type("png", nullptr);
  if (!loader) return nullptr;
  if (gdk_pixbuf_loader_write(loader, data, size, nullptr) &&
      gdk_pixbuf_loader_close(loader, nullptr)) {
    GdkPixbuf *pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
    if (pixbuf) content->pixbuf = GDK_PIXBUF(g_object_ref(pixbuf));
  } else {
    gdk_pixbuf_loader_close(loader, nullptr);
  }
  g_object_unref(loader);
  return content->pixbuf;
}

static void clip_content_get(GtkClipboard *clipboard,
                             GtkSelectionData *selection_data,
                             guint info,
                             gpointer user_data) {
  auto *content = static_cast<ClipContent *>(user_data);
  if (info == kClipPng && content->png) {
    gsize size = 0;
    auto *data = static_cast<const guchar *>(g_bytes_get_data(content->png, &size));
    gtk_selection_data_set(selection_data, gtk_selection_data_get_target(selection_data), 8,
                           data, static_cast<gint>(size));
  } else if (info == kClipImage) {
    GdkPixbuf *pixbuf = clip_content_pixbuf(content);
    if (pixbuf) gtk_selection_data_set_pixbuf(selection_data, pixbuf);
  } else if (info == kClipText && content->text) {
    gtk_selection_data_set_text(selection_data, content->text, -1);
  }
}

static void clip_content_clear(GtkClipboard *clipboard, gpointer user_data) {
  clip_content_free(static_cast<ClipContent *>(user_data));
}

// "write": {png?: Uint8List, text?: String} as one clipboard entry.
static void write_clipboard(FlMethodCall *method_call) {
  FlValue *args = fl_method_call_get_args(method_call);
  FlValue *png = nullptr;
  FlValue *text = nullptr;
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    png = fl_value_lookup_string(args, "png");
    text = fl_value_lookup_string(args, "text");
  }
  if (png != nullptr && fl_value_get_type(png) != FL_VALUE_TYPE_UINT8_LIST) png = nullptr;
  if (text != nullptr && fl_value_get_type(text) != FL_VALUE_TYPE_STRING) text = nullptr;
  if (png == nullptr && text == nullptr) {
    fl_method_call_respond_success(method_call, fl_value_new_bool(FALSE), nullptr);
    return;
  }

  auto *content = new ClipContent{nullptr, nullptr, nullptr};
  GtkTargetList *targets = gtk_target_list_new(nullptr, 0);
  if (png != nullptr) {
    content->png = g_bytes_new(fl_value_get_uint8_list(png), fl_value_get_length(png));
    // Every format GdkPixbuf can write, the PNG itself byte for byte.
    GdkAtom png_atom = gdk_atom_intern_static_string("image/png");
    gtk_target_list_add_image_targets(targets, kClipImage, TRUE);
    gtk_target_list_remove(targets, png_atom);
    gtk_target_list_add(targets, png_atom, 0, kClipPng);
  }
  if (text != nullptr) {
    content->text = g_strdup(fl_value_get_string(text));
    gtk_target_list_add_text_targets(targets, kClipText);
  }

  gint n_targets = 0;
  GtkTargetEntry *table = gtk_target_table_new_from_list(targets, &n_targets);
  auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
  gboolean done = gtk_clipboard_set_with_data(clipboard, table, static_cast<guint>(n_targets),
                                              clip_content_get, clip_content_clear, content);
  if (done) {
    // A clipboard manager may keep it once Len quits.
    gtk_clipboard_set_can_store(clipboard, nullptr, 0);
  } else {
    clip_content_free(content);
  }
  gtk_target_table_free(table, n_targets);
  gtk_target_list_unref(targets);
  fl_method_call_respond_success(method_call, fl_value_new_bool(done), nullptr);
}

// Called when a method call is received from Flutter.
static void pasteboard_plugin_handle_method_call(
    PasteboardPlugin *self,
    FlMethodCall *method_call) {
  const gchar *method = fl_method_call_get_name(method_call);
  if (strcmp(method, "files") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
    gtk_clipboard_request_uris(clipboard, gtk_clipboard_request_uris_callback, g_object_ref(method_call));
  } else if (strcmp(method, "writeFiles") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());

    auto args = fl_method_call_get_args(method_call);
    auto size = fl_value_get_length(args);

    auto **paths = new gchar *[size + 1];
    paths[size] = nullptr;
    for (unsigned int i = 0; i < size; ++i) {
      auto path = fl_value_get_string(fl_value_get_list_value(args, i));
      paths[i] = g_strconcat("file://", path, nullptr);
    }

    GtkTargetList *target_list = gtk_target_list_new(nullptr, 0);
    gtk_target_list_add(target_list, GNOME_COPIED_FILES, 0, 0);

    gtk_target_list_add_uri_targets(target_list, 0);
    gtk_target_list_add_text_targets(target_list, 0);

    int n_targets = 1;
    GtkTargetEntry *target_table = gtk_target_table_new_from_list(target_list, &n_targets);

    gtk_clipboard_set_with_data(clipboard,
                                target_table,
                                n_targets,
                                gtk_clipboard_get_file_uri,
                                gtk_clipboard_clear,
                                paths);

    gtk_target_list_unref(target_list);
    gtk_target_table_free(target_table, n_targets);

    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (strcmp(method, "image") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());

    gtk_clipboard_request_image(clipboard, clipboard_request_image_callback, g_object_ref(method_call));

  } else if (strcmp(method, "peek") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
    gtk_clipboard_request_targets(clipboard, clipboard_request_targets_callback,
                                  g_object_ref(method_call));
  } else if (strcmp(method, "write") == 0) {
    write_clipboard(method_call);
  } else if (strcmp(method, "html") == 0) {
    auto *clipboard = gtk_clipboard_get_default(gdk_display_get_default());
    gtk_clipboard_request_contents(clipboard, gdk_atom_intern_static_string("text/html"),
                                   clipboard_request_html_callback, g_object_ref(method_call));
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void pasteboard_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(pasteboard_plugin_parent_class)->dispose(object);
}

static void pasteboard_plugin_class_init(PasteboardPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = pasteboard_plugin_dispose;
}

static void pasteboard_plugin_init(PasteboardPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  PasteboardPlugin *plugin = PASTEBOARD_PLUGIN(user_data);
  pasteboard_plugin_handle_method_call(plugin, method_call);
}

void pasteboard_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  PasteboardPlugin *plugin = PASTEBOARD_PLUGIN(
      g_object_new(pasteboard_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "pasteboard",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
