library(lidR)
library(terra)
library(lidRmetrics)
#pak::pak('ptompalski/lidRmetrics')
library(Lmoments)
library(geometry)

source("Master_metrics_function.R")

# Load tile, thin for speed while exploring
las <- readLAS("NEON_lidar_tile.laz", filter = "-keep_random_fraction 0.1")

# Remove vendor-classified noise
las <- filter_poi(las, !Classification %in% c(18, 7)) # 18 = LASNOISE, 7 = LASLOWPOINT

# Normalize heights
las <- normalize_height(las, algorithm = tin())

# Compute metrics at 20 m resolution
metric_stack <- pixel_metrics(las,
                              ~master_metrics(X, Y, Z, Intensity,
                                              ReturnNumber, NumberOfReturns),
                              res = 20)

# Inspect the output
print(metric_stack)
names(metric_stack)

# Plot all layers at once
plot(metric_stack)

# Or examine a single metric by name: comparing rumple and open gap for discussion
plot(metric_stack[["vzrumple"]])
plot(metric_stack[["OpenGapSpace"]])
