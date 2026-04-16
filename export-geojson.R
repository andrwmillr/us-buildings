# Export clipped building data as GeoJSON for deck.gl

library(sf)
library(dplyr)
library(tigris)

sf_use_s2(FALSE)
options(tigris_use_cache = TRUE)
zctas <- zctas(cb = TRUE, year = 2020)

# Boston
message("Exporting Boston...")
boston <- st_read("boston_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)
boston_zips <- c("02108", "02109", "02110", "02111", "02113", "02114", "02115", "02116",
                "02118", "02199", "02203", "02210", "02215", "02222")
boston_sel <- zctas %>% dplyr::filter(GEOID20 %in% boston_zips) %>% st_transform(st_crs(boston))
boston_clip <- st_intersection(boston_sel, boston) %>%
  mutate(height = ifelse(height < 0, 3, height)) %>%
  select(height, confidence)
st_write(boston_clip, "boston-buildings.geojson", delete_dsn = TRUE, quiet = TRUE)

# Glendale
message("Exporting Glendale...")
glendale <- st_read("glendale_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)
glendale_sel <- zctas %>% dplyr::filter(GEOID20 %in% c("85308")) %>% st_transform(st_crs(glendale))
glendale_clip <- st_intersection(glendale_sel, glendale) %>%
  mutate(height = ifelse(height < 0, 3, height)) %>%
  select(height, confidence)
st_write(glendale_clip, "glendale-buildings.geojson", delete_dsn = TRUE, quiet = TRUE)

message("Done!")
