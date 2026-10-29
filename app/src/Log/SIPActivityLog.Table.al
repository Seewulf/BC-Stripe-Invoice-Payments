namespace PrabinBhusal.StripePayments;

// One row per Stripe call or posting attempt. Never holds keys, request bodies or e-mail addresses.
table 58152 "SIP Activity Log"
{
    Caption = 'Stripe Activity Log';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            ToolTip = 'Specifies the number of the entry.';
        }
        field(2; Operation; Text[50])
        {
            Caption = 'Operation';
            ToolTip = 'Specifies what was done, for example Create Session or Post Payment.';
        }
        field(3; "Invoice No."; Code[20])
        {
            Caption = 'Invoice No.';
            ToolTip = 'Specifies the invoice that the operation was for.';
        }
        field(4; "Session Id"; Text[250])
        {
            Caption = 'Session Id';
            ToolTip = 'Specifies the Stripe Checkout Session.';
        }
        field(5; "HTTP Status Code"; Integer)
        {
            Caption = 'HTTP Status Code';
            ToolTip = 'Specifies the HTTP status that Stripe returned. 0 means that no response was received.';
        }
        field(6; "Duration (ms)"; Integer)
        {
            Caption = 'Duration (ms)';
            ToolTip = 'Specifies how long the call took, in milliseconds.';
        }
        field(7; Success; Boolean)
        {
            Caption = 'Success';
            ToolTip = 'Specifies whether the operation succeeded.';
        }
        field(8; Message; Text[2048])
        {
            Caption = 'Message';
            ToolTip = 'Specifies the result or the error message.';
        }
        field(9; "Error Call Stack"; Text[2048])
        {
            Caption = 'Error Call Stack';
            ToolTip = 'Specifies where the error was raised.';
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
