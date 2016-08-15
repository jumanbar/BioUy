
setwd("BioUy/R/")
library(RODBC)
library(rgdal)
installed.packages("rjson")

library(rjson)

con <- odbcConnect("biouy")

# odbcQuery(con, "create extension postgis")
# odbcQuery(con, "create extension postgis_topology")
# odbcQuery(con, "create extension plr")

sqlQuery(con, "select postgis_full_version();")

sqlQuery(con, "select id, sc, geoformas, cod_sittot from public.ppr_sites limit 15")
sqlQuery(con, "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
sqlQuery(con, "SELECT column_name, ordinal_position, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ambientes_ppr'")
