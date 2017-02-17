/*
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 47;  -- 10 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 710; -- 100 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 752; -- 1030 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 193; -- 10167 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 1;   -- 182518 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 8;   -- 1964451 puntos
update ppr_biomes set geom = ST_Buffer(geom, 0) where id = 10;  -- 4120781 puntos

select count(*) from ppr_biomes;
*/

-- select id || ';' || ST_NPoints(geom) || ';' || ST_NRings(geom) || ';' || ST_NumGeometries(geom) from ppr_biomes where id <= 1000 order by ST_NPoints(geom) \g tabla_npoints.csv

-- select id, ST_NPoints(geom), ST_NRings(geom), ST_NumGeometries(geom), 406 from ppr_biomes where id = 10078;

/*
explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 37406 and path = 110376; -- 31

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 21 and path = 3405; -- 31

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 7186 and path = 98; -- 31

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 4805 and path = 1; -- 100

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 33682 and path = 2; -- 100

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 711 and path = 103; -- 100

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 39731 and path = 616; -- 316

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 10 and path = 326491; -- 316

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 6570 and path = 53; -- 316

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 36800 and path = 62; -- 1000

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 10257 and path = 295226; -- 1000

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 36614 and path = 36; -- 1000

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 37401 and path = 114402; -- 10027

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 36303 and path = 8791; -- 30412 - 514.3 ms

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 37406 and path = 78167; -- 95432 - 9153.9 ms 

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id = 2516 and path = 26817; -- 79021 - 1651.7 ms
*/


/* NPoints = 10 *//*
explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id =  37404 and path = 126678;

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id =  7634 and path = 29;

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id =  32651 and path = 13;

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id =  1272 and path = 131;

explain analyze update ppr_biomes_dump_filtered 
set geom = ST_Buffer(geom, 0) 
where id =  37404 and path = 76950;
*/

/* NPoints entre 10 mil y 80 mil... */

/*
10308
16400
18781
19796
16217
26163
49162
29965
16206
10148
*/

/*
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  6 and path = 16041;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  48334 and path = 4090;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  36331 and path = 15601;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  6 and path = 48892;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  36155 and path = 5442;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  161 and path = 2254;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  39964 and path = 4620;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  383 and path = 3972;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  36375 and path = 11908;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  37400 and path = 4551;
*/

/* NPoints entre 1000 y 10000 */

/*
1779
9115
1201
3326
1490
7446
3867
1884
1018
2087
*/

/*
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  10238 and path = 610;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  29259 and path = 117566;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  35209 and path = 150;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  45307 and path = 369;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  10257 and path = 22745;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  37402 and path = 28011;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  46406 and path = 2783;- 
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  7 and path = 12235;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  29256 and path = 212417;
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) where id =  6173 and path = 220;
*/

/*
explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) 
where gid in (88, 266, 334, 473, 476, 549, 576, 585, 612, 695);
*/

explain analyze update ppr_biomes_dump_filtered set geom = ST_Buffer(geom, 0) \g salida.txt
-- 3'42"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
/* Problema: esto genera geometrías "MultiPolygon" ...
select count(*), st_GeometryType(geom) 
  from ppr_biomes_dump_filtered 
 group by st_GeometryType(geom);
*/
/*
count  | st_geometrytype 
--------+-----------------
     96 | ST_MultiPolygon
 431200 | ST_Polygon
(2 rows)
*/

/* Para sacar una muestra de cómo son estos MultiPolygon:
select id, path, gid, (ST_dump(geom)).path[1] as path1, 
       ST_NPoints((ST_dump(geom)).geom), 
       ST_Area((ST_Dump(geom)).geom) 
  from ppr_biomes_dump_filtered 
 where ST_GeometryType(geom) = 'ST_MultiPolygon' \g multi.csv
*/

/* El siguiente paso (06_clean_dump2.sql) busca solucionar este problema */
