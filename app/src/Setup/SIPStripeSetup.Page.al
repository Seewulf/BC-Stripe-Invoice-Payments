namespace PrabinBhusal.StripePayments;

page 58150 "SIP Stripe Setup"
{
    Caption = 'Stripe Setup';
    PageType = Card;
    SourceTable = "SIP Stripe Setup";
    ApplicationArea = All;
    UsageCategory = Administration;
    InsertAllowed = false;
    DeleteAllowed = false;
    AboutTitle = 'Get paid through Stripe';
    AboutText = 'Create a Stripe payment page for a posted sales invoice. A job queue checks Stripe every few minutes and posts the payment applied to the invoice. Use Stripe test keys in a sandbox.';

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field(Enabled; Rec.Enabled) { }
                field(Gateway; Rec.Gateway) { }
            }
            group(StripeKey)
            {
                Caption = 'Stripe Key';
                field(SecretKey; SecretKeyText)
                {
                    Caption = 'Secret Key';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Specifies the Stripe secret key or restricted key, for example sk_test_..., rk_test_... or rkcs_test_... from a Stripe CLI sandbox. It is kept in isolated storage and is never shown again.';

                    trigger OnValidate()
                    begin
                        // every Stripe test key has _test_ in it (sk_test_, rk_test_, rkcs_test_)
                        if (SecretKeyText <> '') and not SecretKeyText.Contains('_test_') then
                            if not Confirm(NotTestKeyQst, false) then
                                Error('');
                        // open links belong to the Stripe account and mode of the current key
                        if OpenLinksExist() then
                            if not Confirm(OpenLinksQst, false) then
                                Error('');
                        Rec.SetSecretKey(SecretKeyText);
                        SecretKeyText := '';
                        SecretKeySet := Rec.HasSecretKey();
                    end;
                }
                field(SecretKeySet; SecretKeySet)
                {
                    Caption = 'Secret Key Set';
                    Editable = false;
                    ToolTip = 'Specifies whether a Stripe secret key is stored.';
                }
            }
            group(Posting)
            {
                Caption = 'Posting';
                field("Clearing Bank Account No."; Rec."Clearing Bank Account No.") { }
                field("Payment Nos."; Rec."Payment Nos.") { }
                field("Journal Template Name"; Rec."Journal Template Name") { }
                field("Journal Batch Name"; Rec."Journal Batch Name") { }
            }
            group(PaymentPage)
            {
                Caption = 'Payment Page';
                field("Success URL"; Rec."Success URL") { }
                field("Cancel URL"; Rec."Cancel URL") { }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestConnection)
            {
                Caption = 'Test Connection';
                Image = TestDatabase;
                ToolTip = 'Call Stripe with the stored key to check that the key works and that the extension may make HTTP requests.';

                trigger OnAction()
                var
                    PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
                begin
                    PaymentLinkMgt.TestConnection();
                    Message(ConnectedMsg);
                end;
            }
            action(ScheduleSync)
            {
                Caption = 'Schedule Sync';
                Image = Timesheet;
                ToolTip = 'Create a job queue entry that checks open payment links every 5 minutes and posts the paid ones.';

                trigger OnAction()
                var
                    PaymentSync: Codeunit "SIP Payment Sync";
                begin
                    if PaymentSync.ScheduleJobQueue() then
                        Message(ScheduledMsg)
                    else
                        Message(AlreadyScheduledMsg);
                end;
            }
        }
        area(Navigation)
        {
            action(PaymentLinks)
            {
                Caption = 'Payment Links';
                Image = Links;
                RunObject = page "SIP Payment Links";
                ToolTip = 'View the payment links and their status.';
            }
            action(ActivityLog)
            {
                Caption = 'Activity Log';
                Image = Log;
                RunObject = page "SIP Activity Log";
                ToolTip = 'View every call to Stripe and every posting attempt.';
            }
        }
        area(Promoted)
        {
            actionref(TestConnection_Promoted; TestConnection) { }
            actionref(ScheduleSync_Promoted; ScheduleSync) { }
            actionref(PaymentLinks_Promoted; PaymentLinks) { }
            actionref(ActivityLog_Promoted; ActivityLog) { }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.InsertIfMissing();
        SecretKeySet := Rec.HasSecretKey();
    end;

    local procedure OpenLinksExist(): Boolean
    var
        PaymentLink: Record "SIP Payment Link";
    begin
        PaymentLink.SetRange(Status, PaymentLink.Status::Open);
        exit(not PaymentLink.IsEmpty());
    end;

    var
        [NonDebuggable]
        SecretKeyText: Text;
        SecretKeySet: Boolean;
        OpenLinksQst: Label 'Open payment links were created with the current key. A key for another Stripe account or mode cannot check them, and they stay open until you expire them. Do you want to change the key anyway?';
        NotTestKeyQst: Label 'This is not a Stripe test key (test keys have _test_ in them). Live keys take real money. Do you want to store it anyway?';
        ConnectedMsg: Label 'Stripe accepted the key.';
        ScheduledMsg: Label 'A job queue entry now checks the payment links every 5 minutes.';
        AlreadyScheduledMsg: Label 'A job queue entry for the payment sync already exists. Open Job Queue Entries to change it.';
}
