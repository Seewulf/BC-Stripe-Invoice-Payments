namespace PrabinBhusal.StripePayments;

using Microsoft.Sales.Receivables;

// Reads one Checkout Session from the gateway and moves the link to Paid, Expired or Cancelled.
// A gateway error only sets Last Error: the link stays Open and the next run tries again.
codeunit 58154 "SIP Check Payment Link"
{
    Access = Internal;
    TableNo = "SIP Payment Link";

    trigger OnRun()
    var
        PaymentLink: Record "SIP Payment Link";
        StripeSetup: Record "SIP Stripe Setup";
        TempGatewayResult: Record "SIP Gateway Result";
        TempExpireResult: Record "SIP Gateway Result";
        ActivityLogger: Codeunit "SIP Activity Logger";
        PaymentGateway: Interface "SIP IPayment Gateway";
        StartedAt: DateTime;
        ExpireStartedAt: DateTime;
        Success: Boolean;
        InvoiceSettled: Boolean;
        ExpireSuccess: Boolean;
    begin
        StripeSetup.Get();
        PaymentGateway := StripeSetup.Gateway;
        StartedAt := CurrentDateTime();
        Success := PaymentGateway.GetCheckoutSession(Rec."Session Id", TempGatewayResult);
        // invoice settled in BC while the page is still payable: close it before the customer pays twice
        if Success and (TempGatewayResult."Session Status" = 'open') then
            InvoiceSettled := IsInvoiceSettled(Rec);
        if InvoiceSettled then begin
            ExpireStartedAt := CurrentDateTime();
            ExpireSuccess := PaymentGateway.ExpireCheckoutSession(Rec."Session Id", TempExpireResult);
        end;
        // HTTP calls first, writes after
        ActivityLogger.LogGatewayCall(GetSessionTok, Rec."Invoice No.", Rec."Session Id", TempGatewayResult, Success, StartedAt);
        if InvoiceSettled then
            ActivityLogger.LogGatewayCall(ExpireSessionTok, Rec."Invoice No.", Rec."Session Id", TempExpireResult, ExpireSuccess, ExpireStartedAt);

        // lock after the HTTP calls; another session may have handled the link meanwhile
        PaymentLink.ReadIsolation := IsolationLevel::UpdLock;
        PaymentLink.Get(Rec."Entry No.");
        if PaymentLink.Status <> PaymentLink.Status::Open then
            exit;
        PaymentLink."Synced At" := CurrentDateTime();
        PaymentLink."Last Error" := '';
        if not Success then
            PaymentLink."Last Error" := TempGatewayResult."Error Message"
        else
            if not InvoiceSettled then
                ApplySessionState(PaymentLink, TempGatewayResult)
            else
                if ExpireSuccess then begin
                    PaymentLink.Status := PaymentLink.Status::Cancelled;
                    PaymentLink."Last Error" := InvoiceSettledTxt;
                end else
                    // still payable: the next run tries to close it again
                    PaymentLink."Last Error" := TempExpireResult."Error Message";
        PaymentLink.Modify(true);
        Rec := PaymentLink;
    end;

    var
        GetSessionTok: Label 'Get Session', Locked = true;
        ExpireSessionTok: Label 'Expire Session', Locked = true;
        InvoiceSettledTxt: Label 'The invoice was settled in Business Central, so the Stripe payment page was closed.';
        CurrencyMismatchTxt: Label 'Stripe reports the payment in %1, but the link asked for %2. The payment is not posted. Check it in the Stripe Dashboard and post it manually.', Comment = '%1 = currency reported by Stripe, %2 = currency of the link';

    local procedure ApplySessionState(var PaymentLink: Record "SIP Payment Link"; TempGatewayResult: Record "SIP Gateway Result" temporary)
    var
        StripeAmount: Codeunit "SIP Stripe Amount";
    begin
        if (TempGatewayResult."Session Status" = 'complete') and (TempGatewayResult."Payment Status" = 'paid') then begin
            PaymentLink."Payment Intent Id" := TempGatewayResult."Payment Intent Id";
            // the amount only means something in the currency that was asked; Failed blocks a second charge
            if LowerCase(TempGatewayResult.Currency) <> PaymentLink."Stripe Currency" then begin
                PaymentLink.Status := PaymentLink.Status::Failed;
                PaymentLink."Last Error" := CopyStr(StrSubstNo(CurrencyMismatchTxt, UpperCase(TempGatewayResult.Currency), UpperCase(PaymentLink."Stripe Currency")), 1, MaxStrLen(PaymentLink."Last Error"));
                exit;
            end;
            PaymentLink.Status := PaymentLink.Status::Paid;
            PaymentLink."Amount Paid" := StripeAmount.FromMinorUnits(TempGatewayResult."Amount Total (Minor Units)", TempGatewayResult.Currency);
            exit;
        end;
        if TempGatewayResult."Session Status" = 'expired' then
            PaymentLink.Status := PaymentLink.Status::Expired;
    end;

    // Closed, or less left to pay than the link asks: a Stripe payment now would overpay the invoice.
    local procedure IsInvoiceSettled(PaymentLink: Record "SIP Payment Link"): Boolean
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
    begin
        InvoiceEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        InvoiceEntry.SetLoadFields(Open);
        InvoiceEntry.SetAutoCalcFields("Remaining Amount");
        if not InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.") then
            exit(false);
        exit((not InvoiceEntry.Open) or (InvoiceEntry."Remaining Amount" < PaymentLink.Amount));
    end;
}
