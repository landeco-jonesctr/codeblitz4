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
# chunk = chunks[[4]]
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
opt_output_files(ctg_full)    <- 'output/2019/{XLEFT}_{YBOTTOM}'
opt_stop_early(ctg_full)    <- FALSE

plan(multisession, workers = 3)
catalog_map(ctg_full, myfun, res = 20)
#not saving output as anything bc it will output to folder

# mosaic all saved tiles into one raster
tile_files  <- list.files('output/2019', pattern = '\\.tif$', full.names = TRUE)
tile_rasts  <- lapply(tile_files, rast)
mosaic_full <- do.call(mosaic, c(tile_rasts, list(fun = 'mean')))
writeRaster(mosaic_full, 'output/2019_metrics.tif', overwrite = TRUE)

# =============================================================================
# RE-RUN RESUME/SKIP — only process tiles that don't have a tif yet.
# Use this if the run was interrupted and you want to pick up where you left off.
# {XLEFT}_{YBOTTOM} gives each chunk a stable name from its lower-left corner,
# which is consistent no matter how the catalog is subsetted.
# =============================================================================

ctg_full <- readLAScatalog('I:/neon/2019/lidar/ClassifiedPointCloud/')


# build the expected output filename for every chunk (same formula as above)
chunks   <- engine_chunks(ctg_full)

expected <- sapply(chunks, function(c)
  paste0('output/2019/', c@bbox[1,1], '_', c@bbox[2,1], '.tif'))

# find which chunks still need to run
todo_rows <- which(!file.exists(expected))
cat('Tiles remaining:', length(todo_rows), 'of', length(chunks), '\n')

# subset catalog to only unfinished tiles
ctg_resume <- ctg_full[todo_rows, ]
opt_filter(ctg_resume)       <- '-thin_with_voxel 0.5'
opt_chunk_buffer(ctg_resume) <- 80
opt_output_files(ctg_resume) <- 'output/2019/{XLEFT}_{YBOTTOM}'
opt_stop_early(ctg_full)    <- FALSE

plan(multisession, workers = 2)
catalog_map(ctg_resume, myfun, res = 20)
plan(sequential)

# mosaic ALL tiles (done + newly finished)
tile_files  <- list.files('output/2019', pattern = '\\.tif$', full.names = TRUE)
tile_rasts  <- lapply(tile_files, rast)
mosaic_full <- do.call(mosaic, c(tile_rasts, list(fun = 'mean')))
plot(mosaic_full[[99]])
writeRaster(mosaic_full, 'output/2019_metrics.tif', overwrite = TRUE)
