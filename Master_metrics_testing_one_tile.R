library(lidR)
library(terra)
library(lidRmetrics)
library(Lmoments)
install.packages("geometry")

source("Master_metrics_function.R")

las <- readLAS("NEON_lidar_tile.laz", filter = "-keep_random_fraction 0.5")
las <- filter_poi(las, !Classification %in% c(18,17))
las <- normalize_height(las, algorithm = tin())

metric_stack <- pixel_metrics(las, ~master_metrics(X, Y, Z, Intensity, ReturnNumber, NumberOfReturns),
                              res = 20)
names(metric_stack)
#108 different layers
plot(metric_stack)

par(mfrow = c(1, 2))
plot(metric_stack[["pzabovemean"]])
plot(metric_stack[["zentropy"]])
#seem to be negatively correlated -- areas where most points are above 
#the mean won't have a super high vertical complexity
#NA points in zentropy are likely a result of the ground being removed
#before vertical complexity is calculated, so there will be NAs in locations
#where there is only ground 
     