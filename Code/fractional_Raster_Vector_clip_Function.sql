
------ Check if the function ST_Clip with touched argument exist in the installation of postgis


CREATE OR REPLACE FUNCTION raster_fractional_boundary_clip(
    rast        raster,
    geom        geometry,
    threshold   double precision DEFAULT 0.0,
    at_least    boolean DEFAULT TRUE
)
RETURNS raster
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS
$$
DECLARE
    geom_proj   geometry;
    geom_env    geometry;

    rast_env    raster;
    rast_out    raster;

    px_w        double precision;
    px_h        double precision;
    px_area     double precision;
    r_minkowski double precision;

    geom_inner  geometry;
    geom_bound  geometry;

    p           record;

    band2_fixed raster;
BEGIN

    ------------------------------------------------------------
    -- 0. Validate threshold
    ------------------------------------------------------------
    IF threshold < 0 OR threshold > 1 THEN
        RAISE EXCEPTION 'threshold must be in [0,1], got %', threshold;
    END IF;

    ------------------------------------------------------------
    -- 1. Align geometry to raster SRID
    ------------------------------------------------------------
    geom_proj := ST_MakeValid(ST_Transform(geom, ST_SRID(rast)));
    geom_env  := ST_Envelope(geom_proj);

    ------------------------------------------------------------
    -- 2. Pixel metrics
    ------------------------------------------------------------
    px_w := abs(ST_PixelWidth(rast));
    px_h := abs(ST_PixelHeight(rast));
    px_area := px_w * px_h;

    r_minkowski := 0.5 * sqrt(px_w * px_w + px_h * px_h);

    ------------------------------------------------------------
    -- 3. Clip to envelope (performance)
    ------------------------------------------------------------
    rast_env := ST_Clip(rast, geom_env, NULL::double precision, TRUE);

    IF rast_env IS NULL THEN
        RETURN NULL;
    END IF;

    ------------------------------------------------------------
    -- 4. polygon clip (Touched=TRUE)
    ------------------------------------------------------------

	rast_out := ST_Clip(
    rast_env,
    geom_proj,
    NULL::double precision[],
	crop => TRUE,
    touched => TRUE
);

    IF rast_out IS NULL THEN
        RETURN NULL;
    END IF;

    ------------------------------------------------------------
    -- 5. Add weight band (Band 2 = 1 for interior pixels)
    ------------------------------------------------------------
    rast_out := ST_AddBand(
        rast_out,
        '32BF',
        1.0,
        0.0
    );

    ------------------------------------------------------------
    -- 6. Interior / Boundary separation
    ------------------------------------------------------------
    geom_inner := ST_Buffer(geom_proj, -r_minkowski);

    geom_bound := ST_Difference(
        geom_proj,
        COALESCE(
            geom_inner,
            ST_GeomFromText('POLYGON EMPTY', ST_SRID(geom_proj))
        )
    );

    IF geom_bound IS NULL OR ST_IsEmpty(geom_bound) THEN
        RETURN rast_out;
    END IF;

    ------------------------------------------------------------
    -- 7. Process boundary pixels
    ------------------------------------------------------------
    FOR p IN
        SELECT
            px.x,
            px.y,
            ST_Area(ST_Intersection(px.geom, geom_proj)) / px_area AS frac
        FROM ST_PixelAsPolygons(rast_out, 1) AS px
        WHERE
            px.val IS NOT NULL
            AND ST_Intersects(px.geom, geom_bound)
    LOOP

        IF p.frac > 0.0 AND p.frac < 1.0 THEN

            IF (
                (at_least AND p.frac >= threshold)
                OR
                (NOT at_least AND p.frac <= threshold)
            ) THEN
                -- keep pixel with fractional weight
                rast_out := ST_SetValue(rast_out, 2, p.x, p.y, p.frac);
            ELSE
                -- exclude pixel
                rast_out := ST_SetValue(rast_out, 1, p.x, p.y, NULL);
                rast_out := ST_SetValue(rast_out, 2, p.x, p.y, NULL);
            END IF;

        END IF;

    END LOOP;

    ------------------------------------------------------------
    -- 8. FIX: Mask band 2 by band 1
    -- Prevent ghost weights where band1 is NULL
    ------------------------------------------------------------
    band2_fixed :=
        ST_MapAlgebra(
            rast_out, 1,
            rast_out, 2,
            'CASE
                WHEN [rast1] IS NULL THEN NULL
                ELSE [rast2]
             END',
            '32BF'
        );

    rast_out :=
        ST_AddBand(
            ST_Band(rast_out, 1),
            band2_fixed
        );

    RETURN rast_out;

END;
$$;



