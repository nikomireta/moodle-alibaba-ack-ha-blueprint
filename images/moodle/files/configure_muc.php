<?php

declare(strict_types=1);

function stderr(string $message): void {
    fwrite(STDERR, $message . PHP_EOL);
}

function stdout(string $message): void {
    fwrite(STDOUT, $message . PHP_EOL);
}

function as_list($value): array {
    return is_array($value) ? array_values($value) : [];
}

function ensure_default_store(array &$configuration, string $storeName, array $storeConfig): void {
    if (!isset($configuration['stores'][$storeName]) || !is_array($configuration['stores'][$storeName])) {
        $configuration['stores'][$storeName] = $storeConfig;
    }
}

function upsert_mode_mapping(array &$configuration, int $mode, string $store): void {
    $mappings = as_list($configuration['modemappings'] ?? []);
    $filtered = [];

    foreach ($mappings as $mapping) {
        if (!is_array($mapping) || !array_key_exists('mode', $mapping) || (int)$mapping['mode'] !== $mode) {
            $filtered[] = $mapping;
        }
    }

    $filtered[] = [
        'store' => $store,
        'mode' => $mode,
        'sort' => 0,
    ];

    $configuration['modemappings'] = array_values($filtered);
}

function upsert_definition_mapping(array &$configuration, string $definition, array $stores): void {
    $mappings = as_list($configuration['definitionmappings'] ?? []);
    $filtered = [];

    foreach ($mappings as $mapping) {
        if (!is_array($mapping) || !array_key_exists('definition', $mapping) || $mapping['definition'] !== $definition) {
            $filtered[] = $mapping;
        }
    }

    $sort = 1;
    foreach ($stores as $store) {
        $filtered[] = [
            'store' => $store,
            'definition' => $definition,
            'sort' => $sort,
        ];
        $sort++;
    }

    $configuration['definitionmappings'] = array_values($filtered);
}

$redisHost = trim((string)(getenv('REDIS_CACHE_HOST') ?: ''));
$redisPort = trim((string)(getenv('REDIS_CACHE_PORT') ?: ''));
if ($redisHost === '' || $redisPort === '') {
    stderr('REDIS_CACHE_HOST or REDIS_CACHE_PORT is empty. Skip MUC auto-config.');
    exit(0);
}

$mucDir = '/var/www/moodledata/muc';
$mucConfigPath = $mucDir . '/config.php';

if (!is_dir($mucDir) && !mkdir($mucDir, 0775, true) && !is_dir($mucDir)) {
    stderr("Failed to create directory: {$mucDir}");
    exit(1);
}

$configuration = [];

if (!isset($configuration['stores']) || !is_array($configuration['stores'])) {
    $configuration['stores'] = [];
}
if (!isset($configuration['locks']) || !is_array($configuration['locks'])) {
    $configuration['locks'] = [];
}

$configuration['locks']['cachelock_file_default'] = [
    'name' => 'cachelock_file_default',
    'type' => 'cachelock_file',
    'dir' => 'filelocks',
    'default' => true,
];

ensure_default_store($configuration, 'default_application', [
    'name' => 'default_application',
    'plugin' => 'file',
    'configuration' => [],
    'features' => 30,
    'modes' => 3,
    'default' => true,
    'class' => 'cachestore_file',
    'lock' => 'cachelock_file_default',
]);

ensure_default_store($configuration, 'default_session', [
    'name' => 'default_session',
    'plugin' => 'session',
    'configuration' => [],
    'features' => 14,
    'modes' => 2,
    'default' => true,
    'class' => 'cachestore_session',
    'lock' => 'cachelock_file_default',
]);

ensure_default_store($configuration, 'default_request', [
    'name' => 'default_request',
    'plugin' => 'static',
    'configuration' => [],
    'features' => 31,
    'modes' => 4,
    'default' => true,
    'class' => 'cachestore_static',
    'lock' => 'cachelock_file_default',
]);

$configuration['stores']['redis-cache'] = [
    'name' => 'redis-cache',
    'plugin' => 'rediscluster',
    'configuration' => [
        'compression' => '0',
        'failover' => '0',
        'persist' => false,
        'prefix' => 'mdc_',
        'readtimeout' => 3.0,
        'serializer' => '2',
        'server' => "{$redisHost}:{$redisPort}",
        'serversecondary' => "{$redisHost}:{$redisPort}",
        'timeout' => 3.0,
    ],
    'features' => 26,
    'modes' => 3,
    'mappingsonly' => false,
    'class' => 'cachestore_rediscluster',
    'default' => false,
    'lock' => 'cachelock_file_default',
];

if (extension_loaded('apcu')) {
    $configuration['stores']['apcu'] = [
        'name' => 'apcu',
        'plugin' => 'apcu',
        'configuration' => [
            'prefix' => 'md_',
        ],
        'features' => 4,
        'modes' => 3,
        'mappingsonly' => false,
        'class' => 'cachestore_apcu',
        'default' => false,
        'lock' => 'cachelock_file_default',
    ];
}

$configuration['stores']['file-cache'] = [
    'name' => 'file-cache',
    'plugin' => 'file',
    'configuration' => [
        'path' => '/tmp/file-cache',
        'autocreate' => 1,
        'lockwait' => 60,
    ],
    'features' => 30,
    'modes' => 3,
    'mappingsonly' => false,
    'class' => 'cachestore_file',
    'default' => false,
    'lock' => 'cachelock_file_default',
];

upsert_mode_mapping($configuration, 1, 'redis-cache');
upsert_mode_mapping($configuration, 2, 'redis-cache');
upsert_mode_mapping($configuration, 4, 'default_request');

$coreDefinitions = [
    'core/plugin_functions',
    'core/string',
    'core/langmenu',
    'core/databasemeta',
];

foreach ($coreDefinitions as $definition) {
    $stores = extension_loaded('apcu') ? ['apcu', 'redis-cache'] : ['redis-cache'];
    upsert_definition_mapping($configuration, $definition, $stores);
}

upsert_definition_mapping($configuration, 'core/htmlpurifier', ['file-cache']);
upsert_definition_mapping($configuration, 'core/coursemodinfo', ['file-cache']);

$payload = "<?php defined('MOODLE_INTERNAL') || die();\n";
$payload .= '$configuration = ' . var_export($configuration, true) . ";\n";

$tempPath = $mucConfigPath . '.tmp.' . getmypid();
if (file_put_contents($tempPath, $payload) === false) {
    stderr("Failed to write temporary file: {$tempPath}");
    exit(1);
}

if (!@rename($tempPath, $mucConfigPath)) {
    @unlink($tempPath);
    stderr("Failed to move temporary file into place: {$mucConfigPath}");
    exit(1);
}

@chown($mucConfigPath, 'www-data');
@chgrp($mucConfigPath, 'www-data');

stdout('MUC cache configuration applied.');
exit(0);
