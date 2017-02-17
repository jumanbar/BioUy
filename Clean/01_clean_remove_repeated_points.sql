--DROP TABLE ppr_biomes;
CREATE TABLE ppr_biomes AS 
  SELECT id, geom FROM ppr_biomes_bak;
-- SELECT 48523

ALTER TABLE ppr_biomes ADD constraint pk_ppr_biomes_id PRIMARY KEY (id);

CREATE INDEX sidx_ppr_biomes_geom ON ppr_biomes USING GIST (geom);

UPDATE ppr_biomes SET geom = ST_RemoveRepeatedPoints(geom);
-- Query returned successfully: 48523 rows affected, 04:03 minutes execution time.
