create table ppr_biomes_dump as
  select row_number() over() as gid, d.id, d.path[1] as path, d.geom 
    from (select id, (ST_Dump(geom)).* from ppr_biomes) d
-- SELECT 6937193

/* Para hechar un vistazo:
  select gid, id, path, st_npoints(geom) from ppr_biomes_dump limit 10;
*/
