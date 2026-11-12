<?php

namespace OPNsense\Juist\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Juist\Settings';
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceTemplate = 'OPNsense/Juist';
    protected static $internalServiceName = 'juist';

    /* the juist interface group comes and goes with the service */
    protected function invokeInterfaceRegistration()
    {
        return true;
    }

    /* juistd needs its anchors called before it starts */
    protected function invokeFirewallReload()
    {
        return true;
    }
}
