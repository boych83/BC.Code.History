namespace Microsoft.Bank.Deposit;

using Microsoft.Sales.Receivables;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.Dimension;
using Microsoft.Finance.GeneralLedger.Ledger;
using Microsoft.Purchases.Payables;
using Microsoft.Bank.BankAccount;
using Microsoft.Bank.Ledger;
using Microsoft.Finance.Analysis;
using System.Telemetry;
using Microsoft.Finance.Currency;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.GeneralLedger.Posting;
using Microsoft.Foundation.AuditCodes;
using System.Utilities;

codeunit 1690 "Bank Deposit-Post"
{
    Permissions = TableData "Cust. Ledger Entry" = r,
                  TableData "Vendor Ledger Entry" = r,
                  TableData "Bank Account Ledger Entry" = r,
                  TableData "Bank Acc. Comment Line" = rimd,
                  TableData "Bank Deposit Header" = rd,
                  TableData "Posted Bank Deposit Header" = rim,
                  TableData "Posted Bank Deposit Line" = rim;
    TableNo = "Bank Deposit Header";

    trigger OnRun()
    var
        GLEntry: Record "G/L Entry";
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalBatch: Record "Gen. Journal Batch";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        BankAccount: Record "Bank Account";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        GenJnlCheckLine: Codeunit "Gen. Jnl.-Check Line";
        UpdateAnalysisView: Codeunit "Update Analysis View";
        FeatureTelemetry: Codeunit "Feature Telemetry";
        TotalAmountLCY: Decimal;
        NextLineNo: Integer;
        CurrLineNo: Integer;
    begin
        FeatureTelemetry.LogUptake('0000IG4', 'Bank Deposit', Enum::"Feature Uptake Status"::Used);
        FeatureTelemetry.LogUsage('0000IG5', 'Bank Deposit', 'Bank deposit posted');
        OnBeforeBankDepositPost(Rec);

        // Check deposit
        Rec.TestField("Posting Date");
        Rec.TestField("Total Deposit Amount");
        Rec.TestField("Document Date");
        Rec.TestField("Bank Account No.");
        BankAccount.Get(Rec."Bank Account No.");
        BankAccount.TestField(Blocked, false);
        Rec.CalcFields("Total Deposit Lines");
        if Rec."Total Deposit Lines" <> Rec."Total Deposit Amount" then
            Error(TotalAmountsMustMatchErr, Rec.FieldCaption("Total Deposit Amount"), Rec.FieldCaption("Total Deposit Lines"));

        OnAfterCheckBankDeposit(Rec);

        if Rec."Currency Code" = '' then
            Currency.InitRoundingPrecision()
        else begin
            Currency.Get(Rec."Currency Code");
            Currency.TestField("Amount Rounding Precision");
        end;

        SourceCodeSetup.Get();

        NextLineNo := 0;
        TotalAmountLCY := 0;
        CurrLineNo := 0;
        ProgressDialog.Open(
          StrSubstNo(PostingDepositTxt, Rec."No.") +
          StatusTxt +
          BankDepositLineTxt +
          DividerTxt);

        ProgressDialog.Update(4, MovingToHistoryTxt);

        PostedBankDepositHeader.LockTable();
        PostedBankDepositLine.LockTable();
        Rec.LockTable();
        GenJournalLine.LockTable();

        InsertPostedBankDepositHeader(Rec);

        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", Rec."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", Rec."Journal Batch Name");
        if GenJournalLine.Find('-') then
            repeat
                NextLineNo := NextLineNo + 1;
                ProgressDialog.Update(2, NextLineNo);

                AssignVATDateIfEmpty(GenJournalLine);
                InsertPostedBankDepositLine(Rec, GenJournalLine, NextLineNo);

                if not Rec."Post as Lump Sum" then
                    AddBalancingAccount(GenJournalLine, Rec)
                else
                    GenJournalLine."Bal. Account No." := '';
                GenJnlCheckLine.RunCheck(GenJournalLine);
            until GenJournalLine.Next() = 0;

        CopyBankComments(Rec);

        // Post to General, and other, Ledgers
        ProgressDialog.Update(4, PostingLinesToLedgersTxt);
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", Rec."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", Rec."Journal Batch Name");
        if GenJournalLine.Find('-') then
            repeat
                CurrLineNo := CurrLineNo + 1;
                ProgressDialog.Update(2, CurrLineNo);
                ProgressDialog.Update(3, Round(CurrLineNo / NextLineNo * 10000, 1));
                if not Rec."Post as Lump Sum" then
                    AddBalancingAccount(GenJournalLine, Rec)
                else begin
                    TotalAmountLCY += GenJournalLine."Amount (LCY)";
                    GenJournalLine."Bal. Account No." := '';
                end;
                GenJournalLine."Source Code" := SourceCodeSetup."Bank Deposit";
                GenJournalLine."Source Type" := GenJournalLine."Source Type"::"Bank Account";
                GenJournalLine."Source No." := Rec."Bank Account No.";
                GenJournalLine."Source Currency Code" := Rec."Currency Code";
                GenJournalLine."Source Currency Amount" := GenJournalLine.Amount;
                OnBeforePostGenJournalLine(GenJournalLine, Rec, GenJnlPostLine);
                GenJnlPostLine.RunWithoutCheck(GenJournalLine);

                PostedBankDepositLine.Get(Rec."No.", CurrLineNo);
                case GenJournalLine."Account Type" of
                    GenJournalLine."Account Type"::"G/L Account",
                    GenJournalLine."Account Type"::"Bank Account":
                        begin
                            GLEntry.FindLast();
                            PostedBankDepositLine."Entry No." := GLEntry."Entry No.";
                            if (not Rec."Post as Lump Sum") and (GenJournalLine.Amount * GLEntry.Amount < 0) then
                                PostedBankDepositLine."Entry No." := PostedBankDepositLine."Entry No." - 1;
                        end;
                    GenJournalLine."Account Type"::Customer:
                        begin
                            CustLedgerEntry.FindLast();
                            PostedBankDepositLine."Entry No." := CustLedgerEntry."Entry No.";
                        end;
                    GenJournalLine."Account Type"::Vendor:
                        begin
                            VendorLedgerEntry.FindLast();
                            PostedBankDepositLine."Entry No." := VendorLedgerEntry."Entry No.";
                        end;
                end;
                if not Rec."Post as Lump Sum" then begin
                    BankAccountLedgerEntry.FindLast();
                    PostedBankDepositLine."Bank Account Ledger Entry No." := BankAccountLedgerEntry."Entry No.";
                    if (GenJournalLine."Account Type" = GenJournalLine."Account Type"::"Bank Account") and
                       (GenJournalLine.Amount * BankAccountLedgerEntry.Amount > 0)
                    then
                        PostedBankDepositLine."Entry No." := PostedBankDepositLine."Entry No." - 1;
                end;
                OnBeforePostedBankDepositLineModify(PostedBankDepositLine, GenJournalLine);
                PostedBankDepositLine.Modify();
            until GenJournalLine.Next() = 0;

        ProgressDialog.Update(4, PostingBankEntryTxt);
        if Rec."Post as Lump Sum" then begin
            PostBalancingEntry(Rec, TotalAmountLCY);
            OnRunOnAfterPostBalancingEntry(GenJournalLine);

            BankAccountLedgerEntry.FindLast();
            PostedBankDepositLine.Reset();
            PostedBankDepositLine.SetRange("Bank Deposit No.", Rec."No.");
            if PostedBankDepositLine.FindSet(true) then
                repeat
                    PostedBankDepositLine."Bank Account Ledger Entry No." := BankAccountLedgerEntry."Entry No.";
                    PostedBankDepositLine.Modify();
                until PostedBankDepositLine.Next() = 0;
        end;

        ProgressDialog.Update(4, RemovingBankDepositTxt);
        DeleteBankComments(Rec);

        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", Rec."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", Rec."Journal Batch Name");
        OnRunOnBeforeGenJournalLineDeleteAll(Rec, PostedBankDepositLine, GenJournalLine);
        GenJournalLine.DeleteAll();
        GenJournalTemplate.Get(Rec."Journal Template Name");
        GenJournalBatch.Get(Rec."Journal Template Name", Rec."Journal Batch Name");
        if GenJournalTemplate."Increment Batch Name" then
            if IncStr(Rec."Journal Batch Name") <> '' then begin
                GenJournalBatch.Get(Rec."Journal Template Name", Rec."Journal Batch Name");
                GenJournalBatch.Delete();
                GenJournalBatch.Name := IncStr(Rec."Journal Batch Name");
                if GenJournalBatch.Insert() then;
            end;

        Rec.Delete();
        Commit();

        UpdateAnalysisView.UpdateAll(0, true);

        OnAfterBankDepositPost(Rec, PostedBankDepositHeader);

        Page.Run(Page::"Posted Bank Deposit", PostedBankDepositHeader);
    end;

    internal procedure CombineDimensionSets(var BankDepositHeader: Record "Bank Deposit Header"; var GenJournalLine: Record "Gen. Journal Line"): Integer
    var
        DefaultDimensionPriority: Record "Default Dimension Priority";
        LocalSourceCodeSetup: Record "Source Code Setup";
        DimensionManagement: Codeunit DimensionManagement;
        DimensionSetIDArr: array[10] of Integer;
        DefaultDimensionPriorityHeader: Integer;
        DefaultDimensionPriorityLine: Integer;
    begin
        if LocalSourceCodeSetup.Get() then
            if LocalSourceCodeSetup."Bank Deposit" <> '' then
                if DefaultDimensionPriority.Get(LocalSourceCodeSetup."Bank Deposit", Database::"Bank Deposit Header") then begin
                    DefaultDimensionPriorityHeader := DefaultDimensionPriority.Priority;
                    if DefaultDimensionPriority.Get(LocalSourceCodeSetup."Bank Deposit", Database::"Gen. Journal Line") then
                        DefaultDimensionPriorityLine := DefaultDimensionPriority.Priority;
                end;
        if DefaultDimensionPriorityHeader < DefaultDimensionPriorityLine then begin
            DimensionSetIDArr[1] := GenJournalLine."Dimension Set ID";
            DimensionSetIDArr[2] := BankDepositHeader."Dimension Set ID";
        end else begin
            DimensionSetIDArr[1] := BankDepositHeader."Dimension Set ID";
            DimensionSetIDArr[2] := GenJournalLine."Dimension Set ID";
        end;

        exit(DimensionManagement.GetCombinedDimensionSetID(DimensionSetIDArr, GenJournalLine."Shortcut Dimension 1 Code", GenJournalLine."Shortcut Dimension 2 Code"));
    end;

    internal procedure CombineDimensionSetsHeaderPriority(var BankDepositHeader: Record "Bank Deposit Header"; var GenJournalLine: Record "Gen. Journal Line"): Integer
    var
        DimensionManagement: Codeunit DimensionManagement;
        DimensionSetIDArr: array[10] of Integer;
    begin
        DimensionSetIDArr[1] := GenJournalLine."Dimension Set ID";
        DimensionSetIDArr[2] := BankDepositHeader."Dimension Set ID";
        exit(DimensionManagement.GetCombinedDimensionSetID(DimensionSetIDArr, GenJournalLine."Shortcut Dimension 1 Code", GenJournalLine."Shortcut Dimension 2 Code"));
    end;

    var
        PostedBankDepositHeader: Record "Posted Bank Deposit Header";
        PostedBankDepositLine: Record "Posted Bank Deposit Line";
        SourceCodeSetup: Record "Source Code Setup";
        Currency: Record Currency;
        GLSetup: Record "General Ledger Setup";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        ProgressDialog: Dialog;
        TotalAmountsMustMatchErr: Label 'The %1 must match the %2.', Comment = '%1 - total amount, %2 - total amount on the lines';
        PostingDepositTxt: Label 'Posting Bank Deposit No. %1...\\', Comment = '%1 - bank deposit number';
        BankDepositLineTxt: Label 'Bank Deposit Line  #2########\', Comment = '#2- a number (progress indicator)';
        DividerTxt: Label '@3@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', Locked = true;
        StatusTxt: Label 'Status        #4###################\', Comment = '#4 - a number (progress indicator)';
        MovingToHistoryTxt: Label 'Moving Bank Deposit to History';
        PostingLinesToLedgersTxt: Label 'Posting Lines to Ledgers';
        PostingBankEntryTxt: Label 'Posting Bank Account Ledger Entry';
        RemovingBankDepositTxt: Label 'Removing Bank Deposit';

    local procedure AddBalancingAccount(var GenJournalLine: Record "Gen. Journal Line"; BankDepositHeader: Record "Bank Deposit Header")
    begin
        GenJournalLine."Bal. Account Type" := GenJournalLine."Bal. Account Type"::"Bank Account";
        GenJournalLine."Bal. Account No." := BankDepositHeader."Bank Account No.";
        GenJournalLine."Balance (LCY)" := 0;
    end;

    local procedure CopyBankComments(BankDepositHeader: Record "Bank Deposit Header")
    var
        BankAccCommentLine: Record "Bank Acc. Comment Line";
        BankAccCommentLine2: Record "Bank Acc. Comment Line";
    begin
        BankAccCommentLine.Reset();
        BankAccCommentLine.SetRange("Table Name", BankAccCommentLine."Table Name"::"Bank Deposit Header");
        BankAccCommentLine.SetRange("Bank Account No.", BankDepositHeader."Bank Account No.");
        BankAccCommentLine.SetRange("No.", BankDepositHeader."No.");
        if BankAccCommentLine.FindSet() then
            repeat
                BankAccCommentLine2 := BankAccCommentLine;
                BankAccCommentLine2."Table Name" := BankAccCommentLine2."Table Name"::"Posted Bank Deposit Header";
                BankAccCommentLine2.Insert();
            until BankAccCommentLine.Next() = 0;
    end;

    local procedure DeleteBankComments(BankDepositHeader: Record "Bank Deposit Header")
    var
        BankAccCommentLine: Record "Bank Acc. Comment Line";
    begin
        BankAccCommentLine.Reset();
        BankAccCommentLine.SetRange("Table Name", BankAccCommentLine."Table Name"::"Bank Deposit Header");
        BankAccCommentLine.SetRange("Bank Account No.", BankDepositHeader."Bank Account No.");
        BankAccCommentLine.SetRange("No.", BankDepositHeader."No.");
        BankAccCommentLine.DeleteAll();
    end;

    local procedure InsertPostedBankDepositHeader(var BankDepositHeader: Record "Bank Deposit Header")
    var
        RecordLinkManagement: Codeunit "Record Link Management";
    begin
        PostedBankDepositHeader.Reset();
        PostedBankDepositHeader.TransferFields(BankDepositHeader, true);
        PostedBankDepositHeader."No. Printed" := 0;
        OnBeforePostedBankDepositHeaderInsert(PostedBankDepositHeader, BankDepositHeader);
        PostedBankDepositHeader.Insert();
        RecordLinkManagement.CopyLinks(BankDepositHeader, PostedBankDepositHeader);
    end;

    local procedure InsertPostedBankDepositLine(BankDepositHeader: Record "Bank Deposit Header"; GenJournalLine: Record "Gen. Journal Line"; LineNo: Integer)
    begin
        PostedBankDepositLine."Bank Deposit No." := BankDepositHeader."No.";
        PostedBankDepositLine."Line No." := LineNo;
        PostedBankDepositLine."Account Type" := GenJournalLine."Account Type";
        PostedBankDepositLine."Account No." := GenJournalLine."Account No.";
        PostedBankDepositLine."Document Date" := GenJournalLine."Document Date";
        PostedBankDepositLine."Document Type" := GenJournalLine."Document Type";
        PostedBankDepositLine."Document No." := GenJournalLine."Document No.";
        PostedBankDepositLine.Description := GenJournalLine.Description;
        PostedBankDepositLine."Currency Code" := GenJournalLine."Currency Code";
        PostedBankDepositLine.Amount := -GenJournalLine.Amount;
        PostedBankDepositLine."Posting Group" := GenJournalLine."Posting Group";
        PostedBankDepositLine."Shortcut Dimension 1 Code" := GenJournalLine."Shortcut Dimension 1 Code";
        PostedBankDepositLine."Shortcut Dimension 2 Code" := GenJournalLine."Shortcut Dimension 2 Code";
        PostedBankDepositLine."Dimension Set ID" := GenJournalLine."Dimension Set ID";
        PostedBankDepositLine."Posting Date" := BankDepositHeader."Posting Date";
        OnBeforePostedBankDepositLineInsert(PostedBankDepositLine, GenJournalLine);
        PostedBankDepositLine.Insert();
    end;

    local procedure PostBalancingEntry(BankDepositHeader: Record "Bank Deposit Header"; TotalAmountLCY: Decimal)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.Init();
        GenJournalLine."Account Type" := GenJournalLine."Account Type"::"Bank Account";
        GenJournalLine."Account No." := BankDepositHeader."Bank Account No.";
        GenJournalLine."Posting Date" := BankDepositHeader."Posting Date";
        GenJournalLine."VAT Reporting Date" := GLSetup.GetVATDate(BankDepositHeader."Posting Date", BankDepositHeader."Document Date");
        GenJournalLine."Document No." := BankDepositHeader."No.";
        GenJournalLine."Currency Code" := BankDepositHeader."Currency Code";
        GenJournalLine."Currency Factor" := BankDepositHeader."Currency Factor";
        GenJournalLine."Posting Group" := BankDepositHeader."Bank Acc. Posting Group";
        GenJournalLine."Shortcut Dimension 1 Code" := BankDepositHeader."Shortcut Dimension 1 Code";
        GenJournalLine."Shortcut Dimension 2 Code" := BankDepositHeader."Shortcut Dimension 2 Code";
        GenJournalLine."Dimension Set ID" := BankDepositHeader."Dimension Set ID";
        GenJournalLine."Source Code" := SourceCodeSetup."Bank Deposit";
        GenJournalLine."Reason Code" := BankDepositHeader."Reason Code";
        GenJournalLine."Document Date" := BankDepositHeader."Document Date";
        GenJournalLine."External Document No." := BankDepositHeader."No.";
        GenJournalLine."Source Type" := GenJournalLine."Source Type"::"Bank Account";
        GenJournalLine."Source No." := BankDepositHeader."Bank Account No.";
        GenJournalLine."Source Currency Code" := BankDepositHeader."Currency Code";
        GenJournalLine.Description := BankDepositHeader."Posting Description";
        GenJournalLine.Amount := BankDepositHeader."Total Deposit Amount";
        GenJournalLine."Source Currency Amount" := BankDepositHeader."Total Deposit Amount";
        GenJournalLine."Journal Template Name" := BankDepositHeader."Journal Template Name";
        GenJournalLine."Journal Batch Name" := BankDepositHeader."Journal Batch Name";
        GenJournalLine.Validate(GenJournalLine.Amount);
        GenJournalLine."Amount (LCY)" := -TotalAmountLCY;
        OnBeforePostBalancingEntry(GenJournalLine, BankDepositHeader, GenJnlPostLine);
        GenJnlPostLine.RunWithCheck(GenJournalLine);
        OnAfterPostBalancingEntry(GenJournalLine);
    end;

    local procedure AssignVATDateIfEmpty(var GenJnlLine: Record "Gen. Journal Line")
    begin
        if GenJnlLine."VAT Reporting Date" = 0D then begin
            GLSetup.Get();
            if (GenJnlLine."Document Date" = 0D) and (GLSetup."VAT Reporting Date" = GLSetup."VAT Reporting Date"::"Document Date") then
                GenJnlLine."VAT Reporting Date" := GenJnlLine."Posting Date"
            else
                GenJnlLine."VAT Reporting Date" := GLSetup.GetVATDate(GenJnlLine."Posting Date", GenJnlLine."Document Date");
            GenJnlLine.Modify();
        end;
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCheckBankDeposit(BankDepositHeader: Record "Bank Deposit Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterBankDepositPost(BankDepositHeader: Record "Bank Deposit Header"; var PostedBankDepositHeader: Record "Posted Bank Deposit Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostBalancingEntry(var GenJournalLine: Record "Gen. Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeBankDepositPost(var BankDepositHeader: Record "Bank Deposit Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostBalancingEntry(var GenJournalLine: Record "Gen. Journal Line"; BankDepositHeader: Record "Bank Deposit Header"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostGenJournalLine(var GenJournalLine: Record "Gen. Journal Line"; BankDepositHeader: Record "Bank Deposit Header"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostedBankDepositHeaderInsert(var PostedBankDepositHeader: Record "Posted Bank Deposit Header"; BankDepositHeader: Record "Bank Deposit Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostedBankDepositLineInsert(var PostedBankDepositLine: Record "Posted Bank Deposit Line"; GenJournalLine: Record "Gen. Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostedBankDepositLineModify(var PostedBankDepositLine: Record "Posted Bank Deposit Line"; GenJournalLine: Record "Gen. Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRunOnAfterPostBalancingEntry(var GenJournalLine: Record "Gen. Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRunOnBeforeGenJournalLineDeleteAll(var BankDepositHeader: Record "Bank Deposit Header"; var PostedBankDepositLine: Record "Posted Bank Deposit Line"; var GenJournalLine: Record "Gen. Journal Line")
    begin
    end;
}



