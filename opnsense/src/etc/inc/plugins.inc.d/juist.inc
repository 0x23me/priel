<?php

/*
 * juistd on OPNsense: its service, its devices, and the pf anchors it
 * refuses to work without.
 */

function juist_enabled()
{
    return !empty((string)(new \OPNsense\Juist\Settings())->enabled);
}

function juist_services()
{
    if (!juist_enabled()) {
        return [];
    }

    return [[
        'description' => gettext('juist mesh VPN'),
        'pidfile' => '/var/run/juistd.pid',
        'configd' => [
            'restart' => ['juist restart'],
            'start' => ['juist start'],
            'stop' => ['juist stop'],
        ],
        'name' => 'juist',
    ]];
}

/* juistd creates and destroys juist0 itself */
function juist_devices()
{
    return [[
        'pattern' => '^juist[0-9]$',
        'configurable' => false,
        'spoofmac' => false,
        'volatile' => true,
    ]];
}

/* juistd puts its devices in the interface group "juist" */
function juist_interfaces()
{
    if (!juist_enabled()) {
        return [];
    }

    return ['juist' => [
        'descr' => gettext('juist (Group)'),
        'if' => 'juist',
        'virtual' => true,
        'enable' => true,
        'type' => 'group',
        'networks' => [],
    ]];
}

function juist_firewall(\OPNsense\Firewall\Plugin $fw)
{
    global $config;

    if (!juist_enabled()) {
        return;
    }

    /*
     * juistd loads its guard, forwarding and NAT rules into anchors under
     * juist/ and only where the main ruleset calls all three, the filter
     * one before the first quick pass rule. Translation comes after the
     * firewall's own, so that an outbound "do not NAT" rule can keep it
     * from rewriting what the firewall routes back by itself.
     */
    $fw->registerAnchor('juist/*', 'nat');
    $fw->registerAnchor('juist/*', 'rdr');
    $fw->registerAnchor('juist/*', 'fw', 0, 'head');

    $mdl = new \OPNsense\Juist\Settings();
    $baserule = [
        'direction' => 'in',
        'to' => '(self)',
        'log' => !isset($config['syslog']['nologdefaultpass']),
        '#ref' => 'ui/juist/settings',
    ];

    /* log sync between members runs inside the tunnel */
    foreach (['inet', 'inet6'] as $ipprotocol) {
        $fw->registerFilterRule(
            1,
            ['interface' => 'juist', 'protocol' => 'tcp', 'to_port' => 41644, 'ipprotocol' => $ipprotocol,
             'descr' => 'juist: log sync between members'],
            $baserule
        );
    }

    if (empty((string)$mdl->openPorts)) {
        return;
    }

    $ports = [['udp', (string)$mdl->port, 'juist: WireGuard and path discovery']];
    if (!empty((string)$mdl->relay)) {
        $ports[] = ['tcp', (string)$mdl->relayPort, 'juist: relay'];
        $ports[] = ['udp', (string)$mdl->relayPort, 'juist: relay'];
    }
    foreach (array_filter(explode(',', (string)$mdl->interfaces)) as $intf) {
        foreach ($ports as [$protocol, $port, $descr]) {
            foreach (['inet', 'inet6'] as $ipprotocol) {
                $fw->registerFilterRule(
                    1,
                    ['interface' => $intf, 'protocol' => $protocol, 'to_port' => $port,
                     'ipprotocol' => $ipprotocol, 'descr' => $descr],
                    $baserule
                );
            }
        }
    }
}
