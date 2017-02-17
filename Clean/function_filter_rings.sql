/*
Author: Simon Greener
Web Page: http://www.spatialdbadvisor.com/postgis_tips_tricks/92/filtering-rings-in-polygon-postgis/

Notes: This version of the function does not handle MultiPolygon geometries. I
choosed it because it performs better. I'm not sure if his latest version (which
does handle MultiPoligon) is really worse performing even when dealing with
single Polygons.

Im including that version at the end, inside comment markers.

NOTE: I changed > for >= in the second WHERE statement

 */
CREATE OR REPLACE FUNCTION filter_rings(geometry, DOUBLE PRECISION)
  RETURNS geometry AS
$BODY$
SELECT ST_MakePolygon((/* Get outer ring of polygon */
        SELECT ST_ExteriorRing(geom) AS outer_ring
          FROM ST_DumpRings($1)
          WHERE path[1] = 0 /* ie the outer ring */
        ),  ARRAY(/* Get all inner rings > a particular area */
        SELECT ST_ExteriorRing(geom) AS inner_rings
          FROM ST_DumpRings($1)
          WHERE path[1] > 0 /* ie not the outer ring */
            AND ST_Area(geom) >= $2
        ) ) AS final_geom
$BODY$
  LANGUAGE 'sql' IMMUTABLE;

/*
    CREATE OR REPLACE FUNCTION filter_rings(geometry, DOUBLE PRECISION)
      RETURNS geometry AS
    $BODY$
    SELECT ST_BuildArea(ST_Collect(b.final_geom)) AS filtered_geom
      FROM (SELECT ST_MakePolygon(( -- Get outer ring of polygon
        SELECT ST_ExteriorRing(a.the_geom) AS outer_ring -- ie the outer ring 
        ),  ARRAY(-- Get all inner rings > a particular area 
         SELECT ST_ExteriorRing(b.geom) AS inner_ring
           FROM (SELECT (ST_DumpRings(a.the_geom)).*) b
          WHERE b.path[1] > 0 -- ie not the outer ring 
            AND ST_Area(b.geom) > $2
        ) ) AS final_geom
             FROM (SELECT ST_GeometryN(ST_Multi($1), --ST_Multi converts any Single Polygons to MultiPolygons 
                                       generate_series(1,ST_NumGeometries(ST_Multi($1)))
                                       ) AS the_geom
                   ) a
           ) b
    $BODY$
      LANGUAGE 'sql' IMMUTABLE;
 
 */
