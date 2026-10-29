namespace PrabinBhusal.StripePayments.Test;

using PrabinBhusal.StripePayments;
using System.TestLibraries.Utilities;

// Parses response bodies in the shape the Stripe API returns them.
codeunit 58193 "SIP Json Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        StripeGateway: Codeunit "SIP Stripe Gateway";
        CreatedSessionTxt: Label '{"id":"cs_test_a1B2c3D4","object":"checkout.session","amount_total":12345,"client_reference_id":"103001","currency":"usd","expires_at":1767225600,"mode":"payment","payment_intent":null,"payment_status":"unpaid","status":"open","url":"https://checkout.stripe.com/c/pay/cs_test_a1B2c3D4#fidkdWxOYHwnPyd1blpxYHZxWjA0"}', Locked = true;
        PaidSessionTxt: Label '{"id":"cs_test_a1B2c3D4","object":"checkout.session","amount_total":12345,"currency":"usd","expires_at":1767225600,"payment_intent":"pi_3QxYz2LkdIwHu7ix0abc1234","payment_status":"paid","status":"complete","url":null}', Locked = true;
        ExpiredSessionTxt: Label '{"id":"cs_test_e5F6g7H8","object":"checkout.session","amount_total":5000,"currency":"eur","expires_at":1767225600,"payment_intent":null,"payment_status":"unpaid","status":"expired","url":null}', Locked = true;
        BareSessionTxt: Label '{"id":"cs_test_x9","payment_intent":null,"amount_total":null}', Locked = true;
        ErrorBodyTxt: Label '{"error":{"code":"resource_missing","doc_url":"https://stripe.com/docs/error-codes/resource-missing","message":"No such checkout.session: cs_test_zzz","param":"session","type":"invalid_request_error"}}', Locked = true;

    [Test]
    procedure CreateResponseGivesIdUrlAndExpiry()
    var
        TempGatewayResult: Record "SIP Gateway Result";
        ExpectedExpiresAt: DateTime;
    begin
        // [GIVEN] the body Stripe returns for a new Checkout Session
        // [WHEN] it is parsed
        Assert.IsTrue(StripeGateway.ParseSession(CreatedSessionTxt, TempGatewayResult), 'parse');
        // [THEN] id, url, status and expiry are read, and there is no payment yet
        Assert.AreEqual('cs_test_a1B2c3D4', TempGatewayResult."Session Id", 'id');
        Assert.AreEqual('https://checkout.stripe.com/c/pay/cs_test_a1B2c3D4#fidkdWxOYHwnPyd1blpxYHZxWjA0', TempGatewayResult.URL, 'url');
        Assert.AreEqual('open', TempGatewayResult."Session Status", 'status');
        Assert.AreEqual('unpaid', TempGatewayResult."Payment Status", 'payment status');
        Assert.AreEqual('', TempGatewayResult."Payment Intent Id", 'payment intent');
        // 1767225600 is 2026-01-01T00:00:00Z, whatever the user's time zone
        Evaluate(ExpectedExpiresAt, '2026-01-01T00:00:00Z', 9);
        Assert.AreEqual(ExpectedExpiresAt, TempGatewayResult."Expires At", 'expires at');
    end;

    [Test]
    procedure PaidResponseGivesPaymentIntentAndAmount()
    var
        TempGatewayResult: Record "SIP Gateway Result";
        Expected: BigInteger;
    begin
        // [GIVEN] a complete and paid session
        // [WHEN] it is parsed
        Assert.IsTrue(StripeGateway.ParseSession(PaidSessionTxt, TempGatewayResult), 'parse');
        // [THEN] the payment intent, amount and currency are read; the null url reads as empty
        Expected := 12345;
        Assert.AreEqual('complete', TempGatewayResult."Session Status", 'status');
        Assert.AreEqual('paid', TempGatewayResult."Payment Status", 'payment status');
        Assert.AreEqual('pi_3QxYz2LkdIwHu7ix0abc1234', TempGatewayResult."Payment Intent Id", 'payment intent');
        Assert.AreEqual(Expected, TempGatewayResult."Amount Total (Minor Units)", 'amount');
        Assert.AreEqual('usd', TempGatewayResult.Currency, 'currency');
        Assert.AreEqual('', TempGatewayResult.URL, 'url');
    end;

    [Test]
    procedure ExpiredResponseIsRead()
    var
        TempGatewayResult: Record "SIP Gateway Result";
    begin
        // [GIVEN] an expired session
        // [WHEN] it is parsed
        Assert.IsTrue(StripeGateway.ParseSession(ExpiredSessionTxt, TempGatewayResult), 'parse');
        // [THEN] the status is expired and there is no payment
        Assert.AreEqual('cs_test_e5F6g7H8', TempGatewayResult."Session Id", 'id');
        Assert.AreEqual('expired', TempGatewayResult."Session Status", 'status');
        Assert.AreEqual('', TempGatewayResult."Payment Intent Id", 'payment intent');
    end;

    [Test]
    procedure NullAndMissingFieldsReadAsEmpty()
    var
        TempGatewayResult: Record "SIP Gateway Result";
        Expected: BigInteger;
    begin
        // [GIVEN] a session with null payment_intent and amount_total and no other fields
        // [WHEN] it is parsed
        Assert.IsTrue(StripeGateway.ParseSession(BareSessionTxt, TempGatewayResult), 'parse');
        // [THEN] nothing fails and the values are empty
        Expected := 0;
        Assert.AreEqual('cs_test_x9', TempGatewayResult."Session Id", 'id');
        Assert.AreEqual('', TempGatewayResult."Payment Intent Id", 'payment intent');
        Assert.AreEqual(Expected, TempGatewayResult."Amount Total (Minor Units)", 'amount');
        Assert.AreEqual('', TempGatewayResult."Session Status", 'status');
        Assert.AreEqual(0DT, TempGatewayResult."Expires At", 'expires at');
    end;

    [Test]
    procedure ErrorBodyGivesMessageAndCode()
    var
        TempGatewayResult: Record "SIP Gateway Result";
    begin
        // [GIVEN] a Stripe error body
        // [WHEN] it is parsed as an error and as a session
        // [THEN] the error reads as message and code, and it is not taken for a session
        Assert.AreEqual('No such checkout.session: cs_test_zzz (resource_missing)', StripeGateway.ParseError(ErrorBodyTxt), 'error text');
        Assert.IsFalse(StripeGateway.ParseSession(ErrorBodyTxt, TempGatewayResult), 'error body is not a session');
        Assert.AreNotEqual('', TempGatewayResult."Error Message", 'error message');
    end;

    [Test]
    procedure NonJsonErrorBodyIsHandled()
    begin
        // [GIVEN] a body that is not JSON, for example from a proxy
        // [WHEN] it is parsed as an error
        // [THEN] a readable message comes back instead of a runtime error
        Assert.AreNotEqual('', StripeGateway.ParseError('<html>Bad Gateway</html>'), 'error text');
    end;
}
