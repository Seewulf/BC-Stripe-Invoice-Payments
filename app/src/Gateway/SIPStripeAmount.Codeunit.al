namespace PrabinBhusal.StripePayments;

using Microsoft.Finance.Currency;
using Microsoft.Finance.GeneralLedger.Setup;

// Business Central amounts and currency codes to Stripe minor units and ISO codes, and back.
codeunit 58152 "SIP Stripe Amount"
{
    Access = Internal;

    var
        NoIsoCodeErr: Label 'Currency %1 has no three-letter ISO code. Fill in the ISO Code on the currency card, or the LCY Code in General Ledger Setup for the local currency.', Comment = '%1 = currency code, or LCY';
        ThreeDecimalCurrencyErr: Label 'Currency %1 uses three decimals in Stripe. This sample does not support three-decimal currencies.', Comment = '%1 = ISO currency code';
        FractionErr: Label 'Stripe cannot charge %2 %1. %1 amounts must be whole numbers.', Comment = '%1 = ISO currency code, %2 = amount';
        LocalCurrencyTok: Label 'LCY', Locked = true;

    procedure StripeCurrency(CurrencyCode: Code[10]): Text[3]
    var
        Currency: Record Currency;
        GeneralLedgerSetup: Record "General Ledger Setup";
        IsoCode: Text;
    begin
        if CurrencyCode = '' then begin
            GeneralLedgerSetup.SetLoadFields("LCY Code");
            GeneralLedgerSetup.Get();
            IsoCode := GeneralLedgerSetup."LCY Code";
        end else begin
            IsoCode := CurrencyCode;
            Currency.SetLoadFields("ISO Code");
            if Currency.Get(CurrencyCode) then
                if Currency."ISO Code" <> '' then
                    IsoCode := Currency."ISO Code";
        end;
        if StrLen(IsoCode) <> 3 then
            if CurrencyCode = '' then
                Error(NoIsoCodeErr, LocalCurrencyTok)
            else
                Error(NoIsoCodeErr, CurrencyCode);
        exit(CopyStr(LowerCase(IsoCode), 1, 3));
    end;

    procedure ToMinorUnits(Amount: Decimal; IsoCode: Text): BigInteger
    begin
        // never round: Stripe would charge a different amount than the invoice asks
        if WholeUnitsOnly(IsoCode) and (Amount <> Round(Amount, 1)) then
            Error(FractionErr, UpperCase(IsoCode), Amount);
        if IsZeroDecimal(IsoCode) then
            exit(Round(Amount, 1));
        exit(Round(Amount * 100, 1));
    end;

    procedure FromMinorUnits(MinorUnits: BigInteger; IsoCode: Text): Decimal
    begin
        if IsZeroDecimal(IsoCode) then
            exit(MinorUnits);
        exit(MinorUnits / 100);
    end;

    // Stripe's lists of zero-decimal and three-decimal currencies. ISK and UGX are sent x100 (Stripe special cases).
    local procedure IsZeroDecimal(IsoCode: Text): Boolean
    begin
        case LowerCase(IsoCode) of
            'bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', 'pyg', 'rwf', 'vnd', 'vuv', 'xaf', 'xof', 'xpf':
                exit(true);
            'bhd', 'jod', 'kwd', 'omr', 'tnd':
                Error(ThreeDecimalCurrencyErr, UpperCase(IsoCode));
        end;
        exit(false);
    end;

    local procedure WholeUnitsOnly(IsoCode: Text): Boolean
    begin
        if IsZeroDecimal(IsoCode) then
            exit(true);
        exit(LowerCase(IsoCode) in ['isk', 'ugx']);
    end;
}
