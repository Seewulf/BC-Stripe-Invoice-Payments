namespace PrabinBhusal.StripePayments;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.GeneralLedger.Posting;
using Microsoft.Foundation.AuditCodes;
using Microsoft.Foundation.NoSeries;
using Microsoft.Sales.Receivables;

// Posts the customer payment for a Paid link, applied to the invoice when that is still possible.
codeunit 58155 "SIP Post Payment"
{
    Access = Internal;
    TableNo = "SIP Payment Link";

    trigger OnRun()
    var
        PaymentLink: Record "SIP Payment Link";
    begin
        // lock the link first, so two sessions can never post the same payment
        PaymentLink.ReadIsolation := IsolationLevel::UpdLock;
        PaymentLink.Get(Rec."Entry No.");
        if PaymentLink.Status <> PaymentLink.Status::Posted then begin
            PaymentLink.TestField(Status, PaymentLink.Status::Paid);
            PaymentLink.TestField("Payment Intent Id");
            if not MarkPostedIfAlreadyPosted(PaymentLink) then
                PostPayment(PaymentLink);
        end;
        Rec := PaymentLink;
    end;

    var
        DescriptionTxt: Label 'Stripe payment %1', Comment = '%1 = invoice no.';

    local procedure PostPayment(var PaymentLink: Record "SIP Payment Link")
    var
        GenJournalLine: Record "Gen. Journal Line";
        SourceCodeSetup: Record "Source Code Setup";
        StripeSetup: Record "SIP Stripe Setup";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        NoSeries: Codeunit "No. Series";
    begin
        StripeSetup.Get();
        StripeSetup.TestField("Clearing Bank Account No.");
        StripeSetup.TestField("Payment Nos.");
        PaymentLink.TestField("Amount Paid");
        SourceCodeSetup.SetLoadFields("Cash Receipt Journal");
        SourceCodeSetup.Get();

        GenJournalLine.Init();
        // needed when General Ledger Setup has Journal Templ. Name Mandatory
        GenJournalLine."Journal Template Name" := StripeSetup."Journal Template Name";
        GenJournalLine."Journal Batch Name" := StripeSetup."Journal Batch Name";
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine."Document Type" := GenJournalLine."Document Type"::Payment;
        GenJournalLine."Document No." := NoSeries.GetNextNo(StripeSetup."Payment Nos.", WorkDate());
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Customer);
        GenJournalLine.Validate("Account No.", PaymentLink."Customer No.");
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"Bank Account");
        GenJournalLine.Validate("Bal. Account No.", StripeSetup."Clearing Bank Account No.");
        GenJournalLine.Validate("Currency Code", PaymentLink."Currency Code");
        GenJournalLine.Validate(Amount, -PaymentLink."Amount Paid");
        GenJournalLine."External Document No." := CopyStr(PaymentLink."Payment Intent Id", 1, MaxStrLen(GenJournalLine."External Document No."));
        GenJournalLine.Description := CopyStr(StrSubstNo(DescriptionTxt, PaymentLink."Invoice No."), 1, MaxStrLen(GenJournalLine.Description));
        GenJournalLine."Source Code" := SourceCodeSetup."Cash Receipt Journal";
        GenJournalLine."System-Created Entry" := true;

        PaymentLink."Needs Review" := PaymentLink."Amount Paid" <> PaymentLink.Amount;
        if CanApplyToInvoice(PaymentLink) then begin
            GenJournalLine."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type"::Invoice;
            GenJournalLine."Applies-to Doc. No." := PaymentLink."Invoice No.";
        end else
            PaymentLink."Needs Review" := true;

        GenJnlPostLine.RunWithCheck(GenJournalLine);
        // a payment discount or tolerance can still leave money open on either side
        if not PaymentLink."Needs Review" then
            PaymentLink."Needs Review" := IsLeftOpen(PaymentLink, GenJournalLine."Document No.");

        PaymentLink.Status := PaymentLink.Status::Posted;
        PaymentLink."Payment Document No." := GenJournalLine."Document No.";
        PaymentLink."Last Error" := '';
        PaymentLink.Modify(true);
    end;

    // Applied only when the invoice is still open for at least the amount paid; otherwise it posts unapplied for review.
    local procedure CanApplyToInvoice(PaymentLink: Record "SIP Payment Link"): Boolean
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
    begin
        InvoiceEntry.SetLoadFields(Open);
        InvoiceEntry.SetAutoCalcFields("Remaining Amount");
        if not InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.") then
            exit(false);
        exit(InvoiceEntry.Open and (InvoiceEntry."Remaining Amount" >= PaymentLink."Amount Paid"));
    end;

    // Reads the entries this transaction just posted: true when the invoice or the payment is still open.
    local procedure IsLeftOpen(PaymentLink: Record "SIP Payment Link"; PaymentDocumentNo: Code[20]): Boolean
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
        PaymentEntry: Record "Cust. Ledger Entry";
    begin
        InvoiceEntry.SetLoadFields(Open);
        if InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.") then
            if InvoiceEntry.Open then
                exit(true);
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        PaymentEntry.SetRange("Document No.", PaymentDocumentNo);
        PaymentEntry.SetRange(Open, true);
        exit(not PaymentEntry.IsEmpty());
    end;

    // Guards against double posting, for example when an earlier run posted but stopped before updating the link.
    local procedure MarkPostedIfAlreadyPosted(var PaymentLink: Record "SIP Payment Link"): Boolean
    var
        PaymentEntry: Record "Cust. Ledger Entry";
    begin
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        PaymentEntry.SetRange("External Document No.", CopyStr(PaymentLink."Payment Intent Id", 1, MaxStrLen(PaymentEntry."External Document No.")));
        PaymentEntry.SetLoadFields("Document No.");
        if not PaymentEntry.FindFirst() then
            exit(false);
        PaymentLink.Status := PaymentLink.Status::Posted;
        PaymentLink."Payment Document No." := PaymentEntry."Document No.";
        PaymentLink."Last Error" := '';
        PaymentLink.Modify(true);
        exit(true);
    end;
}
