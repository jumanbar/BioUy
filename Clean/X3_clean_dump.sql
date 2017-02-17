
-- select id || ';' || ST_NPoints(geom) || ';' || ST_NRings(geom) || ';' || ST_NumGeometries(geom) from ppr_biomes where id <= 1000 order by ST_NPoints(geom) \g tabla_npoints.csv

-- select id, ST_NPoints(geom), ST_NRings(geom), ST_NumGeometries(geom), 406 from ppr_biomes where id = 10078;

/* Ordenar por Nro. de puntos:
select * from (
  select id, sc, geoformas, (st_dump(geom)).path[1], st_NPoints((st_dump(geom)).geom) as NP, 
  st_area((st_dump(geom)).geom) as Area, st_NumGeometries(geom) from ppr_biomes 
  where id in (47, 710, 752, 193, 1)
) sel order by NP;


create table ppr_biomes_dump as

select id, (geom_dump).path[1] as Path, (geom_dump).geom, ST_NPoints((geom_dump).geom) as NP, ST_Area((geom_dump).geom) as Area from (select id, ST_Dump(geom) as geom_dump from ppr_biomes where id in (47, 710, 193)) as gdump;
*/

create table ppr_biomes_dump as
  select id, (ST_Dump(geom)).* from ppr_biomes;
-- SELECT 6798778

/* Para hechar un vistazo:
  select id, path, path[1], st_npoints(geom) from ppr_biomes_dump limit 10;
*/
