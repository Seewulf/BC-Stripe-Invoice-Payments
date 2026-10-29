namespace PrabinBhusal.StripePayments.Test;

using PrabinBhusal.StripePayments;

// Lets the tests swap Stripe for the mock gateway through the setup.
enumextension 58190 "SIP Mock Gateway" extends "SIP Payment Gateway"
{
    value(58190; "SIP Mock")
    {
        Caption = 'Mock (tests only)';
        Implementation = "SIP IPayment Gateway" = "SIP Mock Gateway";
    }
}
