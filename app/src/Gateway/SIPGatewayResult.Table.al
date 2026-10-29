namespace PrabinBhusal.StripePayments;

// In-memory result of one gateway call.
table 58153 "SIP Gateway Result"
{
    Caption = 'Gateway Result';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
        }
        field(10; "Session Id"; Text[250])
        {
            Caption = 'Session Id';
        }
        field(11; URL; Text[2048])
        {
            Caption = 'URL';
        }
        field(12; "Expires At"; DateTime)
        {
            Caption = 'Expires At';
        }
        field(13; "Session Status"; Text[30])
        {
            Caption = 'Session Status';
        }
        field(14; "Payment Status"; Text[30])
        {
            Caption = 'Payment Status';
        }
        field(15; "Payment Intent Id"; Text[100])
        {
            Caption = 'Payment Intent Id';
        }
        field(16; "Amount Total (Minor Units)"; BigInteger)
        {
            Caption = 'Amount Total (Minor Units)';
        }
        field(17; Currency; Text[3])
        {
            Caption = 'Currency';
        }
        field(20; "HTTP Status Code"; Integer)
        {
            Caption = 'HTTP Status Code';
        }
        field(21; "Error Message"; Text[2048])
        {
            Caption = 'Error Message';
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
