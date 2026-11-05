<?php
// Keep this compatible with PHP 5.6. Tests must not require external services.
$name = $argv[1];
if (!extension_loaded($name)) {
    throw new Exception($name . ' did not load');
}

function check_smoke($condition) {
    if (!$condition) {
        throw new Exception('Extension smoke test failed');
    }
}

$value = array('cache' => array(1, 2, 'test'));
switch ($name) {
    case 'igbinary':
        check_smoke(igbinary_unserialize(igbinary_serialize($value)) === $value);
        break;
    case 'msgpack':
        check_smoke(msgpack_unpack(msgpack_pack($value)) === $value);
        break;
    case 'yaml':
        check_smoke(yaml_parse(yaml_emit($value)) === $value);
        break;
    case 'apcu':
        check_smoke(apcu_store('extension-cache', $value));
        check_smoke(apcu_fetch('extension-cache') === $value);
        apcu_delete('extension-cache');
        break;
    case 'redis':
        $client = new Redis();
        // Older releases require a server connection even for serializer options.
        check_smoke($client->isConnected() === false);
        break;
    case 'memcached':
        $client = new Memcached();
        check_smoke($client->getServerList() === array());
        break;
    case 'memcache':
        check_smoke(new Memcache() instanceof Memcache);
        break;
    case 'imagick':
        $image = new Imagick();
        $image->newImage(2, 2, 'white');
        $image->setImageFormat('png');
        check_smoke(strlen($image->getImageBlob()) > 0);
        $image->clear();
        break;
    case 'ds':
        $map = new Ds\Map();
        $map->put('cache', 3);
        check_smoke($map->get('cache') === 3);
        break;
    case 'ast':
        $versions = ast\get_supported_versions();
        check_smoke(ast\parse_code('<?php echo 1;', max($versions)) instanceof ast\Node);
        break;
    case 'mongodb':
        $binary = new MongoDB\BSON\Binary('cache', 0);
        check_smoke($binary->getData() === 'cache');
        break;
    case 'decimal':
        $number = method_exists('Decimal\\Decimal', 'valueOf')
            ? Decimal\Decimal::valueOf('1.5') : new Decimal\Decimal('1.5');
        check_smoke($number->add('2.5')->equals('4'));
        break;
    case 'http':
        $params = new http\Params('cache=ok');
        check_smoke(strpos($params->toString(), 'cache') !== false);
        break;
    case 'uuid':
        check_smoke(strlen(uuid_create()) === 36);
        break;
    case 'zstd':
        check_smoke(zstd_uncompress(zstd_compress('extension-cache')) === 'extension-cache');
        break;
    case 'lz4':
        check_smoke(lz4_uncompress(lz4_compress('extension-cache')) === 'extension-cache');
        break;
    case 'mailparse':
        check_smoke(count(mailparse_rfc822_parse_addresses('cache@example.com')) === 1);
        break;
    case 'xmlrpc':
        check_smoke(xmlrpc_decode(xmlrpc_encode($value)) === $value);
        break;
    case 'xdebug':
        check_smoke(is_array(xdebug_get_function_stack()));
        break;
    default:
        // Reflection exercises the registered module without contacting a
        // database, message broker or another external service.
        $module = new ReflectionExtension($name);
        check_smoke(strcasecmp($module->getName(), $name) === 0);
        $module->getFunctions();
        $module->getClasses();
        $module->getConstants();
        break;
}

echo 'CACHE_SMOKE_OK:', phpversion($name);
