namespace PrabinBhusal.StripePayments;

using System.Threading;

// Job queue entry point: checks every Open link with Stripe and posts the paid ones.
// Each link runs in its own transaction, so one failure never stops the others.
codeunit 58153 "SIP Payment Sync"
{
    TableNo = "Job Queue Entry";

    trigger OnRun()
    begin
        SyncOpenLinks();
    end;

    var
        CheckLinkTok: Label 'Check Link', Locked = true;
        PostPaymentTok: Label 'Post Payment', Locked = true;
        PostedAsTxt: Label 'Posted as payment %1', Comment = '%1 = payment document no.';
        JobDescriptionTxt: Label 'Check Stripe payment links and post payments';

    // Also picks up Paid links, in case an earlier run stopped before posting them.
    procedure SyncOpenLinks(): Integer
    var
        PaymentLink: Record "SIP Payment Link";
        EntryNos: List of [Integer];
        EntryNo: Integer;
    begin
        PaymentLink.SetCurrentKey(Status);
        PaymentLink.SetFilter(Status, '%1|%2', PaymentLink.Status::Open, PaymentLink.Status::Paid);
        PaymentLink.SetLoadFields("Entry No.");
        if PaymentLink.FindSet() then
            repeat
                EntryNos.Add(PaymentLink."Entry No.");
            until PaymentLink.Next() = 0;

        foreach EntryNo in EntryNos do
            SyncLink(EntryNo);
        exit(EntryNos.Count());
    end;

    // Commit first so a posting error cannot roll back the Paid status. Failed links keep the error for Retry Posting.
    internal procedure PostPaidLink(var PaymentLink: Record "SIP Payment Link")
    var
        ActivityLogger: Codeunit "SIP Activity Logger";
        EntryNo: Integer;
        ErrorText: Text;
        ErrorCallStack: Text;
    begin
        EntryNo := PaymentLink."Entry No.";
        Commit();
        if Codeunit.Run(Codeunit::"SIP Post Payment", PaymentLink) then begin
            PaymentLink.Get(EntryNo);
            ActivityLogger.Log(PostPaymentTok, PaymentLink."Invoice No.", PaymentLink."Session Id", 0, 0, true, StrSubstNo(PostedAsTxt, PaymentLink."Payment Document No."), '');
            exit;
        end;

        ErrorText := GetLastErrorText();
        ErrorCallStack := GetLastErrorCallStack();
        PaymentLink.ReadIsolation := IsolationLevel::UpdLock;
        PaymentLink.Get(EntryNo);
        // only a Paid link turns Failed; another session may have posted it meanwhile
        if PaymentLink.Status = PaymentLink.Status::Paid then begin
            PaymentLink.Status := PaymentLink.Status::Failed;
            PaymentLink."Last Error" := CopyStr(ErrorText, 1, MaxStrLen(PaymentLink."Last Error"));
            PaymentLink.Modify(true);
        end;
        ActivityLogger.Log(PostPaymentTok, PaymentLink."Invoice No.", PaymentLink."Session Id", 0, 0, false, ErrorText, ErrorCallStack);
    end;

    // One recurring entry, every 5 minutes. Returns false when it already exists.
    procedure ScheduleJobQueue(): Boolean
    var
        JobQueueEntry: Record "Job Queue Entry";
    begin
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Codeunit);
        JobQueueEntry.SetRange("Object ID to Run", Codeunit::"SIP Payment Sync");
        if not JobQueueEntry.IsEmpty() then
            exit(false);

        JobQueueEntry.Init();
        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := Codeunit::"SIP Payment Sync";
        JobQueueEntry.Description := JobDescriptionTxt;
        JobQueueEntry.InitRecurringJob(5);
        Codeunit.Run(Codeunit::"Job Queue - Enqueue", JobQueueEntry);
        exit(true);
    end;

    local procedure SyncLink(EntryNo: Integer)
    var
        PaymentLink: Record "SIP Payment Link";
    begin
        PaymentLink.Get(EntryNo);
        if PaymentLink.Status = PaymentLink.Status::Open then begin
            Commit();
            if not Codeunit.Run(Codeunit::"SIP Check Payment Link", PaymentLink) then begin
                SaveCheckError(EntryNo);
                exit;
            end;
            PaymentLink.Get(EntryNo);
        end;
        if PaymentLink.Status = PaymentLink.Status::Paid then
            PostPaidLink(PaymentLink);
    end;

    // An unexpected error while checking: the link stays Open and is tried again next run.
    local procedure SaveCheckError(EntryNo: Integer)
    var
        PaymentLink: Record "SIP Payment Link";
        ActivityLogger: Codeunit "SIP Activity Logger";
        ErrorText: Text;
        ErrorCallStack: Text;
    begin
        ErrorText := GetLastErrorText();
        ErrorCallStack := GetLastErrorCallStack();
        PaymentLink.ReadIsolation := IsolationLevel::UpdLock;
        PaymentLink.Get(EntryNo);
        PaymentLink."Last Error" := CopyStr(ErrorText, 1, MaxStrLen(PaymentLink."Last Error"));
        PaymentLink."Synced At" := CurrentDateTime();
        PaymentLink.Modify(true);
        ActivityLogger.Log(CheckLinkTok, PaymentLink."Invoice No.", PaymentLink."Session Id", 0, 0, false, ErrorText, ErrorCallStack);
    end;
}
