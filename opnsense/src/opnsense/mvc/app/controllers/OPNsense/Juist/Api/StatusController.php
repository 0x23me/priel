<?php

namespace OPNsense\Juist\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Juist\Settings;

class StatusController extends ApiControllerBase
{
    private function backend($action, $params)
    {
        $response = json_decode((string)(new Backend())->configdpRun('juist ' . $action, $params), true);
        return $response ?? ['rc' => 1, 'output' => gettext('No answer from the backend.')];
    }

    private function denied()
    {
        return !$this->request->isPost() || empty((string)(new Settings())->admin);
    }

    /* status, devices, health, log, subnets, admins and invite-status: reads, nothing else */
    public function showAction($what = 'status')
    {
        if (!in_array($what, ['status', 'devices', 'health', 'log', 'subnets', 'admins', 'invite-status'], true)) {
            return ['rc' => 2, 'output' => gettext('Unknown request.')];
        }
        return $this->backend('query', [$what]);
    }

    public function inviteAction()
    {
        if ($this->denied()) {
            return ['rc' => 1, 'output' => gettext('This firewall holds no admin key.')];
        }
        $action = $this->request->getPost('action', 'string', 'start');
        $expires = $this->request->getPost('expires', 'string', '15m');
        if (!in_array($action, ['start', 'cancel'], true) || !in_array($expires, ['15m', '1h', '1d'], true)) {
            return ['rc' => 2, 'output' => gettext('Unknown request.')];
        }
        return $this->backend('invite', [$action, $expires]);
    }

    public function removeAction()
    {
        if ($this->denied()) {
            return ['rc' => 1, 'output' => gettext('This firewall holds no admin key.')];
        }
        $device = $this->request->getPost('device', 'string', '');
        if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $device)) {
            return ['rc' => 2, 'output' => gettext('Not a device name.')];
        }
        return $this->backend('remove', [$device]);
    }
}
