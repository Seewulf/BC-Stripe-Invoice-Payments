namespace PrabinBhusal.StripePayments;

// Extensible so another provider, or a test mock, can be plugged in.
enum 58151 "SIP Payment Gateway" implements "SIP IPayment Gateway"
{
    Extensible = true;

    value(0; Stripe)
    {
        Caption = 'Stripe';
        Implementation = "SIP IPayment Gateway" = "SIP Stripe Gateway";
    }
}
