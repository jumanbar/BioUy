# Argumentos
# $1: lista de padrones separados por coma

# Salida, stdout:
# Archivo csv (tabla), con columnas separadas por punto y coma

padrones=$1

camino_git="/home/jmb/BioUy/git_repo"

sed "s/XXXX/$padrones/"\
  $camino_git/SQL/Consultas_utiles/lista_spp_padrones.sql\
  | psql -f - -A -F ';' | head -n -1

