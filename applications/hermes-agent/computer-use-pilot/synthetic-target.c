#include <gtk/gtk.h>
#include <atk-bridge.h>

static void activate(GtkApplication *app, gpointer user_data) {
  (void)user_data;

  GtkWidget *window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "Hermes Synthetic Accessibility Target");
  gtk_window_set_default_size(GTK_WINDOW(window), 520, 520);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_container_set_border_width(GTK_CONTAINER(box), 18);
  gtk_container_add(GTK_CONTAINER(window), box);

  GtkWidget *heading = gtk_label_new("Synthetic accessibility fixture v1");
  gtk_widget_set_name(heading, "fixture-heading");
  gtk_box_pack_start(GTK_BOX(box), heading, FALSE, FALSE, 0);

  GtkWidget *entry = gtk_entry_new();
  gtk_entry_set_text(GTK_ENTRY(entry), "pilot-value");
  gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "Synthetic text field");
  gtk_widget_set_tooltip_text(entry, "Fixed non-sensitive pilot value");
  gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 0);

  GtkWidget *check = gtk_check_button_new_with_label("Pilot checkbox enabled");
  gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(check), TRUE);
  gtk_box_pack_start(GTK_BOX(box), check, FALSE, FALSE, 0);

  GtkWidget *combo = gtk_combo_box_text_new();
  gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(combo), "alpha", "Alpha option");
  gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(combo), "beta", "Beta option");
  gtk_combo_box_set_active_id(GTK_COMBO_BOX(combo), "beta");
  gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);

  GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0.0, 10.0, 1.0);
  gtk_range_set_value(GTK_RANGE(scale), 7.0);
  gtk_box_pack_start(GTK_BOX(box), scale, FALSE, FALSE, 0);

  GtkWidget *button = gtk_button_new_with_label("Synthetic action button");
  gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);

  GtkWidget *disabled = gtk_button_new_with_label("Disabled synthetic button");
  gtk_widget_set_sensitive(disabled, FALSE);
  gtk_box_pack_start(GTK_BOX(box), disabled, FALSE, FALSE, 0);

  GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_widget_set_vexpand(scroll, TRUE);
  GtkWidget *text = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(text), FALSE);
  GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text));
  gtk_text_buffer_set_text(buffer,
      "Synthetic line one.\nSynthetic line two.\nSynthetic line three.", -1);
  gtk_container_add(GTK_CONTAINER(scroll), text);
  gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);

  GtkWidget *status = gtk_label_new("Fixture status: ready");
  gtk_box_pack_start(GTK_BOX(box), status, FALSE, FALSE, 0);

  gtk_widget_show_all(window);
}

int main(int argc, char **argv) {
  g_set_prgname("hermes-computer-use-synthetic-target");
  g_set_application_name("Hermes Computer Use Synthetic Target");
  atk_bridge_adaptor_init(&argc, &argv);

  GtkApplication *app = gtk_application_new(
      "com.yus314.HermesComputerUseSyntheticTarget",
      G_APPLICATION_NON_UNIQUE);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  atk_bridge_adaptor_cleanup();
  return status;
}
