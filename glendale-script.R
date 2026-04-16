# Building footprint map of Glendale, AZ
# Data: Microsoft GlobalMLBuildingFootprints (2026)

library(tidyverse)
library(sf)
library(tigris)

sf_use_s2(FALSE)

# Download building footprints — single quadkey covers Glendale area
quadkey_url <- "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=UnitedStates/quadkey=023102202/part-00124-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz"

if (!file.exists("glendale_buildings.geojsonl")) {
  message("Downloading building footprints...")
  tmp <- tempfile(fileext = ".csv.gz")
  download.file(quadkey_url, tmp, quiet = TRUE)
  lines <- readLines(gzfile(tmp))
  writeLines(lines, "glendale_buildings.geojsonl")
  unlink(tmp)
}

# Read GeoJSON-L
message("Reading building footprints...")
buildings <- st_read("glendale_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

# Use tigris to get ZCTA boundaries
options(tigris_use_cache = TRUE)
zctas_national <- zctas(cb = TRUE, year = 2020)

selected_zip <- zctas_national %>%
  filter(GEOID20 %in% c("85308")) %>%
  st_transform(st_crs(buildings))

# Clip buildings to selected zip code
message("Clipping buildings...")
building_select <- st_intersection(selected_zip, buildings)

# Plot figure-ground map
glendale <- ggplot() +
  geom_sf(data = building_select, fill = "black", color = NA) +
  theme_void() +
  theme(panel.grid.major = element_line(colour = "transparent"))

ggsave("glendale_az.png", glendale, dpi = 400, width = 8, height = 5)
message("Done! Saved to glendale_az.png")
