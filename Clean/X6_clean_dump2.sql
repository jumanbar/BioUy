/* Este paso hace 2 cosas:

   1. Rompe los ST_MultiPolygon en pedazos simples, dejando objetos de clase
      ST_Polygon solamente.
   2. Elimina polígonos de área menor a 1 hectárea.

 */

create table ppr_biomes_dump2 as
  select id, path as path0, (ST_Dump(geom)).*, gid -- gid = nextval?
    from ppr_biomes_dump_filtered
   where ST_GeometryType(geom) = 'ST_MultiPolygon';

delete from ppr_biomes_dump_filtered 
      where gid in (select gid from ppr_biomes_dump2)
         or ST_Area(geom) < 1e4;

delete from ppr_biomes_dump2
      where ST_Area(geom) < 1e4;

insert into ppr_biomes_dump_filtered
  select id, path0 as path, geom, gid
    from ppr_biomes_dump2
   where path[1] = 1;

insert into ppr_biomes_dump_filtered
  select id, path0 as path, geom, 
         nextval('ppr_biomes_dump_filtered_gid_seq') as gid
    from ppr_biomes_dump2
   where path[1] <> 1;

/*
  RESULTADOS:
*/

/* No hay más MultiPolygons:
select count(*), st_GeometryType(geom) 
  from ppr_biomes_dump_filtered 
 group by st_GeometryType(geom);

 count  | st_geometrytype 
--------+-----------------
 431289 | ST_Polygon
(1 row)

  Tampoco hay áreas menores a 1 há:
select min(ST_Area(geom)) from ppr_biomes_dump_filtered;
       min        
------------------
 10000.0012444159
(1 row)
*/



