library(lidR)
library(terra)
library(lidRmetrics)
library(Lmoments)
library(geometry)
library(future)
install.packages('ForestTools')

source("Master_metrics_function.R")

# --- parallel backend ---
plan(multisession, workers = 3)

# --- catalog setup ---
ctg <- readLAScatalog('I:/neon/2019/lidar/ClassifiedPointCloud/')
fns <- ctg@data$filename[1:5]
ctg <- readLAScatalog(fns)
plot(ctg)

opt_chunk_alignment(ctg) <- c(0, 0)
opt_filter(ctg)          <- '-thin_with_voxel 0.5'
opt_chunk_buffer(ctg)    <- 80 ####### CHANGED BC OF EDGE EFFECTS

plot(ctg, chunk_pattern = TRUE)

myfun <- function(las, res) {
  las          <- filter_poi(las, !Classification %in% c(LASNOISE, LASBUILDING, LASLOWPOINT))
  las          <- normalize_height(las, algorithm = tin())
  metric_stack <- pixel_metrics(
    las,
    ~master_metrics(X, Y, Z, Intensity, ReturnNumber, NumberOfReturns),
    res = res
  )
  return(metric_stack)
}

# HOW TO TROUBLESHOOT AND RUN A SIGNLE CHUNK.
# chunks = engine_chunks(ctg)
# chunks[1]
# chunk = chunks[[1]]
# las = readLAS(chunk)
# output = myfun(las, res=20)
# plot(output)

## RUN FOR ENTIRE MAP (subset test)
output <- lidR::catalog_map(ctg, myfun, res = 20)

# reset to sequential when done
plan(sequential)

# =============================================================================
# FULL CATALOG RUN — processes all tiles, saves each to disk, mosaics at end.
# catalog_apply writes one raster per tile via opt_output_files; terra::mosaic
# merges them into a single wall-to-wall stack.
# =============================================================================

ctg_full <- readLAScatalog('I:/neon/2019/lidar/ClassifiedPointCloud/')
opt_chunk_alignment(ctg_full) <- c(0, 0)
opt_filter(ctg_full)          <- '-thin_with_voxel 0.5'
opt_chunk_buffer(ctg_full)    <- 80
opt_output_files(ctg_full)    <- 'output/2019/{ID}'

plan(multisession, workers = 3)
catalog_map(ctg_full, myfun, res = 20)
#not saving output as anything bc it will output to folder

# mosaic all saved tiles into one raster
tile_files  <- list.files('output/2019', pattern = '\\.tif$', full.names = TRUE)
tile_rasts  <- lapply(tile_files, rast)
mosaic_full <- do.call(mosaic, c(tile_rasts, list(fun = 'mean')))
writeRaster(mosaic_full, 'output/2019_metrics.tif')
