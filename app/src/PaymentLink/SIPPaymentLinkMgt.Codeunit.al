namespace PrabinBhusal.StripePayments;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Sales.Customer;
using Microsoft.Sales.History;
using Microsoft.Sales.Receivables;
using System.EMail;

// Creates, opens, expires and re-posts payment links.
codeunit 58150 "SIP Payment Link Mgt"
{
    var
        NotSetUpErr: Label 'Stripe payments are not set up. Open the Stripe Setup page first.';
        NoSecretKeyErr: Label 'Enter the Stripe secret key on the Stripe Setup page first.';
        NotInvoiceErr: Label 'Customer ledger entry %1 is not an invoice. Payment links can only be created for invoices.', Comment = '%1 = entry no.';
        NotOpenErr: Label 'Invoice %1 has nothing left to pay.', Comment = '%1 = invoice no.';
        LinkExistsErr: Label 'Invoice %1 already has a payment link that is open, paid or waiting to be posted. Expire it or finish it first.', Comment = '%1 = invoice no.';
        GatewayErr: Label 'Stripe returned an error: %1', Comment = '%1 = error message';
        NothingToPostErr: Label 'The payment link for invoice %1 has no paid amount to post. Check Last Error and handle the payment in the Stripe Dashboard.', Comment = '%1 = invoice no.';
        OpenPaymentPageQst: Label 'The payment link for invoice %1 is ready. Do you want to open the payment page now?', Comment = '%1 = invoice no.';
        CreateSessionTok: Label 'Create Session', Locked = true;
        ExpireSessionTok: Label 'Expire Session', Locked = true;
        TestConnectionTok: Label 'Test Connection', Locked = true;

    procedure CreateForSalesInvoice(SalesInvoiceHeader: Record "Sales Invoice Header"): Record "SIP Payment Link"
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        SalesInvoiceHeader.TestField("Cust. Ledger Entry No.");
        CustLedgerEntry."Entry No." := SalesInvoiceHeader."Cust. Ledger Entry No.";
        exit(CreateForCustLedgerEntry(CustLedgerEntry));
    end;

    // The link is only saved after Stripe accepted the session. A gateway error commits its log row and then raises the error.
    procedure CreateForCustLedgerEntry(CustLedgerEntry: Record "Cust. Ledger Entry") PaymentLink: Record "SIP Payment Link"
    var
        Customer: Record Customer;
        LockedEntry: Record "Cust. Ledger Entry";
        StripeSetup: Record "SIP Stripe Setup";
        TempGatewayResult: Record "SIP Gateway Result";
        StripeAmount: Codeunit "SIP Stripe Amount";
        ActivityLogger: Codeunit "SIP Activity Logger";
        PaymentGateway: Interface "SIP IPayment Gateway";
        StartedAt: DateTime;
        Success: Boolean;
    begin
        GetReadySetup(StripeSetup);
        CustLedgerEntry.SetLoadFields("Customer No.", "Document Type", "Document No.", "Currency Code", Open);
        CustLedgerEntry.SetAutoCalcFields("Remaining Amount");
        CustLedgerEntry.Get(CustLedgerEntry."Entry No.");
        if CustLedgerEntry."Document Type" <> CustLedgerEntry."Document Type"::Invoice then
            Error(NotInvoiceErr, CustLedgerEntry."Entry No.");
        if (not CustLedgerEntry.Open) or (CustLedgerEntry."Remaining Amount" <= 0) then
            Error(NotOpenErr, CustLedgerEntry."Document No.");
        if ActiveLinkExists(CustLedgerEntry."Document No.") then
            Error(LinkExistsErr, CustLedgerEntry."Document No.");

        PaymentLink.Init();
        PaymentLink."Customer No." := CustLedgerEntry."Customer No.";
        PaymentLink."Invoice No." := CustLedgerEntry."Document No.";
        PaymentLink."Cust. Ledger Entry No." := CustLedgerEntry."Entry No.";
        PaymentLink.Amount := CustLedgerEntry."Remaining Amount";
        PaymentLink."Currency Code" := CustLedgerEntry."Currency Code";
        PaymentLink."Stripe Currency" := StripeAmount.StripeCurrency(PaymentLink."Currency Code");
        PaymentLink."Amount (Minor Units)" := StripeAmount.ToMinorUnits(PaymentLink.Amount, PaymentLink."Stripe Currency");

        Customer.SetLoadFields("E-Mail");
        if Customer.Get(PaymentLink."Customer No.") then;
        PaymentGateway := StripeSetup.Gateway;
        StartedAt := CurrentDateTime();
        Success := PaymentGateway.CreateCheckoutSession(PaymentLink, FirstEmailAddress(Customer."E-Mail"), TempGatewayResult);
        ActivityLogger.LogGatewayCall(CreateSessionTok, PaymentLink."Invoice No.", TempGatewayResult."Session Id", TempGatewayResult, Success, StartedAt);
        if not Success then
            ErrorAfterLog(TempGatewayResult);

        // another user may have created a link during the Stripe call; the invoice entry lock lets only one win
        LockedEntry.ReadIsolation := IsolationLevel::UpdLock;
        LockedEntry.SetLoadFields("Entry No.");
        LockedEntry.Get(CustLedgerEntry."Entry No.");
        if ActiveLinkExists(PaymentLink."Invoice No.") then begin
            // keep the log row; the new session's URL was never shown, so it expires unused
            Commit();
            Error(LinkExistsErr, PaymentLink."Invoice No.");
        end;

        PaymentLink."Session Id" := TempGatewayResult."Session Id";
        PaymentLink.URL := TempGatewayResult.URL;
        PaymentLink."Expires At" := TempGatewayResult."Expires At";
        PaymentLink.Status := PaymentLink.Status::Open;
        PaymentLink.Insert(true);
    end;

    procedure OfferToOpen(PaymentLink: Record "SIP Payment Link")
    begin
        if not GuiAllowed() then
            exit;
        if Confirm(OpenPaymentPageQst, true, PaymentLink."Invoice No.") then
            OpenPaymentPage(PaymentLink);
    end;

    procedure OpenPaymentPage(PaymentLink: Record "SIP Payment Link")
    begin
        PaymentLink.TestField(Status, PaymentLink.Status::Open);
        PaymentLink.TestField(URL);
        Hyperlink(PaymentLink.URL);
    end;

    // Closes the Stripe page so the customer can no longer pay with it.
    procedure ExpireLink(var PaymentLink: Record "SIP Payment Link")
    var
        LockedLink: Record "SIP Payment Link";
        StripeSetup: Record "SIP Stripe Setup";
        TempGatewayResult: Record "SIP Gateway Result";
        ActivityLogger: Codeunit "SIP Activity Logger";
        PaymentGateway: Interface "SIP IPayment Gateway";
        StartedAt: DateTime;
        Success: Boolean;
    begin
        PaymentLink.TestField(Status, PaymentLink.Status::Open);
        GetSetup(StripeSetup);
        PaymentGateway := StripeSetup.Gateway;
        StartedAt := CurrentDateTime();
        Success := PaymentGateway.ExpireCheckoutSession(PaymentLink."Session Id", TempGatewayResult);
        ActivityLogger.LogGatewayCall(ExpireSessionTok, PaymentLink."Invoice No.", PaymentLink."Session Id", TempGatewayResult, Success, StartedAt);
        // 404: this key does not know the session (key or account changed), so it can never be checked; cancel it in BC
        if not Success and (TempGatewayResult."HTTP Status Code" <> 404) then
            ErrorAfterLog(TempGatewayResult);

        // lock a local copy, so the caller's record (often the page Rec) keeps its default isolation
        LockedLink.ReadIsolation := IsolationLevel::UpdLock;
        LockedLink.Get(PaymentLink."Entry No.");
        LockedLink.TestField(Status, LockedLink.Status::Open);
        LockedLink.Status := LockedLink.Status::Cancelled;
        LockedLink."Last Error" := TempGatewayResult."Error Message";
        LockedLink."Synced At" := CurrentDateTime();
        LockedLink.Modify(true);
        PaymentLink.Get(LockedLink."Entry No.");
    end;

    // Posts a Failed link again from the stored Stripe data. Returns true when it is posted now.
    procedure RetryPosting(var PaymentLink: Record "SIP Payment Link"): Boolean
    var
        LockedLink: Record "SIP Payment Link";
        PaymentSync: Codeunit "SIP Payment Sync";
    begin
        // lock a local copy, so the caller's record keeps its default isolation
        LockedLink.ReadIsolation := IsolationLevel::UpdLock;
        LockedLink.Get(PaymentLink."Entry No.");
        LockedLink.TestField(Status, LockedLink.Status::Failed);
        // no paid amount (e.g. paid in another currency): nothing to post, keep the reason
        if LockedLink."Amount Paid" = 0 then
            Error(NothingToPostErr, LockedLink."Invoice No.");
        LockedLink.Status := LockedLink.Status::Paid;
        LockedLink."Last Error" := '';
        LockedLink.Modify(true);
        PaymentSync.PostPaidLink(LockedLink);
        PaymentLink.Get(LockedLink."Entry No.");
        exit(PaymentLink.Status = PaymentLink.Status::Posted);
    end;

    procedure TestConnection()
    var
        StripeSetup: Record "SIP Stripe Setup";
        TempGatewayResult: Record "SIP Gateway Result";
        ActivityLogger: Codeunit "SIP Activity Logger";
        PaymentGateway: Interface "SIP IPayment Gateway";
        StartedAt: DateTime;
        Success: Boolean;
    begin
        GetSetup(StripeSetup);
        PaymentGateway := StripeSetup.Gateway;
        StartedAt := CurrentDateTime();
        Success := PaymentGateway.TestConnection(TempGatewayResult);
        ActivityLogger.LogGatewayCall(TestConnectionTok, '', '', TempGatewayResult, Success, StartedAt);
        if not Success then
            ErrorAfterLog(TempGatewayResult);
    end;

    local procedure GetSetup(var StripeSetup: Record "SIP Stripe Setup")
    begin
        if not StripeSetup.Get() then
            Error(NotSetUpErr);
        if (StripeSetup.Gateway = StripeSetup.Gateway::Stripe) and not StripeSetup.HasSecretKey() then
            Error(NoSecretKeyErr);
    end;

    // Everything a new link needs, so a paid link can always be posted.
    local procedure GetReadySetup(var StripeSetup: Record "SIP Stripe Setup")
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
    begin
        GetSetup(StripeSetup);
        StripeSetup.TestField(Enabled);
        StripeSetup.TestField("Clearing Bank Account No.");
        StripeSetup.TestField("Payment Nos.");
        StripeSetup.TestField("Success URL");
        GeneralLedgerSetup.SetLoadFields("Journal Templ. Name Mandatory");
        GeneralLedgerSetup.Get();
        if GeneralLedgerSetup."Journal Templ. Name Mandatory" then begin
            StripeSetup.TestField("Journal Template Name");
            StripeSetup.TestField("Journal Batch Name");
        end;
    end;

    // Failed is blocked too: the customer has paid, only the posting is missing.
    local procedure ActiveLinkExists(InvoiceNo: Code[20]): Boolean
    var
        PaymentLink: Record "SIP Payment Link";
    begin
        PaymentLink.SetRange("Invoice No.", InvoiceNo);
        PaymentLink.SetFilter(Status, '%1|%2|%3', PaymentLink.Status::Open, PaymentLink.Status::Paid, PaymentLink.Status::Failed);
        exit(not PaymentLink.IsEmpty());
    end;

    // Stripe takes one address; BC allows several separated by semicolons. An invalid one is left out.
    local procedure FirstEmailAddress(EmailAddresses: Text) EmailAddress: Text
    var
        MailManagement: Codeunit "Mail Management";
    begin
        if EmailAddresses = '' then
            exit('');
        EmailAddress := EmailAddresses.Split(';').Get(1).Trim();
        if not MailManagement.CheckValidEmailAddress(EmailAddress) then
            EmailAddress := '';
    end;

    // Commit keeps the log row; the error then only rolls back what comes after it.
    local procedure ErrorAfterLog(TempGatewayResult: Record "SIP Gateway Result" temporary)
    begin
        Commit();
        Error(GatewayErr, TempGatewayResult."Error Message");
    end;
}
