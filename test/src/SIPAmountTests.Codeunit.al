namespace PrabinBhusal.StripePayments.Test;

using PrabinBhusal.StripePayments;
using System.TestLibraries.Utilities;

codeunit 58192 "SIP Amount Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        StripeAmount: Codeunit "SIP Stripe Amount";

    [Test]
    procedure TwoDecimalCurrencyIsSentInCents()
    var
        Expected: BigInteger;
    begin
        // [GIVEN] 12.34 USD
        // [WHEN] it is converted to Stripe minor units and back
        // [THEN] Stripe gets 1234 cents and 1234 cents read back as 12.34
        Expected := 1234;
        Assert.AreEqual(Expected, StripeAmount.ToMinorUnits(12.34, 'usd'), 'USD to cents');
        Assert.AreEqual(12.34, StripeAmount.FromMinorUnits(1234, 'usd'), 'cents to USD');
    end;

    [Test]
    procedure ZeroDecimalCurrencyIsSentAsIs()
    var
        Expected: BigInteger;
    begin
        // [GIVEN] 1234 JPY, a currency without decimals in Stripe
        // [WHEN] it is converted to Stripe minor units and back
        // [THEN] the amount is unchanged both ways
        Expected := 1234;
        Assert.AreEqual(Expected, StripeAmount.ToMinorUnits(1234, 'JPY'), 'JPY to Stripe');
        Assert.AreEqual(1234, StripeAmount.FromMinorUnits(1234, 'jpy'), 'Stripe to JPY');
    end;

    [Test]
    procedure ThreeDecimalCurrencyIsRefused()
    begin
        // [GIVEN] 1.234 KWD, a three-decimal currency
        // [WHEN] it is converted to Stripe minor units
        asserterror StripeAmount.ToMinorUnits(1.234, 'kwd');
        // [THEN] a clear error says it is not supported
        Assert.ExpectedError('three decimals');
    end;

    [Test]
    procedure UgandanShillingIsSentTimesHundred()
    var
        Expected: BigInteger;
    begin
        // [GIVEN] 5 UGX, which Stripe wants as a two-decimal value ending in 00
        // [WHEN] it is converted to Stripe minor units and back
        // [THEN] Stripe gets 500 and 500 reads back as 5
        Expected := 500;
        Assert.AreEqual(Expected, StripeAmount.ToMinorUnits(5, 'ugx'), 'UGX to Stripe');
        Assert.AreEqual(5, StripeAmount.FromMinorUnits(500, 'ugx'), 'Stripe to UGX');
    end;

    [Test]
    procedure FractionOfZeroDecimalCurrencyIsRefused()
    begin
        // [GIVEN] 12.5 JPY, which Stripe cannot charge
        // [WHEN] it is converted to Stripe minor units
        asserterror StripeAmount.ToMinorUnits(12.5, 'jpy');
        // [THEN] it is refused instead of silently rounded
        Assert.ExpectedError('whole numbers');
    end;
}
