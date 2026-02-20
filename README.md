# Fractional Raster–Vector Clipping Operator

A database-native implementation of a **Fractional Raster–Vector Clipping Operator** for boundary-consistent and resolution-aware spatial aggregation.

This repository accompanies the paper:

> *A Fractional Raster–Vector Clipping Operator for Boundary-Consistent Multi-Scale Spatial Analysis*  


---

## Overview

Raster–vector clipping is a fundamental operation in geospatial analysis.  
Conventional implementations rely on binary inclusion rules (e.g., center-in-polygon or all-touched), which treat pixels as either fully inside or outside a target geometry. This discretization introduces **resolution-dependent boundary bias** during aggregation.

This repository provides:

- A formalized **fractional raster–vector clipping operator**
- A **PostgreSQL/PostGIS implementation**
- A boundary-localized algorithm that avoids universal containment tests
- Reproducible workflows for evaluating scale-dependent aggregation bias

The operator defines pixel contribution based on **proportional areal overlap**, enabling:

- Weighted aggregation
- Threshold-based categorical inclusion
- Resolution-consistent spatial analysis

---

## Key Features

- Formal mathematical definition of fractional overlap  
- Interior–boundary geometric decomposition using erosion  
- Efficient boundary-localized overlap computation  
- Dual-band raster output (thematic values + geometric weight)  
- Threshold-controlled inclusion semantics  
- Fully reproducible SQL workflows  



## Installation

### Requirements

- PostgreSQL ≥ 13  
- PostGIS ≥ 3 (with raster support enabled)  
- A database with raster functionality activated  

You can verify PostGIS installation with:

```sql
SELECT PostGIS_Version();
````

---

### Installing the Function

1. Clone this repository:

```bash
git clone https://github.com/yourusername/fractional_polygon_raster_clip.git
cd Code
```

2. Connect to your PostgreSQL database and execute the SQL file containing the function:

```bash
psql -d your_database -f functions/raster_fractional_boundary_clip.sql
```

Alternatively, you may copy and execute the function definition directly inside `psql` or pgAdmin.

Once executed successfully, the function `raster_fractional_boundary_clip` will be available in your database.

---

## Usage

### Function Signature

```sql
raster_fractional_boundary_clip(
    rast      raster,
    geom      geometry,
    threshold double precision DEFAULT 0.0,
    at_least  boolean DEFAULT TRUE
)
```

### Parameters

* `rast` — Input raster
* `geom` — Polygon geometry used for clipping
* `threshold` — Minimum (or maximum) fractional overlap in the range ([0,1])
* `at_least` —

  * `TRUE`: keep pixels with fraction ≥ threshold
  * `FALSE`: keep pixels with fraction ≤ threshold

---

## Basic Use Cases

### 1. Fully Fractional Clipping (Reference Model)

Include all intersecting pixels and compute fractional weights:

```sql
SELECT raster_fractional_boundary_clip(rast, geom, 0.0, TRUE)
FROM raster_table, polygon_table
WHERE polygon_table.id = 1;
```

* All intersecting pixels are retained.
* Boundary pixels receive proportional weights.
* Fully contained pixels have weight = 1.

---

### 2. Threshold-Based Inclusion (e.g., 60% Overlap)

Retain only pixels with at least 60% overlap:

```sql
SELECT raster_fractional_boundary_clip(rast, geom, 0.6, TRUE)
FROM raster_table, polygon_table
WHERE polygon_table.id = 1;
```

* Pixels with overlap ≥ 0.6 are included.
* Fully contained pixels (fraction = 1) are always included.
* Pixels below threshold are excluded (set to NULL).

---

### 3. Strict Containment (Equivalent to τ = 1)

```sql
SELECT raster_fractional_boundary_clip(rast, geom, 1.0, TRUE)
FROM raster_table, polygon_table
WHERE polygon_table.id = 1;
```

Only fully contained pixels are retained.

---

## Output

The function returns a two-band raster:

* **Band 1** — Thematic raster values (clipped result)
* **Band 2** — Fractional overlap weights

Interior pixels have weight = 1.
Boundary pixels have weight ( 0 < f \leq 1 ).
Excluded pixels are set to NULL in both bands.

---

## Notes

* The geometry is automatically transformed to the raster SRID.
* Performance is optimized by restricting intersection computation to boundary pixels only.
* The function is `IMMUTABLE` and `PARALLEL SAFE`.

---


Here is a well-structured Markdown section you can add to your README under a heading such as **Validation and Testing**. It explains the purpose of the scenarios clearly and organizes the SQL blocks logically.

---

````markdown
## Validation and Testing

To verify correctness and boundary behavior, a controlled 5×5 raster and a set of test polygons are constructed.  
These synthetic scenarios allow deterministic validation of:

- Exact fractional overlap values  
- Threshold behavior  
- Interior vs. boundary classification  
- Multi-pixel spans  
- Sub-pixel offsets  

---

## Scenario Construction

### 1. Create Temporary Test Tables

```sql
CREATE TEMP TABLE test_raster (rast raster);
CREATE TEMP TABLE test_geom (id serial PRIMARY KEY, geom geometry);
````

---

### 2. Generate a 5×5 Control Raster

A 5×5 raster with pixel size 1×1 (SRID 3857) and values 1–25.

```sql
INSERT INTO test_raster (rast)
SELECT
    ST_SetValues(
        ST_AddBand(
            ST_MakeEmptyRaster(5, 5, 0, 5, 1, -1, 0, 0, 3857),
            '32BF'::text, 0.0, NULL
        ),
        1, 1, 1,
        ARRAY[
            [ 1,  2,  3,  4,  5 ],
            [ 6,  7,  7,  9, 10 ],
            [11, 12, 13, 14, 15 ],
            [16, 17, 18, 19, 20 ],
            [21, 22, 23, 24, 25 ]
        ]::double precision[]
    );
```

Note: Pixel size = 1 × 1 → pixel area = 1.
This makes fractional interpretation straightforward.

---

### 3. Insert Test Geometries

Each geometry targets a specific overlap case.

```sql
INSERT INTO test_geom (geom) VALUES 
-- #1: 50% coverage of a single pixel
(ST_GeomFromText('POLYGON((1.0 4.0, 1.5 4.0, 1.5 3.0, 1.0 3.0, 1.0 4.0))', 3857)),

-- #2: 100% coverage of a single pixel
(ST_GeomFromText('POLYGON((2.0 4.0, 3.0 4.0, 3.0 3.0, 2.0 3.0, 2.0 4.0))', 3857)),

-- #3: 25% coverage
(ST_GeomFromText('POLYGON((1.5 3.5, 2.0 3.5, 2.0 3.0, 1.5 3.0, 1.5 3.5))', 3857)),

-- #4: Multi-pixel span
(ST_GeomFromText('POLYGON((1.0 3.0, 3.5 3.0, 3.5 1.0, 1.0 1.0, 1.0 3.0))', 3857)),

-- #5: Sub-pixel offset
(ST_GeomFromText('POLYGON((0.25 4.75, 0.75 4.75, 0.75 4.25, 0.25 4.25, 0.25 4.75))', 3857));
```

Additional complex polygons:

```sql
INSERT INTO test_geom (geom) VALUES 
(ST_GeomFromText('POLYGON((0.0 4.0, 3 4.0, 4 3, 4.5 2.5, 3 1, 0 1, 0 4))', 3857));

INSERT INTO test_geom (geom) VALUES 
(ST_GeomFromText('POLYGON((1 4.5, 4 4.5, 4.5 3.5, 4.25 2.25, 1 2.25, 1 4.5))', 3857));
```

---

## Boundary Pixel Inspection

The following query identifies pixels classified as boundary pixels
(i.e., pixels with fractional weight strictly between 0 and 1).

```sql
SELECT
    g.id AS geom_id,

    -- Global raster indices
    ST_WorldToRasterCoordX(tr.rast, ST_X(p.geom)) AS global_col,
    ST_WorldToRasterCoordY(tr.rast, ST_Y(p.geom)) AS global_row,

    -- Local clipped raster indices
    p.x AS local_col,
    p.y AS local_row,

    -- Original pixel value
    ST_Value(r.rast, 1, p.x, p.y) AS landcover_value,

    -- Fractional weight
    p.val AS fraction

FROM test_raster tr
JOIN test_geom g ON TRUE

CROSS JOIN LATERAL (
    SELECT raster_fractional_boundary_clip(tr.rast, g.geom, 0.0001) AS rast
) r

CROSS JOIN LATERAL
    ST_PixelAsPoints(r.rast, 2) AS p

WHERE
    p.val IS NOT NULL
    AND p.val > 0.0
    AND p.val < 1.0

ORDER BY g.id, global_row, global_col;
```

---

## Expected Validation Behavior

* Geometry #1 should produce a fractional value ≈ 0.5
* Geometry #2 should produce a weight = 1
* Geometry #3 should produce a weight ≈ 0.25
* Multi-pixel geometries should produce a mix of:

  * Fully interior pixels (weight = 1)
  * Boundary pixels (0 < weight < 1)
* Sub-pixel offsets should verify geometric precision

These scenarios allow step-by-step verification of:

* Fraction correctness
* Threshold filtering
* Interior–boundary separation
* Band consistency (no ghost weights)

---

This controlled setup ensures deterministic testing of the fractional raster–vector clipping operator before applying it to large-scale datasets. 

```


