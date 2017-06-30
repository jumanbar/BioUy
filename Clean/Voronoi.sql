/*
select row_number() over() as gid, path[1] as anillo, path[2] as punto, geom from (
select (st_dumppoints(geom)).* from tmp_fills) as d
*/
WITH 
    -- Sample set of points to work with
    Sample AS (SELECT ST_GeomFromText('MULTIPOINT (12 5, 5 7, 2 5, 19 6, 19 13, 15 18, 10 20, 4 18, 0 13, 0 6, 4 1, 10 0, 15 1, 19 6)') geom),
    -- Build edges and circumscribe points to generate a centroid
    Edges AS (
    SELECT id,
        UNNEST(ARRAY['e1','e2','e3']) EdgeName,
        UNNEST(ARRAY[
            ST_MakeLine(p1,p2) ,
            ST_MakeLine(p2,p3) ,
            ST_MakeLine(p3,p1)]) Edge,
        ST_Centroid(ST_ConvexHull(ST_Union(-- Done this way due to issues I had with LineToCurve
            ST_CurveToLine(
              REPLACE(ST_AsText(ST_LineMerge(
                        ST_Union(ST_MakeLine(p1,p2), 
                                 ST_MakeLine(p2,p3)))),
                      'LINE','CIRCULAR'),15),
            ST_CurveToLine(
              REPLACE(ST_AsText(ST_LineMerge(
                        ST_Union(ST_MakeLine(p2,p3),
                                 ST_MakeLine(p3,p1)))),
                      'LINE','CIRCULAR'),15)
        ))) ct      
    FROM    (
        -- Decompose to points
        SELECT id,
            ST_PointN(g,1) p1,
            ST_PointN(g,2) p2,
            ST_PointN(g,3) p3
        FROM    (
            SELECT (gd).Path id, ST_ExteriorRing((gd).Geom) g -- ID andmake triangle a linestring
            FROM (SELECT (ST_Dump(ST_DelaunayTriangles(geom))) gd FROM Sample) a -- Get Delaunay Triangles
            )b
        ) c
    )
SELECT ST_Polygonize(ST_Node(ST_LineMerge(ST_Union(v, ST_ExteriorRing(ST_ConvexHull(v))))))
FROM (
    SELECT  -- Create voronoi edges and reduce to a multilinestring
        ST_LineMerge(ST_Union(ST_MakeLine(
        x.ct,
        CASE 
        WHEN y.id IS NULL THEN
            CASE WHEN ST_Within(
                x.ct,
                (SELECT ST_ConvexHull(geom) FROM sample)) THEN -- Don't draw lines back towards the original set
                -- Project line out twice the distance from convex hull
                ST_MakePoint(ST_X(x.ct) + ((ST_X(ST_Centroid(x.edge)) - ST_X(x.ct)) * 2),ST_Y(x.ct) + ((ST_Y(ST_Centroid(x.edge)) - ST_Y(x.ct)) * 2))
            END
        ELSE 
            y.ct
        END
        ))) v
    FROM    Edges x 
        LEFT OUTER JOIN -- Self Join based on edges
        Edges y ON x.id <> y.id AND ST_Equals(x.edge,y.edge)
    ) z;



