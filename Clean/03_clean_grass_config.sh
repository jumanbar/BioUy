User='jmb'

# Crear nueva location con el código EPSG (WGS84 + UTM21S: 32721):
grass70 -c epsg:32721 /home/$User/grassdata/BioUy
grass70 -c /home/$User/grassdata/BioUy/$User

# Conectar con la base de datos PostgreSQL (dentro de grass70):
# Estos pasos no me acuerdo bien cómo los hice...
# db.connect
# db.login
