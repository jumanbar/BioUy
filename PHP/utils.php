<?php

/**
 * Converts array to assoc array with provided keys
 *
 * @param array $keys     keys
 * @param array $elements elements
 *
 * @return array
 */
function tableElementsToAssocArray($keys, $elements)
{
    $result = [];

    foreach ($elements as $element) {
        $eKeys = $keys;
        if (count($eKeys) != count($element)) {
            foreach ($eKeys as $key => $value) {

                if (!isset($element[$key])) {
                    $element[$key] = $value;
                    $eKeys[$key]    = $key;
                }
            }
        }

        $result[] = array_combine($eKeys, $element);
    }

    return $result;
}

/**
 * Sanitizes text obtained from html
 *
 * @param string $text text
 *
 * @return string
 */
function sanitizeHtmlText($text)
{
    return html_entity_decode(strip_tags(trim(preg_replace('/\s+/', ' ', $text))));
}

/**
 * Saves data to file
 *
 * @param string  $fileName file name
 * @param string  $data     data
 * @param boolean $override overrides file data when true
 *
 * @return void
 */
function saveToFile($fileName, $data, $override = false)
{
    if ($override) {
        file_put_contents($fileName, $data.PHP_EOL);
    } else {
        file_put_contents($fileName, $data.PHP_EOL, FILE_APPEND);
    }
}
