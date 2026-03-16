#' Compute a Comprehensive Set of LiDAR Structural Metrics
#'
#' @description
#' Computes a comprehensive suite of LiDAR-derived forest structure metrics from
#' a normalized point cloud. Combines multiple metric families from the
#' \code{lidRmetrics} package — including height statistics, return structure,
#' rumple, voxel occupancy, kernel density, HOME, and texture — into a single
#' named list suitable for use with \code{\link[lidR]{pixel_metrics}}.
#'
#' @param x Numeric vector. Point x-coordinates (e.g., \code{X} column of a LAS object).
#' @param y Numeric vector. Point y-coordinates (e.g., \code{Y} column of a LAS object).
#' @param z Numeric vector. Normalized point heights (e.g., \code{Z} column of a
#'   height-normalized LAS object).
#' @param i Numeric vector. Point intensities (e.g., \code{Intensity} column).
#' @param ReturnNumber Integer vector. Return number for each point.
#' @param NumberOfReturns Integer vector. Total number of returns for the pulse
#'   associated with each point.
#' @param zmin Numeric. Minimum height threshold (meters) below which points are
#'   excluded from metric calculations. Default is \code{NA} (no threshold applied).
#' @param threshold Numeric vector. Height thresholds (meters) used to compute
#'   proportion-above metrics. Default is \code{c(2, 5)}.
#' @param dz Numeric. Vertical slice thickness (meters) for interval-based metrics.
#'   Default is \code{1}.
#' @param interval_count Integer. Number of equal-height intervals for vertical
#'   distribution metrics. Default is \code{10}.
#' @param zintervals Numeric vector. Custom height break points (meters) defining
#'   vertical strata for interval metrics. Default is
#'   \code{c(0, 0.15, 2, 5, 10, 20, 30)}.
#' @param pixel_size Numeric. Pixel resolution (meters) used internally for
#'   rumple and texture calculations. Default is \code{1}.
#' @param vox_size Numeric. Voxel size (meters) used for voxel occupancy metrics.
#'   Default is \code{1}.
#' @param KeepReturns Integer vector. Return numbers to retain for
#'   \code{metrics_echo2}. Default is \code{c(1, 2, 3, 4)}.
#' @param chm_algorithm Algorithm object. CHM algorithm passed to
#'   \code{metrics_texture}. If \code{NULL} (default), the function uses its
#'   internal default.
#'
#' @return A named list of numeric values, one element per metric. When used
#'   inside \code{\link[lidR]{pixel_metrics}}, the output is a multi-layer
#'   \code{SpatRaster} with one layer per metric. Metric families included:
#'   \itemize{
#'     \item \strong{set1} — Height percentiles, mean, sd, skewness, kurtosis,
#'       proportion above thresholds, and interval metrics (\code{metrics_set1})
#'     \item \strong{echo} — First/last/single return proportions (\code{metrics_echo})
#'     \item \strong{echo2} — Return-specific height statistics (\code{metrics_echo2})
#'     \item \strong{rumple} — Canopy surface complexity index (\code{metrics_rumple})
#'     \item \strong{vox} — Voxel occupancy and fill ratio (\code{metrics_voxels})
#'     \item \strong{kde} — Kernel density height distribution metrics (\code{metrics_kde})
#'     \item \strong{HOME} — Height of median energy, intensity-weighted (\code{metrics_HOME})
#'     \item \strong{texture} — GLCM texture metrics from a CHM (\code{metrics_texture})
#'   }
#'
#' @references
#' Tompalski, P. (2022). \emph{lidRmetrics: Metrics for the lidR package}.
#' R package. \url{https://github.com/ptompalski/lidRmetrics}
#'
#' Roussel, J.R., Auty, D., Coops, N.C., Tompalski, P., Goodbody, T.R.H.,
#' Meador, A.S., Bourdon, J.F., de Boissieu, F., Achim, A. (2020).
#' lidR: An R package for analysis of Airborne LiDAR Data.
#' \emph{Remote Sensing of Environment}, 251, 112061.
#' \doi{10.1016/j.rse.2020.112061}
#'
#' @seealso
#' \code{\link[lidR]{pixel_metrics}}, \code{\link[lidR]{normalize_height}},
#' \code{\link[lidR]{filter_poi}}
#'
#' @examples
#' \dontrun{
#' library(lidR)
#' library(lidRmetrics)
#'
#' # Load and prepare a tile
#' las <- readLAS("NEON_lidar_tile.laz")
#' las <- filter_poi(las, !Classification %in% c(18, 7))
#' las <- normalize_height(las, algorithm = tin())
#'
#' # Compute metrics at 20 m resolution
#' Master_raster <- pixel_metrics(
#'   las,
#'   ~master_metrics(X, Y, Z, Intensity, ReturnNumber, NumberOfReturns),
#'   res = 20
#' )
#'
#' # Inspect output
#' print(Master_raster)
#' names(Master_raster)
#' plot(Master_raster)
#' }
master_metrics <- function(x, y, z, i, ReturnNumber, NumberOfReturns,
                           zmin           = NA,
                           threshold      = c(2, 5),
                           dz             = 1,
                           interval_count = 10,
                           zintervals     = c(0, 0.15, 2, 5, 10, 20, 30),
                           pixel_size     = 1,
                           vox_size       = 1,
                           KeepReturns    = c(1, 2, 3, 4),
                           chm_algorithm  = NULL) {
  
  m_set1   <- lidRmetrics::metrics_set1(z = z, zmin = zmin, threshold = threshold,
                                        dz = dz, interval_count = interval_count,
                                        zintervals = zintervals)
  
  m_echo   <- lidRmetrics::metrics_echo(ReturnNumber = ReturnNumber,
                                        NumberOfReturns = NumberOfReturns,
                                        z = z, zmin = zmin)
  
  m_echo2  <- lidRmetrics::metrics_echo2(ReturnNumber = ReturnNumber,
                                         KeepReturns = KeepReturns,
                                         z = z, zmin = zmin)
  
  m_rumple <- lidRmetrics::metrics_rumple(x = x, y = y, z = z,
                                          pixel_size = pixel_size)
  
  m_vox    <- metrics_voxels(x = x, y = y, z = z,
                             vox_size = vox_size, zmin = zmin)
  
  m_kde    <- lidRmetrics::metrics_kde(z = z, zmin = zmin)
  
  m_HOME   <- lidRmetrics::metrics_HOME(z = z, i = i, zmin = zmin)
  
  mt       <- lidRmetrics::metrics_texture(x = x, y = y, z = z,
                                           pixel_size = pixel_size,
                                           zmin = zmin,
                                           chm_algorithm = chm_algorithm)
  
  m <- c(m_set1, m_echo, m_echo2, m_rumple, m_vox, m_kde, m_HOME, mt)
  return(m)
}