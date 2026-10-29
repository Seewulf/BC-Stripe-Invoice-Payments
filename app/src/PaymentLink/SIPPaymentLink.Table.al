namespace PrabinBhusal.StripePayments;

using Microsoft.Finance.Currency;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Receivables;

// One Stripe Checkout page for one posted sales invoice.
table 58151 "SIP Payment Link"
{
    Caption = 'Payment Link';
    DataClassification = CustomerContent;
    DrillDownPageId = "SIP Payment Links";
    LookupPageId = "SIP Payment Links";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            ToolTip = 'Specifies the number of the payment link.';
        }
        field(2; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            TableRelation = Customer;
            ToolTip = 'Specifies the customer who pays the invoice.';
        }
        field(3; "Invoice No."; Code[20])
        {
            Caption = 'Invoice No.';
            ToolTip = 'Specifies the posted sales invoice that the link is for.';
        }
        field(4; "Cust. Ledger Entry No."; Integer)
        {
            Caption = 'Cust. Ledger Entry No.';
            TableRelation = "Cust. Ledger Entry";
            ToolTip = 'Specifies the customer ledger entry of the invoice.';
        }
        field(10; Amount; Decimal)
        {
            Caption = 'Amount';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            ToolTip = 'Specifies the amount the customer is asked to pay. This is the remaining amount of the invoice when the link was created.';
        }
        field(11; "Currency Code"; Code[10])
        {
            Caption = 'Currency Code';
            TableRelation = Currency;
            ToolTip = 'Specifies the currency of the invoice. Blank means local currency.';
        }
        field(12; "Stripe Currency"; Text[3])
        {
            Caption = 'Stripe Currency';
            ToolTip = 'Specifies the three-letter ISO currency code sent to Stripe.';
        }
        field(13; "Amount (Minor Units)"; BigInteger)
        {
            Caption = 'Amount (Minor Units)';
            ToolTip = 'Specifies the amount sent to Stripe in the smallest currency unit, for example cents.';
        }
        field(20; "Session Id"; Text[250])
        {
            Caption = 'Session Id';
            ToolTip = 'Specifies the ID of the Stripe Checkout Session.';
        }
        field(21; URL; Text[2048])
        {
            Caption = 'URL';
            ToolTip = 'Specifies the address of the Stripe payment page. Send it to the customer.';
        }
        field(22; "Expires At"; DateTime)
        {
            Caption = 'Expires At';
            ToolTip = 'Specifies when Stripe closes the payment page.';
        }
        field(30; Status; Enum "SIP Payment Link Status")
        {
            Caption = 'Status';
            ToolTip = 'Specifies where the link is: Open, Paid (not posted yet), Posted, Failed (paid, but posting failed), Expired or Cancelled.';
        }
        field(31; "Payment Intent Id"; Text[100])
        {
            Caption = 'Payment Intent Id';
            ToolTip = 'Specifies the Stripe payment. It is also the external document no. of the posted payment.';
        }
        field(32; "Amount Paid"; Decimal)
        {
            Caption = 'Amount Paid';
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            ToolTip = 'Specifies the amount that Stripe reports as paid.';
        }
        field(33; "Payment Document No."; Code[20])
        {
            Caption = 'Payment Document No.';
            ToolTip = 'Specifies the document no. of the posted customer payment.';
        }
        field(34; "Needs Review"; Boolean)
        {
            Caption = 'Needs Review';
            ToolTip = 'Specifies that the payment was posted but not applied, or that the amount paid differs from the amount asked. Apply it manually.';
        }
        field(40; "Last Error"; Text[2048])
        {
            Caption = 'Last Error';
            ToolTip = 'Specifies the last error from Stripe or from posting.';
        }
        field(41; "Synced At"; DateTime)
        {
            Caption = 'Synced At';
            ToolTip = 'Specifies when the link was last checked with Stripe.';
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(InvoiceStatus; "Invoice No.", Status) { }
        key(Status; Status) { }
    }
}
