# 3D building height map of Glendale, AZ (85308)

library(tidyverse)
library(sf)
library(tigris)
library(rayshader)
library(raster)

sf_use_s2(FALSE)

# Read building footprints
message("Reading building footprints...")
buildings <- st_read("glendale_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

# Get zip code boundaries
options(tigris_use_cache = TRUE)
zctas_national <- zctas(cb = TRUE, year = 2020)

selected_zip <- zctas_national %>%
  dplyr::filter(GEOID20 %in% c("85308")) %>%
  st_transform(st_crs(buildings))

# Clip buildings
message("Clipping buildings...")
building_select <- st_intersection(selected_zip, buildings)

# Clean up heights
building_select <- building_select %>%
  mutate(height = ifelse(height < 0, 3, height))

# Project to UTM for proper meter-based rasterization
building_select <- st_transform(building_select, 32612) # UTM 12N for Arizona

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
colors <- colorRampPalette(c("#0a0a0a", "#1a0533", "#4a0c6b", "#a62098",
                              "#e85362", "#fcae12", "#fcffa4"))(256)

# Scale colors to 0-15m range for suburban buildings
color_matrix <- height_matrix
color_matrix[color_matrix > 15] <- 15

message("Rendering 3D...")
color_matrix %>%
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
render_snapshot("glendale-3d.png")
message("Done! Saved to glendale-3d.png")
message("Rotate with click+drag, zoom with scroll.")
