/*
 * gerbv-render: Render Gerber/Excellon files to PNG using libgerbv.
 *
 * Usage:
 *   gerbv-render <output.png> <width> <height> [--dpi N] [--bg RRGGBB] <file1.gbr> [file2.gbr] ...
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gerbv.h>

static const guint32 layer_colors[] = {
    0xFF0000FF, 0x00FF00FF, 0xFFFF00FF, 0x0000FFFF,
    0xFF00FFFF, 0x00FFFFFF, 0xFF8000FF, 0x8000FFFF,
};
#define NUM_COLORS (sizeof(layer_colors) / sizeof(layer_colors[0]))

int main(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: gerbv-render <output.png> <width> <height> [--dpi N] [--bg RRGGBB] <file1.gbr> ...\n");
        return 1;
    }

    const char *output_path = argv[1];
    int width = atoi(argv[2]);
    int height = atoi(argv[3]);
    int dpi = 300;
    guint32 bg_color = 0x000000FF;

    if (width < 1 || height < 1 || width > 8000 || height > 8000) {
        fprintf(stderr, "Error: width/height must be 1-8000\n");
        return 1;
    }

    const char *files[64];
    int file_count = 0;
    int i = 4;

    while (i < argc) {
        if (strcmp(argv[i], "--dpi") == 0 && i + 1 < argc) {
            dpi = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--bg") == 0 && i + 1 < argc) {
            unsigned int r, g, b;
            if (sscanf(argv[++i], "%02x%02x%02x", &r, &g, &b) == 3) {
                bg_color = (r << 24) | (g << 16) | (b << 8) | 0xFF;
            }
        } else {
            if (file_count < 64) files[file_count++] = argv[i];
        }
        i++;
    }

    if (file_count == 0) {
        fprintf(stderr, "Error: no input files specified\n");
        return 1;
    }

    gerbv_project_t *project = gerbv_create_project();
    if (!project) {
        fprintf(stderr, "Error: failed to create gerbv project\n");
        return 1;
    }

    /* Set background */
    project->background.red = ((bg_color >> 24) & 0xFF) * 257;
    project->background.green = ((bg_color >> 16) & 0xFF) * 257;
    project->background.blue = ((bg_color >> 8) & 0xFF) * 257;

    /* Load files */
    for (int f = 0; f < file_count; f++) {
        gerbv_open_layer_from_filename(project, (gchar *)files[f]);
        if (project->file[f] && project->file[f]->image) {
            guint32 color = layer_colors[f % NUM_COLORS];
            project->file[f]->color.red = ((color >> 24) & 0xFF) * 257;
            project->file[f]->color.green = ((color >> 16) & 0xFF) * 257;
            project->file[f]->color.blue = ((color >> 8) & 0xFF) * 257;
            project->file[f]->alpha = 65535;
            project->file[f]->isVisible = TRUE;
        } else {
            fprintf(stderr, "Warning: failed to load %s\n", files[f]);
        }
    }

    /* Use gerbv's built-in export which handles zoom-to-fit correctly */
    gerbv_export_png_file_from_project_autoscaled(
        project, width, height, (gchar *)output_path
    );

    printf("%s\n", output_path);
    gerbv_destroy_project(project);
    return 0;
}
