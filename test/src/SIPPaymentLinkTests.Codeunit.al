namespace PrabinBhusal.StripePayments.Test;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Sales.History;
using Microsoft.Sales.Receivables;
using PrabinBhusal.StripePayments;
using System.TestLibraries.Utilities;

// A gateway error commits its log row inside the code under test. RequiredTestIsolation = Codeunit
// makes sure the runner rolls everything back, including the setup changes in SIP Test Library.
codeunit 58194 "SIP Payment Link Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "SIP Test Library";
        MockGateway: Codeunit "SIP Mock Gateway";
        PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";

    [Test]
    procedure CreateLinkStoresSessionAndSendsMinorUnits()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        GeneralLedgerSetup: Record "General Ledger Setup";
        PaymentLink: Record "SIP Payment Link";
        ExpectedMinorUnits: BigInteger;
    begin
        // [GIVEN] an open invoice of 123.45 in local currency
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 123.45));

        // [WHEN] a payment link is created for it
        PaymentLink := PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] an Open link with the session is stored, and the gateway was asked for 12345 minor units
        GeneralLedgerSetup.Get();
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Open, PaymentLink.Status, 'status');
        Assert.AreEqual(123.45, PaymentLink.Amount, 'amount');
        Assert.AreEqual(CustLedgerEntry."Document No.", PaymentLink."Invoice No.", 'invoice no.');
        Assert.AreEqual(CustLedgerEntry."Customer No.", PaymentLink."Customer No.", 'customer no.');
        Assert.AreEqual(LowerCase(GeneralLedgerSetup."LCY Code"), PaymentLink."Stripe Currency", 'Stripe currency');
        Assert.AreNotEqual('', PaymentLink."Session Id", 'session id');
        Assert.AreNotEqual('', PaymentLink.URL, 'url');
        Assert.AreNotEqual(0DT, PaymentLink."Expires At", 'expires at');
        ExpectedMinorUnits := 12345;
        Assert.AreEqual(ExpectedMinorUnits, PaymentLink."Amount (Minor Units)", 'minor units stored');
        Assert.AreEqual(ExpectedMinorUnits, MockGateway.LastAmountMinorUnits(), 'minor units sent');
        Assert.AreEqual(PaymentLink."Stripe Currency", MockGateway.LastCurrency(), 'currency sent');
        Assert.AreEqual(PaymentLink."Invoice No.", MockGateway.LastInvoiceNo(), 'invoice no. sent');
    end;

    [Test]
    procedure CreateFromPostedSalesInvoiceUsesItsLedgerEntry()
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a posted sales invoice header that points to an open invoice entry
        TestLibrary.InitSetup();
        SalesInvoiceHeader."Cust. Ledger Entry No." := TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 80);

        // [WHEN] the link is created from the posted invoice
        PaymentLink := PaymentLinkMgt.CreateForSalesInvoice(SalesInvoiceHeader);

        // [THEN] it is created for that entry
        Assert.AreEqual(SalesInvoiceHeader."Cust. Ledger Entry No.", PaymentLink."Cust. Ledger Entry No.", 'ledger entry');
        Assert.AreEqual(80, PaymentLink.Amount, 'amount');
    end;

    [Test]
    procedure SecondLinkForSameInvoiceIsRefused()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        // [GIVEN] an invoice that already has an open payment link
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 100));
        PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [WHEN] a second link is created
        asserterror PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] it is refused
        Assert.ExpectedError('already has a payment link');
    end;

    [Test]
    procedure ClosedInvoiceIsRefused()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        // [GIVEN] an invoice that is fully paid
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 100));
        TestLibrary.PostPaymentElsewhere(CustLedgerEntry."Customer No.", CustLedgerEntry."Document No.", 100);

        // [WHEN] a payment link is created
        asserterror PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] it is refused
        Assert.ExpectedError('nothing left to pay');
    end;

    [Test]
    procedure GatewayErrorOnCreateSavesNoLinkButLogsIt()
    var
        ActivityLog: Record "SIP Activity Log";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] an open invoice, and the gateway rejects the session
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 100));
        MockGateway.SetCreateFails(true);

        // [WHEN] a payment link is created
        asserterror PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] the gateway error is raised, no link is stored and the failed call is logged
        Assert.ExpectedError(MockGateway.MockErrorMessage());
        PaymentLink.SetRange("Invoice No.", CustLedgerEntry."Document No.");
        Assert.RecordIsEmpty(PaymentLink);
        ActivityLog.SetRange("Invoice No.", CustLedgerEntry."Document No.");
        ActivityLog.SetRange(Success, false);
        Assert.RecordIsNotEmpty(ActivityLog);
    end;

    [Test]
    procedure OnlyFirstEmailAddressIsSent()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        // [GIVEN] a customer with two e-mail addresses, as Business Central allows
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 100));
        TestLibrary.SetCustomerEmail(CustLedgerEntry."Customer No.", 'accounts@contoso.com; ap@contoso.com');

        // [WHEN] a payment link is created
        PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] the gateway gets only the first address, which Stripe accepts
        Assert.AreEqual('accounts@contoso.com', MockGateway.LastCustomerEmail(), 'customer e-mail sent');
    end;

    [Test]
    procedure ExpireUnknownSessionCancelsLink()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] an open link that the gateway no longer knows (404), for example after a key change
        TestLibrary.InitSetup();
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), 100));
        PaymentLink := PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);
        MockGateway.SetExpireFails(404);

        // [WHEN] the user expires the link
        PaymentLinkMgt.ExpireLink(PaymentLink);

        // [THEN] the link is Cancelled with the gateway error, so it no longer blocks the invoice
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Cancelled, PaymentLink.Status, 'status');
        Assert.AreEqual(MockGateway.MockErrorMessage(), PaymentLink."Last Error", 'last error');
    end;
}
