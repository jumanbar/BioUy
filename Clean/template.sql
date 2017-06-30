
TRUNCATE output_what;
COPY output_what FROM '/home/jmb/BioUy/XXX' DELIMITER ',' CSV;

INSERT INTO padron_biome (padron_id, biome_id, n)
SELECT padron_id, biome_id, count(*) AS n
  FROM output_what
 GROUP BY padron_id, biome_id;

INSERT INTO padron_sgm (padron_id, sgm_id, n)
SELECT padron_id, utm_id AS sgm_id, count(*) AS n
  FROM output_what
 GROUP BY padron_id, utm_id;
