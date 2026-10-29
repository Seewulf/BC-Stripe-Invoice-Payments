namespace PrabinBhusal.StripePayments;

using Microsoft.Bank.BankAccount;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Foundation.NoSeries;

// Singleton setup. The Stripe secret key lives in isolated storage, never in a table field.
table 58150 "SIP Stripe Setup"
{
    Caption = 'Stripe Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
        }
        field(10; Enabled; Boolean)
        {
            Caption = 'Enabled';
            ToolTip = 'Specifies that payment links can be created. Links that already exist are still synchronized when this is turned off.';
        }
        field(11; Gateway; Enum "SIP Payment Gateway")
        {
            Caption = 'Gateway';
            ToolTip = 'Specifies the payment provider that creates and checks the payment pages.';
        }
        field(20; "Clearing Bank Account No."; Code[20])
        {
            Caption = 'Clearing Bank Account No.';
            TableRelation = "Bank Account";
            ToolTip = 'Specifies the bank account that receives Stripe payments until Stripe pays them out to your real bank account.';
        }
        field(21; "Payment Nos."; Code[20])
        {
            Caption = 'Payment Nos.';
            TableRelation = "No. Series";
            ToolTip = 'Specifies the number series for the document numbers of the payments that are posted.';
        }
        field(22; "Journal Template Name"; Code[10])
        {
            Caption = 'Journal Template Name';
            TableRelation = "Gen. Journal Template" where(Type = const("Cash Receipts"));
            ToolTip = 'Specifies the cash receipt journal template that the payments are posted with. Required when Journal Templ. Name Mandatory is turned on in General Ledger Setup.';

            trigger OnValidate()
            begin
                if Rec."Journal Template Name" <> xRec."Journal Template Name" then
                    Rec."Journal Batch Name" := '';
            end;
        }
        field(23; "Journal Batch Name"; Code[10])
        {
            Caption = 'Journal Batch Name';
            TableRelation = "Gen. Journal Batch".Name where("Journal Template Name" = field("Journal Template Name"));
            ToolTip = 'Specifies the journal batch that the payments are posted with. Required when Journal Templ. Name Mandatory is turned on in General Ledger Setup.';
        }
        field(30; "Success URL"; Text[250])
        {
            Caption = 'Success URL';
            InitValue = 'https://example.com/paid';
            ToolTip = 'Specifies the page that Stripe shows the customer after a successful payment.';
        }
        field(31; "Cancel URL"; Text[250])
        {
            Caption = 'Cancel URL';
            InitValue = 'https://example.com/cancelled';
            ToolTip = 'Specifies the page that Stripe shows the customer when they leave the payment page without paying.';
        }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }

    var
        SecretKeyStorageTok: Label 'SIP-Stripe-Secret-Key', Locked = true;

    procedure InsertIfMissing()
    begin
        Rec.Reset();
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;

    // An empty key removes the stored key.
    internal procedure SetSecretKey(SecretKey: SecretText)
    begin
        if SecretKey.IsEmpty() then begin
            if IsolatedStorage.Contains(SecretKeyStorageTok, DataScope::Company) then
                IsolatedStorage.Delete(SecretKeyStorageTok, DataScope::Company);
            exit;
        end;
        if EncryptionEnabled() then
            IsolatedStorage.SetEncrypted(SecretKeyStorageTok, SecretKey, DataScope::Company)
        else
            IsolatedStorage.Set(SecretKeyStorageTok, SecretKey, DataScope::Company);
    end;

    procedure HasSecretKey(): Boolean
    begin
        exit(IsolatedStorage.Contains(SecretKeyStorageTok, DataScope::Company));
    end;

    [NonDebuggable]
    internal procedure GetSecretKey() SecretKey: SecretText
    begin
        if IsolatedStorage.Get(SecretKeyStorageTok, DataScope::Company, SecretKey) then;
    end;
}
