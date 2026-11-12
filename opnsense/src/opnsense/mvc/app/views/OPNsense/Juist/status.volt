<script>
    $(document).ready(function() {
        const admin = {{ admin ? 'true' : 'false' }};
        let inviteTimer = null;

        function show(what, target) {
            ajaxGet('/api/juist/status/show/' + what, {}, function(data) {
                $(target).text(data.output || '');
            });
        }

        function showDevices() {
            ajaxGet('/api/juist/status/show/devices', {}, function(data) {
                const $body = $('#devices > tbody').empty();
                if (!data.rows || data.rows.length === 0) {
                    $body.append($('<tr>').append($('<td colspan="5">').text(data.output || '')));
                    return;
                }
                $.each(data.rows, function(_, row) {
                    const $tr = $('<tr>');
                    $tr.append($('<td>').text(row.name + (row.self ? ' {{ lang._('(this firewall)') }}' : '')));
                    $tr.append($('<td>').text(row.ipv4));
                    $tr.append($('<td>').text(row.reached));
                    $tr.append($('<td>').text(row.roles));
                    const $cmd = $('<td>');
                    if (admin && !row.self) {
                        $cmd.append($('<button class="btn btn-xs btn-default" type="button"><span class="fa fa-fw fa-trash-o"></span></button>')
                            .data('device', row.name).addClass('act-remove'));
                    }
                    $body.append($tr.append($cmd));
                });
            });
        }

        function showInvite(data) {
            $('#inviteLink').text(data.link || '');
            $('#inviteOutput').text(data.output || '');
            $('#inviteCancel').toggle(!!data.running);
            if (!data.running && inviteTimer !== null) {
                clearInterval(inviteTimer);
                inviteTimer = null;
                showDevices();
            }
        }

        function pollInvite() {
            ajaxGet('/api/juist/status/show/invite-status', {}, showInvite);
        }

        $('#inviteStart').click(function() {
            ajaxCall('/api/juist/status/invite', {action: 'start', expires: $('#inviteExpires').val()}, function(data) {
                showInvite(data);
                if (inviteTimer === null) {
                    inviteTimer = setInterval(pollInvite, 2000);
                }
            });
        });

        $('#inviteCancel').click(function() {
            ajaxCall('/api/juist/status/invite', {action: 'cancel', expires: '15m'}, showInvite);
        });

        $('#devices').on('click', '.act-remove', function() {
            const device = $(this).data('device');
            BootstrapDialog.confirm({
                title: "{{ lang._('Remove device') }}",
                message: $('<span>').text(device).html(),
                type: BootstrapDialog.TYPE_DANGER,
                callback: function(yes) {
                    if (yes) {
                        ajaxCall('/api/juist/status/remove', {device: device}, function(data) {
                            if (data.rc !== 0) {
                                BootstrapDialog.alert($('<span>').text(data.output || '').html());
                            }
                            showDevices();
                        });
                    }
                }
            });
        });

        show('status', '#statusText');
        show('health', '#healthText');
        show('log', '#logText');
        show('subnets', '#subnetsText');
        showDevices();
        if (admin) {
            pollInvite();
        }
        updateServiceControlUI('juist');
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#devicesTab">{{ lang._('Devices') }}</a></li>
    <li><a data-toggle="tab" href="#subnetsTab">{{ lang._('Subnets') }}</a></li>
    <li><a data-toggle="tab" href="#logTab">{{ lang._('Log') }}</a></li>
</ul>
<div class="tab-content content-box">
    <div id="general" class="tab-pane fade in active">
        <pre id="statusText"></pre>
        <pre id="healthText"></pre>
    </div>
    <div id="devicesTab" class="tab-pane fade in">
        <table id="devices" class="table table-striped table-condensed">
            <thead>
                <tr>
                    <th>{{ lang._('Name') }}</th>
                    <th>{{ lang._('Address') }}</th>
                    <th>{{ lang._('Reached') }}</th>
                    <th>{{ lang._('Roles') }}</th>
                    <th></th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
        {% if admin %}
        <div class="col-md-12">
            <hr/>
            <select id="inviteExpires" class="selectpicker" data-width="auto">
                <option value="15m">15 {{ lang._('minutes') }}</option>
                <option value="1h">1 {{ lang._('hour') }}</option>
                <option value="1d">1 {{ lang._('day') }}</option>
            </select>
            <button class="btn btn-primary" id="inviteStart" type="button">{{ lang._('Invite a device') }}</button>
            <button class="btn btn-default" id="inviteCancel" type="button" style="display: none;">{{ lang._('Cancel invite') }}</button>
            <br/><br/>
            <pre id="inviteLink" style="white-space: pre-wrap; word-break: break-all;"></pre>
            <pre id="inviteOutput"></pre>
        </div>
        {% endif %}
    </div>
    <div id="subnetsTab" class="tab-pane fade in">
        <pre id="subnetsText"></pre>
    </div>
    <div id="logTab" class="tab-pane fade in">
        <pre id="logText"></pre>
    </div>
</div>
