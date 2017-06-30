/* Este código agarra el id más chico para todos los padrones clonados */
create table padrones_rep as
select * from (
  select min(id) as id, padron, depto, seccat, lamina, cuadricula, count(*) as n 
    from padrones_rurales 
   group by padron, depto, seccat, lamina, cuadricula 
   order by n desc
) as g where n > 1;
/* biouy=# select sum(n) from padrones_rep; -- 18979 */

/* Este código es para agarrar todos los id de los padrones que aparecen repetidos
   en los campos <> geometría. Sé que lo hizo bien porque la cantidad de filas da 
   18979 (ver arriba). */
create table padrones_rep_id as (
select id from (
	select id from (
		select 
		  id, padron, depto, seccat, lamina, cuadricula, 
		  ROW_NUMBER() OVER(PARTITION BY padron, depto, seccat, lamina, cuadricula 
		                        ORDER BY id) as rn
		  from padrones_rurales
	) as pr where rn > 1
	UNION
	select id from padrones_rep
) as u order by id );

/* Este código es para agrupar por geometría (visto en StackOverflow, lo de usar
   ST_AsBinary), para ver cuántos realmente están duplicados en todo sentido: */
select padron, depto, seccat, lamina, cuadricula, n 
  from (
    select padron, depto, seccat, lamina, cuadricula, ST_AsBinary(geom), count(*) as n 
      from padrones_rurales
     where id in (select id from padrones_rep_id)
     group by padron, depto, seccat, lamina, cuadricula, ST_AsBinary(geom) 
     order by n desc, cuadricula, lamina, seccat, depto, padron
  ) as g;
 --where g.padron <> 0 limit 200;

/* El único padrón que parece tener realmente repetida hasta la geometría sería este: */
select id from padrones_rurales
 where padron = 18920
   and depto = 'CANELONES'
   and seccat = 0
   and lamina = 'SIN DATO'
   and cuadricula = 'SIN DATO';
/*  65896
   109700 */

create table tmp_padrones as (select * from padrones_rurales where id in ( 65896, 109700));
