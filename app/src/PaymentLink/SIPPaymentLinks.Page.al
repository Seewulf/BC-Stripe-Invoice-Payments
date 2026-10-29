namespace PrabinBhusal.StripePayments;

using Microsoft.Sales.Receivables;

page 58151 "SIP Payment Links"
{
    Caption = 'Stripe Payment Links';
    PageType = List;
    SourceTable = "SIP Payment Link";
    SourceTableView = sorting("Entry No.") order(descending);
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Links)
            {
                field("Entry No."; Rec."Entry No.") { }
                field("Invoice No."; Rec."Invoice No.") { }
                field("Customer No."; Rec."Customer No.") { }
                field(Status; Rec.Status) { }
                field(Amount; Rec.Amount) { }
                field("Currency Code"; Rec."Currency Code") { }
                field("Amount Paid"; Rec."Amount Paid") { }
                field("Needs Review"; Rec."Needs Review") { }
                field("Payment Document No."; Rec."Payment Document No.") { }
                field("Expires At"; Rec."Expires At") { }
                field("Synced At"; Rec."Synced At") { }
                field("Last Error"; Rec."Last Error") { }
                field(URL; Rec.URL)
                {
                    ExtendedDatatype = URL;
                }
                field("Session Id"; Rec."Session Id") { Visible = false; }
                field("Payment Intent Id"; Rec."Payment Intent Id") { Visible = false; }
                field("Stripe Currency"; Rec."Stripe Currency") { Visible = false; }
                field("Amount (Minor Units)"; Rec."Amount (Minor Units)") { Visible = false; }
                field("Cust. Ledger Entry No."; Rec."Cust. Ledger Entry No.") { Visible = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SyncNow)
            {
                Caption = 'Sync Now';
                Image = Refresh;
                ToolTip = 'Check all open links with Stripe now and post the paid ones. The job queue does the same every few minutes.';

                trigger OnAction()
                var
                    PaymentSync: Codeunit "SIP Payment Sync";
                begin
                    Message(SyncedMsg, PaymentSync.SyncOpenLinks());
                    CurrPage.Update(false);
                end;
            }
            action(OpenPaymentPage)
            {
                Caption = 'Open Payment Page';
                Image = Web;
                ToolTip = 'Open the Stripe payment page of the selected open link.';

                trigger OnAction()
                var
                    PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
                begin
                    PaymentLinkMgt.OpenPaymentPage(Rec);
                end;
            }
            action(RetryPosting)
            {
                Caption = 'Retry Posting';
                Image = PostingEntries;
                ToolTip = 'Post the payment of a Failed link again, for example after unblocking the customer.';

                trigger OnAction()
                var
                    PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
                begin
                    if PaymentLinkMgt.RetryPosting(Rec) then
                        Message(PostedMsg, Rec."Payment Document No.")
                    else
                        Message(StillFailedMsg, Rec."Last Error");
                    CurrPage.Update(false);
                end;
            }
            action(ExpireLink)
            {
                Caption = 'Expire Link';
                Image = Cancel;
                ToolTip = 'Close the Stripe payment page of the selected open link, so the customer can no longer pay with it.';

                trigger OnAction()
                var
                    PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
                begin
                    Rec.TestField(Status, Rec.Status::Open);
                    if not Confirm(ExpireQst, false, Rec."Invoice No.") then
                        exit;
                    PaymentLinkMgt.ExpireLink(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
        area(Navigation)
        {
            action(CustomerLedgerEntry)
            {
                Caption = 'Customer Ledger Entry';
                Image = CustomerLedger;
                RunObject = page "Customer Ledger Entries";
                RunPageLink = "Entry No." = field("Cust. Ledger Entry No.");
                ToolTip = 'View the invoice entry that the link is for.';
            }
        }
        area(Promoted)
        {
            actionref(SyncNow_Promoted; SyncNow) { }
            actionref(OpenPaymentPage_Promoted; OpenPaymentPage) { }
            actionref(RetryPosting_Promoted; RetryPosting) { }
            actionref(ExpireLink_Promoted; ExpireLink) { }
        }
    }

    var
        SyncedMsg: Label '%1 payment links checked.', Comment = '%1 = number of links';
        PostedMsg: Label 'The payment is posted as document %1.', Comment = '%1 = payment document no.';
        StillFailedMsg: Label 'Posting failed again: %1', Comment = '%1 = error message';
        ExpireQst: Label 'Expire the payment page for invoice %1? The customer can no longer pay with it.', Comment = '%1 = invoice no.';
}
