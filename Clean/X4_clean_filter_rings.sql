-- drop table ppr_biomes_dump_filtered ;
create table ppr_biomes_dump_filtered as
select id, path[1], filter_rings(geom, 1e4) as geom 
  from ppr_biomes_dump
where st_area(geom) > 1e4;
-- SELECT 431296

/* Para hechar un vistazo:
  select id, path, st_npoints(geom), st_area(geom) 
    from ppr_biomes_dump_filtered
   order by st_area(geom) -- Para ver el área mínima de los poly
    limit 10;
*/

alter table ppr_biomes_dump_filtered add column gid serial primary key;
CREATE INDEX sidx_ppr_biomes_dump_filtered_geom ON ppr_biomes_dump_filtered USING GIST (geom);

/*
biouy=# select count(*), st_GeometryType(geom) from ppr_biomes_dump_filtered group by st_GeometryType(geom);
 count  | st_geometrytype 
--------+-----------------
 431296 | ST_Polygon
(1 row)
*/


