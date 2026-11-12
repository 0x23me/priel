<?php

namespace OPNsense\Juist;

class SettingsController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Juist/settings');
        $this->view->settingsForm = $this->getForm('settings');
    }
}
