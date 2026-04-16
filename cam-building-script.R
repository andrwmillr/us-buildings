# Building footprint map of Boston/Cambridge/Somerville
# Data: Microsoft GlobalMLBuildingFootprints (2026)
# Original inspiration: https://gist.github.com/etachov/a029c849c89ee3d4f7d59dda83f97ed2

library(tidyverse)
library(sf)
library(tigris)
sf_use_s2(FALSE)

# Download building footprints from Microsoft GlobalMLBuildingFootprints
# Data is partitioned by Bing Maps L9 quadkeys; these two cover the Boston metro area
quadkey_urls <- c(
  "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=UnitedStates/quadkey=030233212/part-00194-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
  "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=UnitedStates/quadkey=030233213/part-00118-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz"
)

if (!file.exists("boston_buildings.geojsonl")) {
  message("Downloading building footprints...")
  lines <- c()
  for (url in quadkey_urls) {
    tmp <- tempfile(fileext = ".csv.gz")
    download.file(url, tmp, quiet = TRUE)
    lines <- c(lines, readLines(gzfile(tmp)))
    unlink(tmp)
  }
  writeLines(lines, "boston_buildings.geojsonl")
}

# Read GeoJSON-L (one GeoJSON feature per line)
message("Reading building footprints...")
buildings <- st_read("boston_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

# Use tigris to get ZCTA boundaries (zip codes)
options(tigris_use_cache = TRUE)
zctas_national <- zctas(cb = TRUE, year = 2020)

# Boston peninsula: Beacon Hill, Downtown, North End, Back Bay, South End, Fenway, Chinatown
zips <- c("02108", "02109", "02110", "02111", "02113", "02114", "02115", "02116",
          "02118", "02199", "02203", "02210", "02215", "02222")

selected_zip <- zctas_national %>%
  filter(GEOID20 %in% zips) %>%
  st_transform(st_crs(buildings))

# Clip buildings to selected zip codes
message("Clipping buildings to selected zip codes...")
building_select <- st_intersection(selected_zip, buildings)

# Replace missing heights (-1) with NA; cap at 50m to maximize contrast
building_select <- building_select %>%
  mutate(height = ifelse(height < 0, NA, pmin(height, 50)))

# Plot color-coded by building height
boscamsom <- ggplot() +
  geom_sf(data = building_select, aes(fill = height), color = NA) +
  scale_fill_gradientn(
    colors = c("#1a0533", "#4a0c6b", "#a62098", "#e85362", "#fcae12", "#fcffa4"),
    na.value = "#0a0a0a",
    name = "Height (m)",
    limits = c(0, 50),
    breaks = c(0, 10, 20, 30, 40, 50),
    labels = c("0", "10", "20", "30", "40", "50+")
  ) +
  theme_void() +
  theme(panel.grid.major = element_line(colour = "transparent"),
        plot.background = element_rect(fill = "black", color = NA),
        panel.background = element_rect(fill = "black", color = NA),
        legend.text = element_text(color = "white", size = 10),
        legend.title = element_text(color = "white", size = 12))

ggsave("bos-cam-som-buildings.png", boscamsom, dpi = 400, width = 8, height = 5)
message("Done! Saved to bos-cam-som-buildings.png")
