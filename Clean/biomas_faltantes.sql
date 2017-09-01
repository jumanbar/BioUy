
/* Para Miguel: estos biomas le faltan en la base de datos del SNAP: */

\COPY (select id, auto_id, sc, geoformas, carac_inun, cod_veget, cod_di_agr, cod_profun, cod_textur, cod_drenaj, cod_hidrom, cod_ph, cod_gr_roc, cod_otro, cod_sittot, cod_sitfin from ppr_biomes_bak where cod_sitfin IN ('Ba-PaPPPLTNN', 'BoPPLENNN-b', 'BoPPPLINN', 'D', 'O', 'P', 'suelo desnudo')) TO '/home/jmb/BioUy/biomas_faltantes.csv' WITH DELIMITER ';' CSV HEADER ;
