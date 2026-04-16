# Add a new city to the 3D building map
# Usage: Rscript add-city.R <city-name> <zip1,zip2,...>
# Example: Rscript add-city.R chicago 60601,60602,60603,60604,60605,60606,60607

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript add-city.R <city-name> <zip1,zip2,...>\n",
       "Example: Rscript add-city.R chicago 60601,60602,60603")
}

city_name <- tolower(args[1])
zips <- strsplit(args[2], ",")[[1]]

library(sf)
library(dplyr)
library(tigris)

sf_use_s2(FALSE)
options(tigris_use_cache = TRUE)

# Get zip code boundaries and find the bounding box
message("Getting zip code boundaries...")
zctas <- zctas(cb = TRUE, year = 2020)
selected <- zctas %>% dplyr::filter(GEOID20 %in% zips)

if (nrow(selected) == 0) stop("No matching zip codes found!")

bbox <- st_bbox(st_transform(selected, 4326))
message(sprintf("Bounding box: %.3f,%.3f to %.3f,%.3f",
                bbox["xmin"], bbox["ymin"], bbox["xmax"], bbox["ymax"]))

# Calculate L9 quadkeys covering the bounding box
lat_lon_to_quadkey <- function(lat, lon, level = 9) {
  sin_lat <- sin(lat * pi / 180)
  x <- ((lon + 180) / 360) * (2^level)
  y <- (0.5 - log((1 + sin_lat) / (1 - sin_lat)) / (4 * pi)) * (2^level)
  tile_x <- as.integer(x)
  tile_y <- as.integer(y)
  qk <- ""
  for (i in seq(level, 1)) {
    digit <- 0
    mask <- bitwShiftL(1L, i - 1L)
    if (bitwAnd(tile_x, mask) != 0) digit <- digit + 1
    if (bitwAnd(tile_y, mask) != 0) digit <- digit + 2
    qk <- paste0(qk, digit)
  }
  qk
}

# Get unique quadkeys for all corners and center
corners <- expand.grid(
  lat = seq(bbox["ymin"], bbox["ymax"], length.out = 3),
  lon = seq(bbox["xmin"], bbox["xmax"], length.out = 3)
)
quadkeys <- unique(mapply(lat_lon_to_quadkey, corners$lat, corners$lon))
message(sprintf("Need %d quadkey tile(s): %s", length(quadkeys), paste(quadkeys, collapse = ", ")))

# Download dataset index and find matching URLs
message("Fetching dataset index...")
index <- read.csv("https://minedbuildings.z5.web.core.windows.net/global-buildings/dataset-links.csv")
urls <- index$Url[index$Location == "UnitedStates" & index$QuadKey %in% quadkeys]

if (length(urls) == 0) stop("No matching tiles found in the dataset!")
message(sprintf("Downloading %d tile(s)...", length(urls)))

# Download and combine tiles
geojsonl_file <- paste0(city_name, "_buildings.geojsonl")
all_lines <- c()
for (url in urls) {
  tmp <- tempfile(fileext = ".csv.gz")
  download.file(url, tmp, quiet = TRUE)
  all_lines <- c(all_lines, readLines(gzfile(tmp)))
  unlink(tmp)
}
writeLines(all_lines, geojsonl_file)
message(sprintf("Downloaded %d buildings", length(all_lines)))

# Read, clip, and export
message("Clipping to selected zip codes...")
buildings <- st_read(geojsonl_file, drivers = "GeoJSONSeq", quiet = TRUE)
selected <- st_transform(selected, st_crs(buildings))
clipped <- st_intersection(selected, buildings) %>%
  mutate(height = ifelse(height < 0, 3, height)) %>%
  select(height, confidence)

outfile <- paste0(city_name, "-buildings.geojson")
st_write(clipped, outfile, delete_dsn = TRUE, quiet = TRUE)

# Calculate suggested config
center_lon <- mean(c(bbox["xmin"], bbox["xmax"]))
center_lat <- mean(c(bbox["ymin"], bbox["ymax"]))
max_h <- max(clipped$height, na.rm = TRUE)
suggested_max <- ceiling(max_h / 5) * 5

message(sprintf("\nDone! Exported %d buildings to %s", nrow(clipped), outfile))
message(sprintf("\nAdd this to CITIES in map.html:\n"))
message(sprintf("  '%s': {", city_name))
message(sprintf("    file: '%s',", outfile))
message(sprintf("    lng: %.4f, lat: %.4f, zoom: 13,", center_lon, center_lat))
message(sprintf("    maxHeight: %d", suggested_max))
message(sprintf("  }"))
