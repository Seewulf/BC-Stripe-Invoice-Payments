namespace PrabinBhusal.StripePayments.Test;

using PrabinBhusal.StripePayments;

// Stands in for Stripe: answers are scripted per test, and it remembers what it was sent.
// HttpClientHandler mocking is on-premises only, so the tests swap the gateway instead.
codeunit 58191 "SIP Mock Gateway" implements "SIP IPayment Gateway"
{
    SingleInstance = true;

    var
        SessionAmounts: Dictionary of [Text, BigInteger];
        SessionCurrencies: Dictionary of [Text, Text];
        CreateFails: Boolean;
        GetFails: Boolean;
        NextSessionStatus: Text;
        NextPaymentStatus: Text;
        SentAmountMinorUnits: BigInteger;
        SentCurrency: Text;
        SentInvoiceNo: Code[20];
        SentCustomerEmail: Text;
        ExpiredSessionId: Text;
        PaidAmountOverride: BigInteger;
        PaidCurrencyOverride: Text;
        ExpireFailStatusCode: Integer;
        MockErrorTxt: Label 'Your card was declined. (card_declined)', Locked = true;

    procedure Reset()
    begin
        Clear(SessionAmounts);
        Clear(SessionCurrencies);
        CreateFails := false;
        GetFails := false;
        NextSessionStatus := 'open';
        NextPaymentStatus := 'unpaid';
        SentAmountMinorUnits := 0;
        SentCurrency := '';
        SentInvoiceNo := '';
        SentCustomerEmail := '';
        ExpiredSessionId := '';
        PaidAmountOverride := 0;
        PaidCurrencyOverride := '';
        ExpireFailStatusCode := 0;
    end;

    procedure SetCreateFails(Fails: Boolean)
    begin
        CreateFails := Fails;
    end;

    procedure SetGetFails(Fails: Boolean)
    begin
        GetFails := Fails;
    end;

    // What every following Get Session call returns, for example complete + paid.
    procedure SetSessionOutcome(SessionStatus: Text; PaymentStatus: Text)
    begin
        NextSessionStatus := SessionStatus;
        NextPaymentStatus := PaymentStatus;
    end;

    // Get Session reports this amount instead of the one asked; 0 = no override.
    procedure SetPaidAmountOverride(MinorUnits: BigInteger)
    begin
        PaidAmountOverride := MinorUnits;
    end;

    // Get Session reports this currency instead of the one asked; empty = no override.
    procedure SetPaidCurrencyOverride(Currency: Text)
    begin
        PaidCurrencyOverride := Currency;
    end;

    // Expire Session fails with this HTTP status; 0 = it succeeds.
    procedure SetExpireFails(HttpStatusCode: Integer)
    begin
        ExpireFailStatusCode := HttpStatusCode;
    end;

    procedure LastCustomerEmail(): Text
    begin
        exit(SentCustomerEmail);
    end;

    procedure LastExpiredSessionId(): Text
    begin
        exit(ExpiredSessionId);
    end;

    procedure MockErrorMessage(): Text
    begin
        exit(MockErrorTxt);
    end;

    procedure LastAmountMinorUnits(): BigInteger
    begin
        exit(SentAmountMinorUnits);
    end;

    procedure LastCurrency(): Text
    begin
        exit(SentCurrency);
    end;

    procedure LastInvoiceNo(): Code[20]
    begin
        exit(SentInvoiceNo);
    end;

    procedure CreateCheckoutSession(var PaymentLink: Record "SIP Payment Link"; CustomerEmail: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        SessionId: Text[250];
    begin
        SentAmountMinorUnits := PaymentLink."Amount (Minor Units)";
        SentCurrency := PaymentLink."Stripe Currency";
        SentInvoiceNo := PaymentLink."Invoice No.";
        SentCustomerEmail := CustomerEmail;
        Result.Init();
        if CreateFails then begin
            Result."HTTP Status Code" := 402;
            Result."Error Message" := MockErrorTxt;
            exit(false);
        end;

        SessionId := CopyStr('cs_test_' + NewId(), 1, MaxStrLen(SessionId));
        SessionAmounts.Set(SessionId, PaymentLink."Amount (Minor Units)");
        SessionCurrencies.Set(SessionId, PaymentLink."Stripe Currency");
        Result."HTTP Status Code" := 200;
        Result."Session Id" := SessionId;
        Result.URL := CopyStr('https://checkout.stripe.com/c/pay/' + SessionId, 1, MaxStrLen(Result.URL));
        Result."Expires At" := CurrentDateTime() + 24 * 60 * 60 * 1000;
        Result."Session Status" := 'open';
        Result."Payment Status" := 'unpaid';
        Result."Amount Total (Minor Units)" := PaymentLink."Amount (Minor Units)";
        Result.Currency := PaymentLink."Stripe Currency";
        exit(true);
    end;

    procedure GetCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    begin
        Result.Init();
        if GetFails then begin
            Result."HTTP Status Code" := 500;
            Result."Error Message" := MockErrorTxt;
            exit(false);
        end;

        Result."HTTP Status Code" := 200;
        Result."Session Id" := CopyStr(SessionId, 1, MaxStrLen(Result."Session Id"));
        Result."Session Status" := CopyStr(NextSessionStatus, 1, MaxStrLen(Result."Session Status"));
        Result."Payment Status" := CopyStr(NextPaymentStatus, 1, MaxStrLen(Result."Payment Status"));
        if SessionAmounts.ContainsKey(SessionId) then begin
            Result."Amount Total (Minor Units)" := SessionAmounts.Get(SessionId);
            Result.Currency := CopyStr(SessionCurrencies.Get(SessionId), 1, MaxStrLen(Result.Currency));
        end;
        if PaidAmountOverride <> 0 then
            Result."Amount Total (Minor Units)" := PaidAmountOverride;
        if PaidCurrencyOverride <> '' then
            Result.Currency := CopyStr(PaidCurrencyOverride, 1, MaxStrLen(Result.Currency));
        // one payment intent per session, like Stripe
        if NextPaymentStatus = 'paid' then
            Result."Payment Intent Id" := CopyStr('pi_' + CopyStr(SessionId, 9, 24), 1, MaxStrLen(Result."Payment Intent Id"));
        exit(true);
    end;

    procedure ExpireCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    begin
        Result.Init();
        if ExpireFailStatusCode <> 0 then begin
            Result."HTTP Status Code" := ExpireFailStatusCode;
            Result."Error Message" := MockErrorTxt;
            exit(false);
        end;
        ExpiredSessionId := SessionId;
        Result."HTTP Status Code" := 200;
        Result."Session Id" := CopyStr(SessionId, 1, MaxStrLen(Result."Session Id"));
        Result."Session Status" := 'expired';
        Result."Payment Status" := 'unpaid';
        exit(true);
    end;

    procedure TestConnection(var Result: Record "SIP Gateway Result" temporary): Boolean
    begin
        Result.Init();
        Result."HTTP Status Code" := 200;
        exit(true);
    end;

    local procedure NewId(): Text
    begin
        exit(LowerCase(DelChr(Format(CreateGuid()), '=', '{}-')));
    end;
}
