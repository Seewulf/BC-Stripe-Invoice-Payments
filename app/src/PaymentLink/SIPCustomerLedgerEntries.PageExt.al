namespace PrabinBhusal.StripePayments;

using Microsoft.Sales.Receivables;

pageextension 58151 "SIP Customer Ledger Entries" extends "Customer Ledger Entries"
{
    actions
    {
        addlast(Processing)
        {
            action(SIPCreateStripePaymentLink)
            {
                ApplicationArea = All;
                Caption = 'Create Stripe Payment Link';
                Image = ElectronicPayment;
                ToolTip = 'Create a Stripe payment page for the remaining amount of the selected open invoice. Business Central posts the payment when the customer has paid.';

                trigger OnAction()
                var
                    PaymentLink: Record "SIP Payment Link";
                    PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
                begin
                    PaymentLink := PaymentLinkMgt.CreateForCustLedgerEntry(Rec);
                    // save the link before asking the user anything
                    Commit();
                    PaymentLinkMgt.OfferToOpen(PaymentLink);
                end;
            }
            action(SIPStripePaymentLinks)
            {
                ApplicationArea = All;
                Caption = 'Stripe Payment Links';
                Image = Links;
                RunObject = page "SIP Payment Links";
                RunPageLink = "Invoice No." = field("Document No.");
                ToolTip = 'View the Stripe payment links for the selected invoice.';
            }
        }
        addlast(Category_Process)
        {
            actionref(SIPCreateStripePaymentLink_Promoted; SIPCreateStripePaymentLink) { }
        }
    }
}
