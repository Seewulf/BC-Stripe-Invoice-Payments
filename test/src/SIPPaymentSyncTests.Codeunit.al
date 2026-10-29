namespace PrabinBhusal.StripePayments.Test;

using Microsoft.Sales.Receivables;
using PrabinBhusal.StripePayments;
using System.TestLibraries.Utilities;

// The sync commits once per link. RequiredTestIsolation = Codeunit makes sure the runner
// rolls everything back, including the setup changes in SIP Test Library.
codeunit 58195 "SIP Payment Sync Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "SIP Test Library";
        MockGateway: Codeunit "SIP Mock Gateway";
        PaymentLinkMgt: Codeunit "SIP Payment Link Mgt";
        PaymentSync: Codeunit "SIP Payment Sync";

    [Test]
    procedure PaidSessionPostsAppliedPayment()
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] an open invoice of 250 with a payment link, and Stripe reports the session paid
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 250);
        MockGateway.SetSessionOutcome('complete', 'paid');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the payment is posted with the payment intent as external document no. and closes the invoice
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Posted, PaymentLink.Status, 'status');
        Assert.AreEqual(250, PaymentLink."Amount Paid", 'amount paid');
        Assert.IsFalse(PaymentLink."Needs Review", 'needs review');
        Assert.AreNotEqual('', PaymentLink."Payment Intent Id", 'payment intent');
        FindStripePayment(PaymentEntry, PaymentLink);
        Assert.AreEqual(PaymentLink."Payment Document No.", PaymentEntry."Document No.", 'payment document no.');
        Assert.AreEqual(UpperCase(PaymentLink."Payment Intent Id"), PaymentEntry."External Document No.", 'external document no.');
        InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.");
        Assert.IsFalse(InvoiceEntry.Open, 'invoice must be closed');
    end;

    [Test]
    procedure SyncTwicePostsOnce()
    var
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a paid link that has been synced and posted
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 75);
        MockGateway.SetSessionOutcome('complete', 'paid');
        PaymentSync.SyncOpenLinks();

        // [WHEN] the sync runs again, and once more after the link fell back to Paid as if a run had stopped before updating it
        PaymentSync.SyncOpenLinks();
        PaymentLink.Get(PaymentLink."Entry No.");
        PaymentLink.Status := PaymentLink.Status::Paid;
        PaymentLink.Modify();
        PaymentSync.SyncOpenLinks();

        // [THEN] there is still exactly one payment and the link is Posted
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        Assert.RecordCount(PaymentEntry, 1);
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Posted, PaymentLink.Status, 'status');
    end;

    [Test]
    procedure ExpiredSessionMarksLinkExpired()
    var
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link whose session has expired at Stripe
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 60);
        MockGateway.SetSessionOutcome('expired', 'unpaid');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the link is Expired and nothing is posted
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Expired, PaymentLink.Status, 'status');
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        Assert.RecordIsEmpty(PaymentEntry);
    end;

    [Test]
    procedure PostingErrorDoesNotStopOtherLinksAndCanBeRetried()
    var
        LinkA: Record "SIP Payment Link";
        LinkB: Record "SIP Payment Link";
    begin
        // [GIVEN] two paid links; customer A is blocked, customer B is fine
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(LinkA, 100);
        CreateLinkForNewInvoice(LinkB, 200);
        TestLibrary.SetCustomerBlocked(LinkA."Customer No.", true);
        MockGateway.SetSessionOutcome('complete', 'paid');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] A is Failed with the posting error, B is still Posted
        LinkA.Get(LinkA."Entry No.");
        LinkB.Get(LinkB."Entry No.");
        Assert.AreEqual(LinkA.Status::Failed, LinkA.Status, 'status A');
        Assert.AreNotEqual('', LinkA."Last Error", 'error A');
        Assert.AreEqual(LinkB.Status::Posted, LinkB.Status, 'status B');

        // [WHEN] customer A is unblocked and the posting is retried
        TestLibrary.SetCustomerBlocked(LinkA."Customer No.", false);
        Assert.IsTrue(PaymentLinkMgt.RetryPosting(LinkA), 'retry');

        // [THEN] A is Posted
        LinkA.Get(LinkA."Entry No.");
        Assert.AreEqual(LinkA.Status::Posted, LinkA.Status, 'status A after retry');
        Assert.AreEqual('', LinkA."Last Error", 'error A after retry');
    end;

    [Test]
    procedure InvoicePaidElsewherePostsUnappliedForReview()
    var
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a payment link; the invoice is paid another way, and the customer pays on Stripe before the sync can close the page
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 120);
        TestLibrary.PostPaymentElsewhere(PaymentLink."Customer No.", PaymentLink."Invoice No.", 120);
        MockGateway.SetSessionOutcome('complete', 'paid');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the Stripe money is posted unapplied and the link is flagged for review
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Posted, PaymentLink.Status, 'status');
        Assert.IsTrue(PaymentLink."Needs Review", 'needs review');
        FindStripePayment(PaymentEntry, PaymentLink);
        Assert.IsTrue(PaymentEntry.Open, 'payment must stay open');
    end;

    [Test]
    procedure GatewayErrorOnSyncKeepsLinkOpen()
    var
        ActivityLog: Record "SIP Activity Log";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] an open link, and Stripe cannot be reached
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 90);
        MockGateway.SetGetFails(true);

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the link stays Open with the error, and the failed call is logged
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Open, PaymentLink.Status, 'status');
        Assert.AreEqual(MockGateway.MockErrorMessage(), PaymentLink."Last Error", 'last error');
        ActivityLog.SetRange("Invoice No.", PaymentLink."Invoice No.");
        ActivityLog.SetRange(Success, false);
        Assert.RecordIsNotEmpty(ActivityLog);
    end;

    [Test]
    procedure PaymentDiscountLeavesPaymentOpenForReview()
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link for an invoice of 100 that still has a payment discount of 2, and Stripe collects the full 100
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        TestLibrary.SetPaymentDiscount(PaymentLink."Cust. Ledger Entry No.", 2);
        MockGateway.SetSessionOutcome('complete', 'paid');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the discount closes the invoice, the extra 2 stays open on the payment and the link needs review
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Posted, PaymentLink.Status, 'status');
        Assert.IsTrue(PaymentLink."Needs Review", 'needs review');
        InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.");
        Assert.IsFalse(InvoiceEntry.Open, 'invoice must be closed');
        FindStripePayment(PaymentEntry, PaymentLink);
        Assert.IsTrue(PaymentEntry.Open, 'payment must stay open');
    end;

    [Test]
    procedure PartialPaymentIsPostedAndFlagged()
    var
        InvoiceEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link for 100, and Stripe reports 9000 minor units paid
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        MockGateway.SetSessionOutcome('complete', 'paid');
        MockGateway.SetPaidAmountOverride(9000);

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] 90 is posted against the invoice, 10 stays open and the link needs review
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Posted, PaymentLink.Status, 'status');
        Assert.AreEqual(90, PaymentLink."Amount Paid", 'amount paid');
        Assert.IsTrue(PaymentLink."Needs Review", 'needs review');
        InvoiceEntry.SetAutoCalcFields("Remaining Amount");
        InvoiceEntry.Get(PaymentLink."Cust. Ledger Entry No.");
        Assert.IsTrue(InvoiceEntry.Open, 'invoice must stay open');
        Assert.AreEqual(10, InvoiceEntry."Remaining Amount", 'remaining amount');
    end;

    [Test]
    procedure PaymentInOtherCurrencyIsNotPosted()
    var
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
        Reason: Text;
    begin
        // [GIVEN] a link, and Stripe reports the payment in another currency than the link asked for
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        MockGateway.SetSessionOutcome('complete', 'paid');
        MockGateway.SetPaidCurrencyOverride('xts');

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] nothing is posted, and the link is Failed with the reason
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Failed, PaymentLink.Status, 'status');
        Assert.AreNotEqual('', PaymentLink."Last Error", 'last error');
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        Assert.RecordIsEmpty(PaymentEntry);

        // [THEN] Retry Posting is refused and the currency reason is kept
        Reason := PaymentLink."Last Error";
        asserterror PaymentLinkMgt.RetryPosting(PaymentLink);
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Failed, PaymentLink.Status, 'status after retry');
        Assert.AreEqual(Reason, PaymentLink."Last Error", 'last error after retry');
    end;

    [Test]
    procedure InvoiceSettledInBCClosesOpenPaymentPage()
    var
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link whose Stripe page is still open, and the invoice is paid another way
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 110);
        TestLibrary.PostPaymentElsewhere(PaymentLink."Customer No.", PaymentLink."Invoice No.", 110);

        // [WHEN] the sync runs
        PaymentSync.SyncOpenLinks();

        // [THEN] the Stripe page is expired and the link is Cancelled with the reason
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Cancelled, PaymentLink.Status, 'status');
        Assert.AreNotEqual('', PaymentLink."Last Error", 'reason');
        Assert.AreEqual(PaymentLink."Session Id", MockGateway.LastExpiredSessionId(), 'session expired at the gateway');
    end;

    [Test]
    procedure FailedLinkBlocksNewLink()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link that was paid but could not be posted, and the customer is unblocked again
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        TestLibrary.SetCustomerBlocked(PaymentLink."Customer No.", true);
        MockGateway.SetSessionOutcome('complete', 'paid');
        PaymentSync.SyncOpenLinks();
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Failed, PaymentLink.Status, 'status');
        TestLibrary.SetCustomerBlocked(PaymentLink."Customer No.", false);

        // [WHEN] a new link is created for the same invoice
        CustLedgerEntry.Get(PaymentLink."Cust. Ledger Entry No.");
        asserterror PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] it is refused, so the customer cannot pay twice
        Assert.ExpectedError('already has a payment link');
    end;

    [Test]
    procedure ExpiredLinkAllowsNewLink()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        NewLink: Record "SIP Payment Link";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] a link whose Stripe session has expired
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        MockGateway.SetSessionOutcome('expired', 'unpaid');
        PaymentSync.SyncOpenLinks();

        // [WHEN] a new link is created for the same invoice
        CustLedgerEntry.Get(PaymentLink."Cust. Ledger Entry No.");
        NewLink := PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);

        // [THEN] a new Open link is created
        Assert.AreNotEqual(PaymentLink."Entry No.", NewLink."Entry No.", 'new link');
        Assert.AreEqual(NewLink.Status::Open, NewLink.Status, 'status');
    end;

    [Test]
    procedure ExpiredLinkIsLeftAloneBySync()
    var
        PaymentEntry: Record "Cust. Ledger Entry";
        PaymentLink: Record "SIP Payment Link";
    begin
        // [GIVEN] an open link that the user expires
        TestLibrary.InitSetup();
        CreateLinkForNewInvoice(PaymentLink, 100);
        PaymentLinkMgt.ExpireLink(PaymentLink);
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Cancelled, PaymentLink.Status, 'status after expire');
        Assert.AreNotEqual(0DT, PaymentLink."Synced At", 'synced at');

        // [WHEN] the gateway later reports the session paid and the sync runs
        MockGateway.SetSessionOutcome('complete', 'paid');
        PaymentSync.SyncOpenLinks();

        // [THEN] the link stays Cancelled and nothing is posted
        PaymentLink.Get(PaymentLink."Entry No.");
        Assert.AreEqual(PaymentLink.Status::Cancelled, PaymentLink.Status, 'status after sync');
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        Assert.RecordIsEmpty(PaymentEntry);
    end;

    local procedure CreateLinkForNewInvoice(var PaymentLink: Record "SIP Payment Link"; Amount: Decimal)
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        CustLedgerEntry.Get(TestLibrary.PostInvoice(TestLibrary.CreateCustomer(), Amount));
        PaymentLink := PaymentLinkMgt.CreateForCustLedgerEntry(CustLedgerEntry);
    end;

    local procedure FindStripePayment(var PaymentEntry: Record "Cust. Ledger Entry"; PaymentLink: Record "SIP Payment Link")
    begin
        PaymentEntry.SetRange("Customer No.", PaymentLink."Customer No.");
        PaymentEntry.SetRange("Document Type", PaymentEntry."Document Type"::Payment);
        PaymentEntry.SetRange("External Document No.", CopyStr(PaymentLink."Payment Intent Id", 1, MaxStrLen(PaymentEntry."External Document No.")));
        Assert.RecordCount(PaymentEntry, 1);
        PaymentEntry.FindFirst();
    end;
}
