namespace PrabinBhusal.StripePayments;

page 58152 "SIP Activity Log"
{
    Caption = 'Stripe Activity Log';
    PageType = List;
    SourceTable = "SIP Activity Log";
    SourceTableView = sorting("Entry No.") order(descending);
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Entries)
            {
                field("Entry No."; Rec."Entry No.") { }
                field(CreatedAt; Rec.SystemCreatedAt)
                {
                    Caption = 'Created At';
                    ToolTip = 'Specifies when the entry was written.';
                }
                field(Operation; Rec.Operation) { }
                field("Invoice No."; Rec."Invoice No.") { }
                field(Success; Rec.Success) { }
                field("HTTP Status Code"; Rec."HTTP Status Code") { }
                field("Duration (ms)"; Rec."Duration (ms)") { }
                field(Message; Rec.Message) { }
                field("Session Id"; Rec."Session Id") { Visible = false; }
                field("Error Call Stack"; Rec."Error Call Stack") { Visible = false; }
            }
        }
    }
}
