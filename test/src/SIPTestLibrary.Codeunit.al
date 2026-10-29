namespace PrabinBhusal.StripePayments.Test;

using Microsoft.Bank.BankAccount;
using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.GeneralLedger.Posting;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.NoSeries;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Receivables;
using PrabinBhusal.StripePayments;
using System.Security.User;

// Test helpers. No Tests-TestLibraries dependency so this runs on a normal online sandbox.
// Invoices are posted straight to the customer through a journal line, so no sales or VAT setup is needed.
codeunit 58190 "SIP Test Library"
{
    procedure InitSetup()
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
        PaymentLink: Record "SIP Payment Link";
        StripeSetup: Record "SIP Stripe Setup";
        UserSetup: Record "User Setup";
        MockGateway: Codeunit "SIP Mock Gateway";
    begin
        // the sync handles every Open or Paid link in the company: start from none
        PaymentLink.DeleteAll();
        MockGateway.Reset();
        StripeSetup.InsertIfMissing();
        StripeSetup.Enabled := true;
        StripeSetup.Gateway := StripeSetup.Gateway::"SIP Mock";
        StripeSetup."Clearing Bank Account No." := CreateBankAccount();
        StripeSetup."Payment Nos." := CreateNoSeries();
        if StripeSetup."Success URL" = '' then
            StripeSetup."Success URL" := 'https://example.com/paid';
        StripeSetup.Modify();
        // local currency needs an ISO code for Stripe; journal lines without a template must post on the work date
        GeneralLedgerSetup.Get();
        if StrLen(GeneralLedgerSetup."LCY Code") <> 3 then
            GeneralLedgerSetup."LCY Code" := 'USD';
        GeneralLedgerSetup."Journal Templ. Name Mandatory" := false;
        GeneralLedgerSetup."Allow Posting From" := 0D;
        GeneralLedgerSetup."Allow Posting To" := 0D;
        GeneralLedgerSetup.Modify();
        if UserSetup.Get(UserId()) then begin
            UserSetup."Allow Posting From" := 0D;
            UserSetup."Allow Posting To" := 0D;
            UserSetup.Modify();
        end;
    end;

    procedure CreateCustomer(): Code[20]
    var
        Customer: Record Customer;
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        CustomerPostingGroup.SetFilter("Receivables Account", '<>%1', '');
        CustomerPostingGroup.FindFirst();
        Customer.Init();
        Customer."No." := NewCode('CU');
        Customer.Name := 'Stripe test customer';
        Customer."Customer Posting Group" := CustomerPostingGroup.Code;
        Customer.Insert(true);
        exit(Customer."No.");
    end;

    procedure SetCustomerEmail(CustomerNo: Code[20]; EmailAddresses: Text[80])
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        Customer."E-Mail" := EmailAddresses;
        Customer.Modify();
    end;

    // Gives the open invoice a payment discount that is still possible on the work date.
    procedure SetPaymentDiscount(InvoiceEntryNo: Integer; DiscountAmount: Decimal)
    var
        Customer: Record Customer;
        CustomerPostingGroup: Record "Customer Posting Group";
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        CustLedgerEntry.Get(InvoiceEntryNo);
        CustLedgerEntry."Pmt. Discount Date" := WorkDate();
        CustLedgerEntry."Pmt. Disc. Tolerance Date" := WorkDate();
        CustLedgerEntry."Original Pmt. Disc. Possible" := DiscountAmount;
        CustLedgerEntry."Orig. Pmt. Disc. Possible(LCY)" := DiscountAmount;
        CustLedgerEntry."Remaining Pmt. Disc. Possible" := DiscountAmount;
        CustLedgerEntry.Modify();
        // the granted discount is posted to the posting group's discount accounts
        Customer.Get(CustLedgerEntry."Customer No.");
        CustomerPostingGroup.Get(Customer."Customer Posting Group");
        if CustomerPostingGroup."Payment Disc. Debit Acc." = '' then
            CustomerPostingGroup."Payment Disc. Debit Acc." := CreateGLAccount();
        if CustomerPostingGroup."Payment Disc. Credit Acc." = '' then
            CustomerPostingGroup."Payment Disc. Credit Acc." := CreateGLAccount();
        CustomerPostingGroup.Modify();
    end;

    procedure SetCustomerBlocked(CustomerNo: Code[20]; IsBlocked: Boolean)
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        if IsBlocked then
            Customer.Blocked := Customer.Blocked::All
        else
            Customer.Blocked := Customer.Blocked::" ";
        Customer.Modify();
    end;

    // Returns the entry no. of the open invoice.
    procedure PostInvoice(CustomerNo: Code[20]; Amount: Decimal): Integer
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        DocumentNo: Code[20];
    begin
        DocumentNo := NewCode('IN');
        PostCustomerLine(Enum::"Gen. Journal Document Type"::Invoice, DocumentNo, CustomerNo, Amount, '');
        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document No.", DocumentNo);
        CustLedgerEntry.FindFirst();
        exit(CustLedgerEntry."Entry No.");
    end;

    // A payment that does not come from Stripe, applied to the invoice.
    procedure PostPaymentElsewhere(CustomerNo: Code[20]; InvoiceNo: Code[20]; Amount: Decimal)
    begin
        PostCustomerLine(Enum::"Gen. Journal Document Type"::Payment, NewCode('PM'), CustomerNo, -Amount, InvoiceNo);
    end;

    local procedure PostCustomerLine(DocumentType: Enum "Gen. Journal Document Type"; DocumentNo: Code[20]; CustomerNo: Code[20]; Amount: Decimal; AppliesToInvoiceNo: Code[20])
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
    begin
        GenJournalLine.Init();
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine."Document Type" := DocumentType;
        GenJournalLine."Document No." := DocumentNo;
        GenJournalLine."External Document No." := DocumentNo;
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Customer);
        GenJournalLine.Validate("Account No.", CustomerNo);
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"G/L Account");
        GenJournalLine.Validate("Bal. Account No.", CreateGLAccount());
        GenJournalLine.Validate(Amount, Amount);
        if AppliesToInvoiceNo <> '' then begin
            GenJournalLine."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type"::Invoice;
            GenJournalLine."Applies-to Doc. No." := AppliesToInvoiceNo;
        end;
        GenJnlPostLine.RunWithCheck(GenJournalLine);
    end;

    local procedure CreateBankAccount(): Code[20]
    var
        BankAccount: Record "Bank Account";
        BankAccountPostingGroup: Record "Bank Account Posting Group";
    begin
        BankAccountPostingGroup.SetFilter("G/L Account No.", '<>%1', '');
        BankAccountPostingGroup.FindFirst();
        BankAccount.Init();
        BankAccount."No." := NewCode('BA');
        BankAccount.Name := 'Stripe clearing';
        BankAccount."Bank Acc. Posting Group" := BankAccountPostingGroup.Code;
        BankAccount.Insert(true);
        exit(BankAccount."No.");
    end;

    // No posting groups on the account, so the invoice carries no VAT.
    local procedure CreateGLAccount(): Code[20]
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.Init();
        GLAccount."No." := NewCode('G');
        GLAccount.Name := 'Stripe test sales';
        GLAccount."Account Type" := GLAccount."Account Type"::Posting;
        GLAccount."Direct Posting" := true;
        GLAccount.Insert(true);
        exit(GLAccount."No.");
    end;

    local procedure CreateNoSeries(): Code[20]
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        NoSeries.Init();
        NoSeries.Code := NewCode('NS');
        NoSeries."Default Nos." := true;
        NoSeries.Insert(true);
        NoSeriesLine.Init();
        NoSeriesLine."Series Code" := NoSeries.Code;
        NoSeriesLine."Line No." := 10000;
        // unique per test, the runner does not roll back between methods
        NoSeriesLine."Starting No." := CopyStr(NoSeries.Code, 1, 8) + '-0001';
        NoSeriesLine."Ending No." := CopyStr(NoSeries.Code, 1, 8) + '-9999';
        NoSeriesLine.Insert(true);
        exit(NoSeries.Code);
    end;

    local procedure NewCode(Prefix: Code[2]): Code[20]
    begin
        exit(CopyStr(Prefix + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 10));
    end;
}
