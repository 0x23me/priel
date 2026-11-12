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

    /* status, devices, health, log, subnets, admins and invite-status */
    public function showAction($what = 'status')
    {
        return $this->backend('query', [$what]);
    }

    public function inviteAction()
    {
        if ($this->denied()) {
            return ['rc' => 1, 'output' => gettext('This firewall holds no admin key.')];
        }
        return $this->backend('invite', [
            $this->request->getPost('action', 'string', 'start'),
            $this->request->getPost('expires', 'string', '15m'),
        ]);
    }

    public function removeAction()
    {
        if ($this->denied()) {
            return ['rc' => 1, 'output' => gettext('This firewall holds no admin key.')];
        }
        return $this->backend('remove', [$this->request->getPost('device', 'string', '')]);
    }
}
