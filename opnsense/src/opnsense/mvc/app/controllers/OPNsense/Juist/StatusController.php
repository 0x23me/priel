<?php

namespace OPNsense\Juist;

class StatusController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Juist/status');
        $this->view->admin = !empty((string)(new Settings())->admin);
    }
}
