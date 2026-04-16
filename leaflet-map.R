# Interactive leaflet maps with building footprints overlaid on real map tiles

library(sf)
library(dplyr)
library(tigris)
library(leaflet)
library(htmlwidgets)

sf_use_s2(FALSE)
options(tigris_use_cache = TRUE)

# --- Boston ---
message("Loading Boston buildings...")
boston_buildings <- st_read("boston_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

zctas <- zctas(cb = TRUE, year = 2020)
boston_zips <- c("02108", "02109", "02110", "02111", "02113", "02114", "02115", "02116",
                "02118", "02199", "02203", "02210", "02215", "02222")
boston_sel <- zctas %>%
  dplyr::filter(GEOID20 %in% boston_zips) %>%
  st_transform(st_crs(boston_buildings))

message("Clipping Boston...")
boston_clip <- st_intersection(boston_sel, boston_buildings) %>%
  mutate(height = ifelse(height < 0, NA, height))

# Height color palette
pal <- colorNumeric(
  palette = c("#1a0533", "#4a0c6b", "#a62098", "#e85362", "#fcae12", "#fcffa4"),
  domain = c(0, 50),
  na.color = "#666666"
)

message("Building Boston leaflet map...")
boston_map <- leaflet(boston_clip) %>%
  addProviderTiles(providers$CartoDB.DarkMatter) %>%
  addPolygons(
    fillColor = ~pal(pmin(height, 50)),
    fillOpacity = 0.8,
    weight = 0,
    popup = ~paste0("Height: ", round(height, 1), "m")
  ) %>%
  addLegend(pal = pal, values = c(0, 50), title = "Height (m)")

saveWidget(boston_map, "boston-leaflet.html", selfcontained = FALSE)
message("Saved boston-leaflet.html")

# --- Glendale ---
message("Loading Glendale buildings...")
glendale_buildings <- st_read("glendale_buildings.geojsonl", drivers = "GeoJSONSeq", quiet = TRUE)

glendale_sel <- zctas %>%
  dplyr::filter(GEOID20 %in% c("85308")) %>%
  st_transform(st_crs(glendale_buildings))

message("Clipping Glendale...")
glendale_clip <- st_intersection(glendale_sel, glendale_buildings) %>%
  mutate(height = ifelse(height < 0, NA, height))

pal_g <- colorNumeric(
  palette = c("#1a0533", "#4a0c6b", "#a62098", "#e85362", "#fcae12", "#fcffa4"),
  domain = c(0, 15),
  na.color = "#666666"
)

message("Building Glendale leaflet map...")
glendale_map <- leaflet(glendale_clip) %>%
  addProviderTiles(providers$CartoDB.DarkMatter) %>%
  addPolygons(
    fillColor = ~pal_g(pmin(height, 15)),
    fillOpacity = 0.8,
    weight = 0,
    popup = ~paste0("Height: ", round(height, 1), "m")
  ) %>%
  addLegend(pal = pal_g, values = c(0, 15), title = "Height (m)")

saveWidget(glendale_map, "glendale-leaflet.html", selfcontained = FALSE)
message("Saved glendale-leaflet.html")
message("Done! Open the HTML files in your browser.")
