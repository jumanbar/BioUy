<?php
require_once "config.php";
require_once "utils.php";

/**
  * Inserts species data into db
  *
  * @param Connection $conn connection
  */
function insertSpecies($conn)
{
    $species = json_decode(file_get_contents(SPECIES_FILE));

    foreach ($species as $item) {
        $sci_parts = explode(" ", $item->scientificName);
        $native = ($item->native == 'Si') ? 'true' : 'false';

        $sql = "INSERT into species (spp_group, spp_order, family, sci_gen, sci_spe, com_name, code, cons_state, native) VALUES (" .
        "'" . $item->group . "'," .
        "'" . $item->order . "'," .
        "'" . $item->family . "'," .
        "'" . $sci_parts[0] . "'," .
        "'" . $sci_parts[1] . "'," .
        "'" . $item->commonNames . "'," .
        "'" . $item->code . "'," .
        "'" . $item->conservationState . "'," .
        "'" . $native . "'" .
        ');';

        $rs = pg_query($conn, $sql);
        if (!$rs) {
            echo "An SQL error occured.\n";
            exit;
        }
    }
}

/**
  * Inserts species by utm card data into db
  *
  * @param Connection $conn connection
  */
function insertSpeciesByUTM($conn)
{
    $dist = json_decode(file_get_contents(DISTRIBUTION_SGM_FILE));

    foreach ($dist as $item) {
        $sql =  "INSERT into utm_species (utm_id, species_id) values (" .
        "(select gid from utm_grid where carta = '" . $item->code . "')," .
        "(select id from species where code = '" . $item->speciesCode . "' limit 1));";

        $rs = pg_query($conn, $sql);
        if (!$rs) {
            echo "An SQL error occured.\n";
            exit;
        }
    }
}

/**
  * Inserts species by ppr site into db
  *
  * @param Connection $conn connection
  */
function insertSpeciesByPPR($conn)
{
    $dist = json_decode(file_get_contents(DISTRIBUTION_PPR_FILE));

    foreach ($dist as $item) {
        $sql =  "INSERT into ppr_type_species (ppr_type_id, species_id) values (" .
        "(select id from ppr_site_type where code = '" . $item->code . "' limit 1)," .
        "(select id from species where code = '" . $item->speciesCode . "' limit 1));";

        $rs = pg_query($conn, $sql);
        if (!$rs) {
            echo "An SQL error occured.\n";
            exit;
        }
    }
}

/**
  * Gets db connection
  */
function getDBConnection()
{
    $conn = pg_connect(
        "dbname='" . DB_NAME . "'" .
        "user='" . DB_USER . "'" .
        "password='" . DB_PASS . "'" .
        "host='" . DB_HOST . "'" .
        "port='" . DB_PORT . "'"
    );
    if (!$conn) {
        echo "Not connected : " . pg_error();
        exit;
    }

    return $conn;
}

/**
  * Inserts all data into db
  *
  * @param Connection $conn connection
  */
function insertAll($conn)
{
    insertSpecies($conn);
    insertSpeciesByUTM($conn);
    insertSpeciesByPPR($conn);
}

$conn = getDBConnection();

insertAll($conn);
