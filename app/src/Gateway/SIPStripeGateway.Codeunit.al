namespace PrabinBhusal.StripePayments;

using System.Utilities;

// Stripe Checkout Sessions API: form-encoded requests, JSON responses.
codeunit 58151 "SIP Stripe Gateway" implements "SIP IPayment Gateway"
{
    Access = Internal;

    var
        SessionsUrlTok: Label 'https://api.stripe.com/v1/checkout/sessions', Locked = true;
        StripeVersionTok: Label '2026-09-30.endive', Locked = true;
        InvoiceProductLbl: Label 'Invoice %1', Comment = '%1 = invoice no. Shown to the customer on the Stripe payment page.';
        SendFailedErr: Label 'The request to Stripe could not be sent: %1 In a sandbox, turn on Allow HttpClient Requests for this extension in Extension Management > Configure.', Comment = '%1 = error from the HTTP client';
        BlockedErr: Label 'Business Central blocked the request to Stripe. Turn on Allow HttpClient Requests for this extension in Extension Management > Configure.';
        UnexpectedResponseErr: Label 'Stripe returned a response that could not be read.';
        StripeErrorTxt: Label '%1 (%2)', Comment = '%1 = Stripe error message, %2 = Stripe error code or type';

    procedure CreateCheckoutSession(var PaymentLink: Record "SIP Payment Link"; CustomerEmail: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        StripeSetup: Record "SIP Stripe Setup";
        Body: TextBuilder;
        ResponseText: Text;
    begin
        StripeSetup.Get();
        AddParameter(Body, 'mode', 'payment');
        // cards only: a delayed method (bank debit) leaves the session complete but unpaid
        AddParameter(Body, 'allowed_payment_method_types[0]', 'card');
        AddParameter(Body, 'line_items[0][price_data][currency]', PaymentLink."Stripe Currency");
        AddParameter(Body, 'line_items[0][price_data][unit_amount]', Format(PaymentLink."Amount (Minor Units)", 0, 9));
        AddParameter(Body, 'line_items[0][price_data][product_data][name]', StrSubstNo(InvoiceProductLbl, PaymentLink."Invoice No."));
        AddParameter(Body, 'line_items[0][quantity]', '1');
        // an empty value asks Stripe to unset the parameter, which create refuses
        if StripeSetup."Success URL" <> '' then
            AddParameter(Body, 'success_url', StripeSetup."Success URL");
        if StripeSetup."Cancel URL" <> '' then
            AddParameter(Body, 'cancel_url', StripeSetup."Cancel URL");
        AddParameter(Body, 'client_reference_id', PaymentLink."Invoice No.");
        AddParameter(Body, 'metadata[bc_invoice_no]', PaymentLink."Invoice No.");
        AddParameter(Body, 'payment_intent_data[metadata][bc_invoice_no]', PaymentLink."Invoice No.");
        if CustomerEmail <> '' then
            AddParameter(Body, 'customer_email', CustomerEmail);
        // a new idempotency key per attempt: Stripe never creates two sessions for one request
        if not SendRequest('POST', SessionsUrlTok, Body.ToText(), true, ResponseText, Result) then
            exit(false);
        exit(ParseSession(ResponseText, Result));
    end;

    procedure GetCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        ResponseText: Text;
    begin
        if not SendRequest('GET', SessionUrl(SessionId), '', false, ResponseText, Result) then
            exit(false);
        exit(ParseSession(ResponseText, Result));
    end;

    procedure ExpireCheckoutSession(SessionId: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        ResponseText: Text;
    begin
        if not SendRequest('POST', SessionUrl(SessionId) + '/expire', '', false, ResponseText, Result) then
            exit(false);
        exit(ParseSession(ResponseText, Result));
    end;

    procedure TestConnection(var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        ResponseText: Text;
    begin
        exit(SendRequest('GET', SessionsUrlTok + '?limit=1', '', false, ResponseText, Result));
    end;

    // Returns false on a missing body, a missing session id or a body that is not JSON.
    internal procedure ParseSession(JsonText: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        Session: JsonObject;
        UnixEpoch: DateTime;
        ExpiresAt: BigInteger;
    begin
        if Session.ReadFrom(JsonText) then
            Result."Session Id" := CopyStr(ReadText(Session, 'id'), 1, MaxStrLen(Result."Session Id"));
        if Result."Session Id" = '' then begin
            Result."Error Message" := UnexpectedResponseErr;
            exit(false);
        end;
        Result.URL := CopyStr(ReadText(Session, 'url'), 1, MaxStrLen(Result.URL));
        Result."Session Status" := CopyStr(ReadText(Session, 'status'), 1, MaxStrLen(Result."Session Status"));
        Result."Payment Status" := CopyStr(ReadText(Session, 'payment_status'), 1, MaxStrLen(Result."Payment Status"));
        Result."Payment Intent Id" := CopyStr(ReadText(Session, 'payment_intent'), 1, MaxStrLen(Result."Payment Intent Id"));
        Result."Amount Total (Minor Units)" := ReadBigInteger(Session, 'amount_total');
        Result.Currency := CopyStr(ReadText(Session, 'currency'), 1, MaxStrLen(Result.Currency));
        // Unix seconds, counted from a UTC epoch so the user's time zone plays no part
        ExpiresAt := ReadBigInteger(Session, 'expires_at');
        if ExpiresAt <> 0 then begin
            Evaluate(UnixEpoch, '1970-01-01T00:00:00Z', 9);
            Result."Expires At" := UnixEpoch + ExpiresAt * 1000;
        end;
        exit(true);
    end;

    // Turns {"error":{"type":"...","code":"...","message":"..."}} into one readable line.
    internal procedure ParseError(JsonText: Text): Text
    var
        Response: JsonObject;
        StripeError: JsonObject;
        Token: JsonToken;
        ErrorMessage: Text;
        ErrorCode: Text;
    begin
        if not Response.ReadFrom(JsonText) then
            exit(UnexpectedResponseErr);
        if not Response.Get('error', Token) then
            exit(UnexpectedResponseErr);
        if not Token.IsObject() then
            exit(UnexpectedResponseErr);
        StripeError := Token.AsObject();
        ErrorMessage := ReadText(StripeError, 'message');
        ErrorCode := ReadText(StripeError, 'code');
        if ErrorCode = '' then
            ErrorCode := ReadText(StripeError, 'type');
        if ErrorMessage = '' then
            exit(UnexpectedResponseErr);
        if ErrorCode = '' then
            exit(ErrorMessage);
        exit(StrSubstNo(StripeErrorTxt, ErrorMessage, ErrorCode));
    end;

    [NonDebuggable]
    local procedure SendRequest(Method: Text; Url: Text; Body: Text; AddIdempotencyKey: Boolean; var ResponseText: Text; var Result: Record "SIP Gateway Result" temporary): Boolean
    var
        StripeSetup: Record "SIP Stripe Setup";
        Client: HttpClient;
        Request: HttpRequestMessage;
        Response: HttpResponseMessage;
        Content: HttpContent;
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
    begin
        Result.Init();
        ResponseText := '';
        Request.Method(Method);
        Request.SetRequestUri(Url);
        Request.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', SecretStrSubstNo('Bearer %1', StripeSetup.GetSecretKey()));
        // fixed API version, so request and response shapes do not follow the account default
        RequestHeaders.Add('Stripe-Version', StripeVersionTok);
        if AddIdempotencyKey then
            RequestHeaders.Add('Idempotency-Key', LowerCase(DelChr(Format(CreateGuid()), '=', '{}')));
        if Method = 'POST' then begin
            Content.WriteFrom(Body);
            Content.GetHeaders(ContentHeaders);
            if ContentHeaders.Contains('Content-Type') then
                ContentHeaders.Remove('Content-Type');
            ContentHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');
            Request.Content(Content);
        end;

        if not Client.Send(Request, Response) then begin
            Result."Error Message" := CopyStr(StrSubstNo(SendFailedErr, GetLastErrorText()), 1, MaxStrLen(Result."Error Message"));
            exit(false);
        end;
        Result."HTTP Status Code" := Response.HttpStatusCode();
        if Response.IsBlockedByEnvironment() then begin
            Result."Error Message" := BlockedErr;
            exit(false);
        end;
        Response.Content().ReadAs(ResponseText);
        if not Response.IsSuccessStatusCode() then begin
            Result."Error Message" := CopyStr(ParseError(ResponseText), 1, MaxStrLen(Result."Error Message"));
            exit(false);
        end;
        exit(true);
    end;

    local procedure SessionUrl(SessionId: Text): Text
    var
        Uri: Codeunit Uri;
    begin
        exit(SessionsUrlTok + '/' + Uri.EscapeDataString(SessionId));
    end;

    local procedure AddParameter(var Body: TextBuilder; Name: Text; Value: Text)
    var
        Uri: Codeunit Uri;
    begin
        if Body.Length() > 0 then
            Body.Append('&');
        Body.Append(Name);
        Body.Append('=');
        Body.Append(Uri.EscapeDataString(Value));
    end;

    // null and missing values read as empty, so a session without payment_intent is fine
    local procedure ReadText(JObject: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not JObject.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure ReadBigInteger(JObject: JsonObject; KeyName: Text): BigInteger
    var
        Token: JsonToken;
    begin
        if not JObject.Get(KeyName, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsBigInteger());
    end;
}
