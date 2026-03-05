<?php  // Moodle configuration file

unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = '$DATABASE_HOST';
$CFG->dbname    = '$DATABASE_NAME';
$CFG->dbuser    = '$DATABASE_USER';
$CFG->dbpass    = '$DATABASE_PASSWORD';
$CFG->prefix    = '$DATABASE_PREFIX';
$CFG->dboptions = array (
  'dbpersist' => true,
  'dbport' => $DATABASE_PORT,
  'dbsocket' => false,
  'dbhandlesoptions' => true,
  'fetchbuffersize' => 0,
  'readonly' => [
    'instance' => '$DATABASE_HOST_READ',
    'connecttimeout' => 2,
    'latency' => 0.5,
  ]
);

$wwwrootfromenv = '$WWW_ROOT';
if ($wwwrootfromenv !== '') {
  $CFG->wwwroot = $wwwrootfromenv;
} else if (!empty($_SERVER['HTTP_HOST'])) {
  $scheme = 'http';
  if (
    (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower((string)$_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https')
    || (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off')
    || (isset($_SERVER['SERVER_PORT']) && (string)$_SERVER['SERVER_PORT'] === '443')
  ) {
    $scheme = 'https';
  }
  $CFG->wwwroot = $scheme . '://' . $_SERVER['HTTP_HOST'];
} else {
  // Deterministic CLI fallback when no HTTP request context exists.
  $CFG->wwwroot = 'http://127.0.0.1';
}
$CFG->dataroot  = '$DATA_ROOT';
$CFG->admin     = '$ADMIN';

$CFG->localcachedir               = '/var/www/localdata/cache';
$CFG->alternative_component_cache = '/var/www/localdata/cache/core_component.php';
$CFG->localrequestdir             = '/var/www/localdata/request';

if ('$OBJECTFS_S3_ENABLED' === '1') {
  $CFG->alternative_file_system_class = '\tool_objectfs\s3_file_system';
}

$CFG->directorypermissions = 02777;
$CFG->sslproxy = $SSL_PROXY;
#$CFG->tool_generator_users_password = 'moodle';

$CFG->session_handler_class = '\cachestore_rediscluster\session';
$CFG->session_rediscluster = [
    'server' => '$REDIS_SESSION_HOST:$REDIS_SESSION_PORT',
    'prefix' => "mdlsession_{$CFG->dbname}:",
    'acquire_lock_timeout' => 60,
    'lock_expire' => 600,
    'max_waiters' => 10,
];

$CFG->xsendfile = 'X-Accel-Redirect';
$CFG->xsendfilealiases = array(
  '/dataroot/' => $CFG->dataroot,
  '/localcachedir/' => $CFG->localcachedir,
);

require_once(__DIR__ . '/lib/setup.php');

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!
