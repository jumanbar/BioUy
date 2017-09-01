/* Consultas útiles */

/* Lista completa de especies en los padrones rurales
 *      4335, 4338, 4325, 4336, 4337, 4339, 4334
 */
SELECT
      --spp.id,
      --sp_area.spp_code, 
      spp.spp_group AS Grupo,
      spp.sci_gen   AS Genero,
      spp.sci_spe   AS Especie,
      spp.com_name  AS N_Comun, 
      spp.cons_state AS E_Conserv,
      sp_area.area   AS Area_has
  FROM
(
  SELECT
        distinct pd.spp_code, 
        sum(b.area) AS Area
    FROM bioma_ref br 
    JOIN
  (
    SELECT distinct bioma_id, sum(area_has) AS Area 
      FROM padron_bioma 
     WHERE padron_id IN (4335, 4338, 4325, 4336, 4337, 4339, 4334) 
     GROUP BY bioma_id
  ) AS b 
      ON br.id = b.bioma_id
    JOIN ppr_distribution pd ON pd.code = br.code
   GROUP BY pd.spp_code
   ORDER BY pd.spp_code
) AS sp_area
  JOIN species spp ON sp_area.spp_code = spp.code
 WHERE spp.id IN

(
  SELECT
        distinct u.species_id
    FROM utm_species u
   WHERE u.utm_id IN
  (
    SELECT sgm_id
      FROM padron_sgm 
     WHERE padron_id IN (4335, 4338, 4325, 4336, 4337, 4339, 4334)
  )
   GROUP BY u.species_id
   ORDER BY u.species_id
)
;



SELECT
      pd.spp_code, 
      pd.presence, 
      b.bioma_id, 
      br.code, 
      b.area
  FROM bioma_ref br 
  JOIN
(
SELECT distinct bioma_id, sum(area_has) AS Area 
  FROM padron_bioma 
 WHERE padron_id IN (4335, 4338, 4325, 4336, 4337, 4339, 4334) 
 GROUP BY bioma_id
) AS b 
    ON br.id = b.bioma_id
  JOIN ppr_distribution pd ON pd.code = br.code
;

