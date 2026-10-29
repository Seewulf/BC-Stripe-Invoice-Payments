namespace PrabinBhusal.StripePayments;

permissionset 58150 "SIP STRIPE PAY"
{
    Caption = 'Stripe Invoice Payments Sample';
    Assignable = true;

    Permissions =
        tabledata "SIP Stripe Setup" = RIMD,
        tabledata "SIP Payment Link" = RIMD,
        tabledata "SIP Activity Log" = RIMD,
        tabledata "SIP Gateway Result" = RIMD,
        table "SIP Stripe Setup" = X,
        table "SIP Payment Link" = X,
        table "SIP Activity Log" = X,
        table "SIP Gateway Result" = X,
        codeunit "SIP Payment Link Mgt" = X,
        codeunit "SIP Stripe Gateway" = X,
        codeunit "SIP Stripe Amount" = X,
        codeunit "SIP Payment Sync" = X,
        codeunit "SIP Check Payment Link" = X,
        codeunit "SIP Post Payment" = X,
        codeunit "SIP Activity Logger" = X,
        page "SIP Stripe Setup" = X,
        page "SIP Payment Links" = X,
        page "SIP Activity Log" = X;
}
