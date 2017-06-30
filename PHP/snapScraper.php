<?php
require "vendor/autoload.php";
require_once "config.php";
require_once "utils.php";

use Goutte\Client;

/**
 * Gets list of elements from html table
 *
 * @param Crawler $table table
 *
 * @return array
 */
function getElementsFromTable($table)
{
    $result = [];
    $rows   = $table->filter('tr');

    $elements = $rows->each(
        function ($node) {
            $values = $node->children()->each(
                function ($node) {
                    return sanitizeHtmlText($node->text());
                }
            );
            return $values;
        }
    );

    $columnNames = array_shift($elements);

    return $elements;
}

/**
 * Gets the list of species extracted from html
 *
 * @param Crawler $html html
 *
 * @return array
 */
function getSpecies($html)
{
    $columns = ['group', 'order', 'family', 'scientificName', 'commonNames', 'code', 'conservationState', 'native'];
    $table   = $html->filter('table')->last();

    return tableElementsToAssocArray($columns, getElementsFromTable($table));
}

/**
 * Gets the list of species distribution extracted from html
 *
 * @param Crawler $html        html
 * @param string  $speciesCode species code
 *
 * @return array
 */
function getSpeciesDistribution($html, $speciesCode)
{
    $columns = ['utType', 'code', 'name', 'presence', 'quote', 'speciesCode' => $speciesCode];
    $table   = $html->filter('table')->last();
    $data    = getElementsFromTable($table);

    return tableElementsToAssocArray($columns, getElementsFromTable($table));
}

/**
 * Proccess species
 *
 * @param Client $client client
 *
 * @return void
 */
function processSpecies($client)
{
    echo "RETRIEVING SPECIES.";
    $html  = $client->request('GET', SNAP_URL . 'busqueda_taxonomica/?grupo=-1&palabra_clave=');
    $species = getSpecies($html);
    echo "PROCESSING SPECIES.";
    if (!empty($species)) {
        saveToFile(SPECIES_FILE, json_encode($species, JSON_UNESCAPED_UNICODE), true);

        echo "SPECIES LIST PROCESSED!";
    }
}

/**
 * Proccess species details
 *
 * @param Client $client    client
 * @param int    $fromIndex index to start
 *
 * @return void
 */
function processSpeciesDetail($client, $fromIndex = false)
{
    $species = json_decode(file_get_contents(SPECIES_FILE));

    if ($fromIndex === false) saveToFile(DISTRIBUTION_FILE, '[', true);

    foreach ($species as $index => $item) {
        if ($fromIndex === false || $index >= $fromIndex) {
            $html = $client->request('GET', SNAP_URL . 'especie/' . $item->code);
            $dist = getSpeciesDistribution($html, $item->code);

            if (!empty($dist)) {
                $data = json_encode($dist, JSON_UNESCAPED_UNICODE);
                $data = substr($data, 1, -1) . ',';
                saveToFile(DISTRIBUTION_FILE, $data);
            }
            echo "INDEX: ". $index . " - " . $item->code . " DETAIL PROCESSED!";
        }
    }

    saveToFile(DISTRIBUTION_FILE, ']');
}

/**
 * Generates file with PPR distribution
 *
 * @return void
 */
function generateDistributionFiles()
{
    $dist = json_decode(file_get_contents(DISTRIBUTION_FILE));
    $sgm       = [];
    $ppr       = [];
    $snap      = [];
    $protected = [];
    $other     = [];

    foreach ($dist as $record) {
        switch ($record->utType) {
        case 'Grilla SGM':
            $sgm[] = $record;
            break;
        case 'Ecosistema PPR':
            $ppr[] = $record;
            break;
        case 'Ecosistema SNAP':
            $snap[] = $record;
            break;
        case  'Área Protegida':
            $protected[] = $record;
            break;
        default:
            $other[] = $record;
            break;
        }
    }

    saveToFile(DISTRIBUTION_SGM_FILE, json_encode($sgm, JSON_UNESCAPED_UNICODE), true);
    saveToFile(DISTRIBUTION_PPR_FILE, json_encode($ppr, JSON_UNESCAPED_UNICODE), true);
    saveToFile(DISTRIBUTION_SNP_FILE, json_encode($snap, JSON_UNESCAPED_UNICODE), true);
    saveToFile(DISTRIBUTION_PRO_FILE, json_encode($protected, JSON_UNESCAPED_UNICODE), true);
    saveToFile(DISTRIBUTION_OTH_FILE, json_encode($other, JSON_UNESCAPED_UNICODE), true);
}

/**
  * Clears all files
  *
  * @return void
  */
function clearAllFiles()
{
    saveToFile(SPECIES_FILE, "", true);
    saveToFile(DISTRIBUTION_FILE, "", true);
}

/**
 * Proccess all data
 *
 * @param Client $client client
 *
 * @return void
 */
function parseAll($client) {
    clearAllFiles();
    processSpecies($client);
    processSpeciesDetail($client);
    generateDistributionFiles();
}

$client = new Client();

// parseAll($client);
