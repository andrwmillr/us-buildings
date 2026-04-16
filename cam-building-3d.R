# 3D building height map of Boston's historic core
# Uses rayshader to extrude building heights

library(tidyverse)
library(sf)
library(tigris)
library(rayshader)
library(raster)

sf_use_s2(FALSE)

# Read building footprints
message("Reading building footprints...")
buildings <- st_read("boston_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

# Get zip code boundaries
options(tigris_use_cache = TRUE)
zctas_national <- zctas(cb = TRUE, year = 2020)

zips <- c("02108", "02109", "02110", "02111", "02113", "02114", "02115", "02116",
          "02118", "02199", "02203", "02210", "02215", "02222")

selected_zip <- zctas_national %>%
  filter(GEOID20 %in% zips) %>%
  st_transform(st_crs(buildings))

# Clip buildings
message("Clipping buildings...")
building_select <- st_intersection(selected_zip, buildings)

# Clean up heights and cap
building_select <- building_select %>%
  mutate(height = ifelse(height < 0, 3, height))

# Project to UTM for proper meter-based rasterization
building_select <- st_transform(building_select, 32619)
bbox <- st_bbox(building_select)

# Rasterize building heights at ~5m resolution
message("Rasterizing building heights...")
res <- 5
r <- raster(xmn = bbox["xmin"], xmx = bbox["xmax"],
            ymn = bbox["ymin"], ymx = bbox["ymax"],
            res = res)
height_raster <- rasterize(building_select, r, field = "height", fun = max, background = 0)
height_matrix <- t(raster::as.matrix(height_raster))
height_matrix[is.na(height_matrix)] <- 0

# Color by height
message("Rendering 3D...")
colors <- colorRampPalette(c("#0a0a0a", "#1a0533", "#4a0c6b", "#a62098",
                              "#e85362", "#fcae12", "#fcffa4"))(256)
height_color <- height_matrix
height_color[height_color > 50] <- 50
color_idx <- floor(height_color / 50 * 255) + 1
color_idx[color_idx > 256] <- 256
rgb_array <- array(0, dim = c(nrow(height_matrix), ncol(height_matrix), 3))
for (i in 1:nrow(height_matrix)) {
  for (j in 1:ncol(height_matrix)) {
    col <- col2rgb(colors[color_idx[i, j]]) / 255
    rgb_array[i, j, ] <- col
  }
}

height_matrix %>%
  height_shade(texture = colors) %>%
  plot_3d(height_matrix,
          zscale = 0.5,
          solid = FALSE,
          shadow = FALSE,
          soliddepth = 0,
          background = "black",
          windowsize = c(1400, 900),
          zoom = 0.5,
          theta = -30,
          phi = 35)

Sys.sleep(1)
render_snapshot("bos-buildings-3d.png")
message("Done! Saved to bos-buildings-3d.png")
message("Rotate with click+drag, zoom with scroll. Press ESC or close the window when done.")
