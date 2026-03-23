# codeblitz4: Scaling Lidar Feature Extraction with LAScatalog

---

## 🎯 Learning Objectives

By the end of this Code Blitz, you should be able to:

- Run the lab's `master_metrics` function on a single lidar tile and interpret the raster stack output
- Understand the structure of a `LAScatalog` and why it matters for landscape-scale analysis
- Apply the master metrics function across an entire tiled dataset using `catalog_map()`
- Produce aligned, multi-year raster stacks suitable for machine learning
- Collaborate using Git branches, commits, and pull requests

---

## 📋 Background

> 📖 **Before starting**, review [codeblitz3](https://github.com/landeco-jonesctr/codeblitz3) to refresh your memory on lidar metrics and the `lidRmetrics` package. Also read through [Module 6: Parallel Processing with LAScatalog](https://lab.jonesctr.org/module-6-speed-up-your-analyses-parallel-processing-with-lascatalog/) on the lab website — Exercise 2 builds directly on those concepts.

In our last Code Blitz, we explored feature families from the `lidRmetrics` package and computed individual metrics on a single tile. Now we scale up.

Real landscapes are not one tile. The Ichauway lidar dataset covers many thousands of hectares, delivered as a grid of tiled `.laz` files. Processing these one at a time by hand would be slow, error-prone, and hard to reproduce. The `LAScatalog` engine in `lidR` solves this: it lets you write processing logic once and apply it efficiently across an entire tiled dataset, handling tile buffering, parallel execution, and output stitching automatically.

We also have lidar acquisitions from **multiple years** (2014, 2016, 2017, 2018, 2019, 2021, 2023). The long-term goal is to use the full multi-year raster stack as input features in a **random forest model** to predict aspects of forest structure — basal area, canopy cover, stem density — across the Ichauway landscape. For that to work, every annual output must share the same spatial grid. Even small misalignments between years will corrupt any pixel-wise comparison or model prediction.

---

## ⚙️ Exercise 1: Run the Master Metrics Function on a Single Tile (20–25 min)

### Setup

Clone the repository and create your own branch before starting:

```bash
git clone https://github.com/landeco-jonesctr/codeblitz4.git
cd codeblitz4
git checkout -b yourname-exercise1
```

Load required packages:

```r
library(lidR)
library(terra)
library(lidRmetrics)
library(Lmoments)

source("Master_metrics_function.R")
```

> 🛑 **Instructor pause** — before running anything, open `Master_metrics_function.R` as a group and walk through it line by line with the team that wrote it. Have them explain each metric family, what arguments are being passed, and why. Also take a moment to look at the [roxygen2](https://roxygen2.r-lib.org/articles/roxygen2.html) notation in the header — this is the standard way R package functions are documented and is worth understanding early.

### Load and Prepare a Single Tile

```r
# Load tile, thin for speed while exploring
las <- readLAS("NEON_lidar_tile.laz", filter = "-keep_random_fraction 0.5")

# Remove vendor-classified noise
las <- filter_poi(las, !Classification %in% c(18, 7)) # 18 = LASNOISE, 7 = LASLOWPOINT

# Normalize heights
las <- normalize_height(las, algorithm = tin())
```

### Run the Master Metrics Function

`master_metrics` takes a normalized `LAS` object and returns a named list of metrics. Wrapped inside `pixel_metrics()`, it produces a multi-layer `SpatRaster` — one layer per metric.

```r
# Compute metrics at 20 m resolution
metric_stack <- pixel_metrics(las,
                              ~master_metrics(X, Y, Z, Intensity,
                                             ReturnNumber, NumberOfReturns),
                              res = 20)

# Inspect the output
print(metric_stack)
names(metric_stack)
```

### Visualize the Output

```r
# Plot all layers at once
plot(metric_stack)

# Or examine a single metric by name
plot(metric_stack[["zq75"]])   # replace with any layer name
```

### Team Discussion Questions

Work through these with your partner before moving on:

1. How many layers does the stack contain? What metric families are represented?
2. Pick two layers that you expect to be correlated. Plot them side by side. Are they? Why or why not?
3. Are there any layers with a lot of `NA` cells? What might cause that?

### Commit Your Work

You can run these from the `Terminal` tab in RStudio:

```bash
git add your_script.R
git commit -m "exercise 1 - single tile metrics"
git push origin yourname-exercise1
```

---

## 🗺️ Exercise 2: Scaling Up with LAScatalog (25–30 min)

### What is a LAScatalog?

A `LAScatalog` is not a loaded point cloud — it is a **catalog of pointers** to `.laz` files on disk. `lidR` reads only the file headers to build a spatial index, so you can work with hundreds of tiles covering large areas without ever loading everything into memory at once. When you run a function, the engine pulls in only the data it needs for each chunk, processes it, writes the output to disk, and moves on.

Each team will work with a different acquisition year during this exercise. Use the path for your assigned year:

| Team | Year | Path |
|------|------|------|
| Team 1 | 2014 | `I:/neon/2014/lidar/Classified_point_cloud/` |
| Team 2 | 2017 | `I:/neon/2017/lidar/ClassifiedPointCloud/` |
| Team 3 | 2019 | `I:/neon/2019/lidar/ClassifiedPointCloud/` |

```r
# Replace the path with your team's assigned year (check 2014 folder name if you're Team 1)
ctg <- readLAScatalog("I:/neon/2014/lidar/ClassifiedPointCloud/")

# Inspect the catalog — note it never loads the points
print(ctg)
plot(ctg)                    # tile footprints
plot(ctg, mapview = TRUE)    # interactive map with basemap (requires mapview package)
```

Take a moment to read the `print()` output. How many files are there? How many points total? What is the point density? Jot these down — you will compare them across years at the end of the session.

### Index the Files

Before processing, each `.laz` file needs a spatial index (`.lax`) so `lidR` can quickly find the points inside any chunk boundary. This has already been done for all NEON years on the lab drive, so you should see the "nothing to do" message below. The code is here for reference and future use:

```r
library(rlas)

lazfiles <- list.files("I:/neon/2014/lidar/ClassifiedPointCloud/",  # update for your year
                       pattern = ".las$|.laz$", full.names = TRUE)

# Only index files that don't already have a .lax companion
missing_lax <- lazfiles[!file.exists(sub("\\.la[sz]$", ".lax", lazfiles))]

if (length(missing_lax) == 0) {
  message("All files already indexed — nothing to do.")
} else {
  message(length(missing_lax), " file(s) missing a .lax index. Writing now...")
  for (f in missing_lax) writelax(f)
  message("Done.")
}
```

### Configure Chunk and Processing Options

Rather than processing tile-by-tile along the original file boundaries, the catalog engine lets you define your own chunk grid. This is powerful: you can choose a chunk size that balances memory use and processing time, snap chunks to a round-number origin so outputs align across years, and add a buffer to handle edge effects.

```r
library(future)

# Define chunk size (in CRS units — meters here)
opt_chunk_size(ctg)      <- 1000     # 1000 x 1000 m chunks

# Buffer to avoid edge artifacts — points from neighboring chunks
# are pulled in during processing, then automatically trimmed from output
opt_chunk_buffer(ctg)    <- 20

# Snap chunk origins to round numbers so all years align on the same grid
opt_chunk_alignment(ctg) <- c(0, 0)

# Thin data to speed up processing while you test
opt_filter(ctg)          <- "-thin_with_voxel 0.5"

# Name each output chunk by its spatial coordinates — unique and informative
opt_output_files(ctg)    <- "output/metrics/{XLEFT}_{YBOTTOM}"

# Enable parallel processing
plan(multisession, workers = 4)   # adjust to your machine

# Visualize the chunk layout before running
plot(ctg, chunk_pattern = TRUE)
```

> **Why `opt_chunk_alignment(ctg) <- c(0, 0)`?** This snaps all chunk corners to a grid anchored at the origin. As long as every year's catalog uses the same alignment and chunk size, the output rasters will share identical pixel origins — no resampling needed to compare years.

> **Why `{XLEFT}_{YBOTTOM}` for output filenames?** Naming by coordinates is unique, reproducible, and tells you exactly where each chunk sits on the landscape.

> **Why buffer?** Metrics near a chunk edge can be distorted if the point cloud is abruptly cut off. The 20 m buffer pulls in neighboring points during computation, then `lidR` automatically trims them back so there is no overlap in the output.

We'll use the settings above for the actual run, but experiment first with a few different values for `opt_chunk_size()` and `opt_chunk_buffer()` and re-run `plot(ctg, chunk_pattern = TRUE)`. What changes?

### Apply the Master Metrics Function with `catalog_map`

> 🛑 **Instructor pause** — read through `?catalog_map` as a group before running. Note that unlike `catalog_apply`, `catalog_map` is designed specifically for functions that take a LAS chunk and return a raster — it handles reading, buffering, writing, and stitching automatically. See `?catalog_apply` for the more flexible (but lower-level) alternative.

`catalog_map` passes each chunk to your function as an already-loaded `LAS` object — you do not call `readLAS()` yourself. The function body is identical to what you ran on a single tile in Exercise 1:

```r
metrics_wrapper <- function(las) {
  las <- filter_poi(las, !Classification %in% c(18, 7))
  las <- normalize_height(las, algorithm = tin())
  metric_stack <- pixel_metrics(las,
                                ~master_metrics(X, Y, Z, Intensity,
                                               ReturnNumber, NumberOfReturns),
                                res = 20)
  return(metric_stack)
}

# Run across the full catalog — one .tif per chunk written to disk automatically
catalog_map(ctg, metrics_wrapper)

# Load all chunk .tifs, mosaic into one raster, and save
chunk_files <- list.files("output/metrics/", pattern = "\\.tif$", full.names = TRUE)
chunk_list  <- lapply(chunk_files, terra::rast)
mosaic      <- do.call(terra::mosaic, chunk_list)

terra::writeRaster(mosaic, "output/metrics_2014.tif", overwrite = TRUE)

# Check your output
print(mosaic)
plot(mosaic)
```

Once `catalog_map` finishes, the individual chunk `.tif` files sit in your output folder. Loading them all into a list, mosaicking, and saving gives you one clean raster per year — a format that is easy to verify, share, and load next session.

### Team Discussion Questions

> 💡 While the catalog runs on one teammate's computer, others can use their consoles to work through these questions.

1. Open `plot(ctg, chunk_pattern = TRUE)`. How does the chunk grid relate to the original tile boundaries? What happens if the landscape edge doesn't divide evenly into your chunk size?
2. What is the difference between `catalog_map` and `catalog_apply`? When would you use each?
3. What would happen if two teams used different `opt_chunk_alignment()` values when processing different years? Would their outputs still align?

### Commit Your Work

```bash
git add your_catalog_script.R
git commit -m "exercise 2 - catalog_map across landscape"
git push origin yourname-exercise1
```

---

## 🏠 Homework: Multi-Year Raster Stack (Complete Before Next Session)

### Overview

Each team will be assigned **multiple acquisition years** to process independently using the `catalog_map` workflow from Exercise 2. At the next session, we will combine all years into a single multi-temporal feature stack and use it as input to a **random forest model** to predict forest structure attributes — basal area, canopy cover, and stem density — across the Ichauway landscape.

For this to work, **every team's outputs must snap together perfectly**. If everyone uses the same `opt_chunk_size`, `opt_chunk_alignment`, and `res` values, the outputs will automatically share the same pixel grid — no manual resampling or mosaicking needed. **Do not change these values.**

| Setting | Required value |
|---|---|
| `opt_chunk_size` | `1000` |
| `opt_chunk_alignment` | `c(0, 0)` |
| `opt_chunk_buffer` | `20` |
| `res` inside `pixel_metrics` | `20` |

### Your Assignment

All seven acquisition years need to be processed. Each team continues with the year they started in Exercise 2, then adds the remaining years assigned to them in series:

| Team | Exercise 2 year | Homework years |
|------|-----------------|----------------|
| Team 1 | 2014 | 2014, 2016 |
| Team 2 | 2017 | 2017, 2018 |
| Team 3 | 2019 | 2019, 2021, 2023 |

> 💡 You already ran your Exercise 2 year during class. If your output file is saved from that run, you can skip re-processing it and move straight to the next year.

### Step 1 — Set Up Your Catalog

```r
year <- 2014   # change for each of your assigned years

ctg_year <- readLAScatalog(paste0("I:/neon/", year, "/lidar/ClassifiedPointCloud/"))

opt_chunk_size(ctg_year)      <- 1000
opt_chunk_buffer(ctg_year)    <- 20
opt_chunk_alignment(ctg_year) <- c(0, 0)
opt_filter(ctg_year)          <- "-thin_with_voxel 0.5"
opt_output_files(ctg_year)    <- paste0("output/", year, "/metrics/{XLEFT}_{YBOTTOM}")

plan(multisession, workers = 4)
```

### Step 2 — Run `catalog_map` and Mosaic

Use the same `metrics_wrapper` from Exercise 2:

```r
catalog_map(ctg_year, metrics_wrapper)

# Load all chunk .tifs, mosaic into one raster, and save with a consistent filename
chunk_files <- list.files(paste0("output/", year, "/metrics/"),
                          pattern = "\\.tif$", full.names = TRUE)
chunk_list  <- lapply(chunk_files, terra::rast)
mosaic      <- do.call(terra::mosaic, chunk_list)

terra::writeRaster(mosaic,
                   filename  = paste0("output/metrics_", year, ".tif"),
                   overwrite = TRUE)

# Check your output
print(mosaic)
plot(mosaic)
```

Repeat Steps 1–2 for each of your assigned years before moving to Step 3.

### Step 3 — Commit and Submit

Create a single branch for all your team's years, commit your script and all output rasters, push, and open a pull request. Example for Team 1:

```bash
git checkout -b homework-team1
git add your_homework_script.R \
        output/metrics_2014.tif \
        output/metrics_2016.tif
git commit -m "homework - team 1 metrics rasters 2014 2016"
git push origin homework-team1
```

### What We Will Do With Your Output Next Session

Because everyone used the same chunk alignment and resolution, loading all years into a single stack is as simple as:

```r
year_files <- list.files("output/", pattern = "metrics_\\d{4}\\.tif$", full.names = TRUE)
year_stack <- terra::rast(year_files)
```

No resampling, no mosaicking — they already snap. This stack becomes the feature set for our random forest models linking lidar structure metrics to field-measured forest attributes across the Ichauway landscape.
