/* La idea de estos comandos es limpiar un poco la mugre de la base, incluyendo
 * cambiar nombres de algunas tablas por alternativas más adecuadas. Los cambios
 * de nombres serían:
 *   utm_grid     --> cartas_sgm (acá hice una copia nomás, porque no puedo
 *   borrar utm_grid sin complicar lo hecho en el trabajo anterior con VS y con
 *   Pancho.
 *   utm_grid2    --> sgm_ref 
 *   ppr_sitfin   --> bioma_ref
 *   padron_biome --> padron_bioma 
 */

ALTER INDEX sidx_cartas_sgm_geom RENAME TO sidx_cartas_sgm_jmb_geom;

-- Importé las cartas del archivo Cartas_SGM.shp, usando QGIS.
-- Este shape es igual al utm_grid.shp, pero se le agregó una columna con el
-- nombre de la carta (ej: Vizcaíno).

/* Para comprobar que los id de las cartas están bien: */

SELECT c.id, u.gid, c.carta, u.carta, c.nombre
  FROM cartas_sgm c JOIN utm_grid u ON c.id = u.gid;

SELECT c.id, u.gid, c.carta, u.carta, c.nombre, u.nombre
  FROM cartas_sgm c JOIN utm_grid2 u ON c.id = u.gid;

DROP TABLE cartas_sgm_jmb ;

ALTER TABLE utm_grid2 RENAME TO sgm_ref;

ALTER TABLE sgm_ref RENAME CONSTRAINT utm_grid2_pkey TO sgmref_pkey;

ALTER TABLE ppr_sitfin RENAME TO bioma_ref;

ALTER TABLE padron_biome RENAME TO padron_bioma;
ALTER TABLE padron_bioma RENAME COLUMN biome_id TO bioma_id;
ALTER TABLE padron_bioma RENAME CONSTRAINT padbiome_pkey TO padbio_pkey;
ALTER SEQUENCE padron_biome_id_seq RENAME TO padron_bioma_id_seq;

