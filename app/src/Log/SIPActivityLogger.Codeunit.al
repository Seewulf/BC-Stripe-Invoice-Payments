namespace PrabinBhusal.StripePayments;

// Writes the activity log. Failures also go to telemetry, without personal data.
codeunit 58156 "SIP Activity Logger"
{
    Access = Internal;

    var
        SessionStateTxt: Label 'Session %1, payment %2', Comment = '%1 = Stripe session status, %2 = Stripe payment status';
        FailureTelemetryTxt: Label 'Stripe payment operation failed.', Locked = true;

    procedure Log(Operation: Text; InvoiceNo: Code[20]; SessionId: Text; HttpStatusCode: Integer; DurationMs: Integer; Success: Boolean; MessageText: Text; ErrorCallStack: Text)
    var
        ActivityLog: Record "SIP Activity Log";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        ActivityLog.Init();
        ActivityLog.Operation := CopyStr(Operation, 1, MaxStrLen(ActivityLog.Operation));
        ActivityLog."Invoice No." := InvoiceNo;
        ActivityLog."Session Id" := CopyStr(SessionId, 1, MaxStrLen(ActivityLog."Session Id"));
        ActivityLog."HTTP Status Code" := HttpStatusCode;
        ActivityLog."Duration (ms)" := DurationMs;
        ActivityLog.Success := Success;
        ActivityLog.Message := CopyStr(MessageText, 1, MaxStrLen(ActivityLog.Message));
        ActivityLog."Error Call Stack" := CopyStr(ErrorCallStack, 1, MaxStrLen(ActivityLog."Error Call Stack"));
        ActivityLog.Insert(true);
        if Success then
            exit;

        CustomDimensions.Add('Operation', Operation);
        CustomDimensions.Add('HttpStatusCode', Format(HttpStatusCode));
        CustomDimensions.Add('DurationMs', Format(DurationMs));
        Session.LogMessage('SIP0001', FailureTelemetryTxt, Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::All, CustomDimensions);
    end;

    procedure LogGatewayCall(Operation: Text; InvoiceNo: Code[20]; SessionId: Text; TempGatewayResult: Record "SIP Gateway Result" temporary; Success: Boolean; StartedAt: DateTime)
    var
        MessageText: Text;
    begin
        if not Success then
            MessageText := TempGatewayResult."Error Message"
        else
            if TempGatewayResult."Session Status" <> '' then
                MessageText := StrSubstNo(SessionStateTxt, TempGatewayResult."Session Status", TempGatewayResult."Payment Status");
        Log(Operation, InvoiceNo, SessionId, TempGatewayResult."HTTP Status Code", CurrentDateTime() - StartedAt, Success, MessageText, '');
    end;
}
