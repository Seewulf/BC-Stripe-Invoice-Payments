namespace PrabinBhusal.StripePayments;

enum 58150 "SIP Payment Link Status"
{
    Extensible = false;

    value(0; Open) { Caption = 'Open'; }
    value(1; Paid) { Caption = 'Paid'; }
    value(2; Posted) { Caption = 'Posted'; }
    value(3; Failed) { Caption = 'Failed'; }
    value(4; Expired) { Caption = 'Expired'; }
    value(5; Cancelled) { Caption = 'Cancelled'; }
}
