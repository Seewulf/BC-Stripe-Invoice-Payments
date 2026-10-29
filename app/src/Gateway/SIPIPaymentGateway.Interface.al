namespace PrabinBhusal.StripePayments;

// Payment provider calls. Each method returns false when the call failed; Result then holds the HTTP status and error message.
interface "SIP IPayment Gateway"
{
    procedure CreateCheckoutSession(var PaymentLink: Record "SIP Payment Link"; CustomerEmail: Text; var Result: Record "SIP Gateway Result" temporary): Boolean;
    procedure GetCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean;
    procedure ExpireCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean;
    procedure TestConnection(var Result: Record "SIP Gateway Result" temporary): Boolean;
}
