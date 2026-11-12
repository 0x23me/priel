<script>
    $(document).ready(function() {
        mapDataToFormUI({'frmSettings': "/api/juist/settings/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('juist');
        });

        $("#reconfigureAct").SimpleActionButton({
            onPreAction: function() {
                const dfObj = new $.Deferred();
                saveFormToEndpoint("/api/juist/settings/set", 'frmSettings', function() { dfObj.resolve(); }, true, function() { dfObj.reject(); });
                return dfObj;
            },
            onAction: function() {
                updateServiceControlUI('juist');
            }
        });
    });
</script>

<div class="content-box">
    {{ partial("layout_partials/base_form", ['fields': settingsForm, 'id': 'frmSettings']) }}
</div>
<section class="page-content-main">
    <div class="content-box">
        <div class="col-md-12">
            <br/>
            <button class="btn btn-primary" id="reconfigureAct"
                data-endpoint='/api/juist/service/reconfigure'
                data-label="{{ lang._('Apply') }}"
                data-error-title="{{ lang._('Error reconfiguring juist') }}"
                type="button"
            ></button>
            <br/><br/>
        </div>
    </div>
</section>
