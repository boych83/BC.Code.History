namespace Microsoft.Finance.Dimension;

using Microsoft.Finance.GeneralLedger.Setup;

query 257 "Dimension Sets"
{
    Caption = 'Dimension Sets';

    elements
    {
        dataitem(General_Ledger_Setup; "General Ledger Setup")
        {
            dataitem(Dimension_Set_Entry; "Dimension Set Entry")
            {
                SqlJoinType = CrossJoin;
                column(Dimension_Set_ID; "Dimension Set ID")
                {
                }
                column(Value_Count)
                {
                    Method = Count;
                }
                dataitem(Dimension_1; "Dimension Set Entry")
                {
                    DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 1 Code";
                    column(Dimension_1_Value_Code; "Dimension Value Code")
                    {
                    }
                    column(Dimension_1_Value_Name; "Dimension Value Name")
                    {
                    }
                    dataitem(Dimension_2; "Dimension Set Entry")
                    {
                        DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 2 Code";
                        column(Dimension_2_Value_Code; "Dimension Value Code")
                        {
                        }
                        column(Dimension_2_Value_Name; "Dimension Value Name")
                        {
                        }
                        dataitem(Dimension_3; "Dimension Set Entry")
                        {
                            DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 3 Code";
                            column(Dimension_3_Value_Code; "Dimension Value Code")
                            {
                            }
                            column(Dimension_3_Value_Name; "Dimension Value Name")
                            {
                            }
                            dataitem(Dimension_4; "Dimension Set Entry")
                            {
                                DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 4 Code";
                                column(Dimension_4_Value_Code; "Dimension Value Code")
                                {
                                }
                                column(Dimension_4_Value_Name; "Dimension Value Name")
                                {
                                }
                                dataitem(Dimension_5; "Dimension Set Entry")
                                {
                                    DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 5 Code";
                                    column(Dimension_5_Value_Code; "Dimension Value Code")
                                    {
                                    }
                                    column(Dimension_5_Value_Name; "Dimension Value Name")
                                    {
                                    }
                                    dataitem(Dimension_6; "Dimension Set Entry")
                                    {
                                        DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 6 Code";
                                        column(Dimension_6_Value_Code; "Dimension Value Code")
                                        {
                                        }
                                        column(Dimension_6_Value_Name; "Dimension Value Name")
                                        {
                                        }
                                        dataitem(Dimension_7; "Dimension Set Entry")
                                        {
                                            DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 7 Code";
                                            column(Dimension_7_Value_Code; "Dimension Value Code")
                                            {
                                            }
                                            column(Dimension_7_Value_Name; "Dimension Value Name")
                                            {
                                            }
                                            dataitem(Dimension_8; "Dimension Set Entry")
                                            {
                                                DataItemLink = "Dimension Set ID" = Dimension_Set_Entry."Dimension Set ID", "Dimension Code" = General_Ledger_Setup."Shortcut Dimension 8 Code";
                                                column(Dimension_8_Value_Code; "Dimension Value Code")
                                                {
                                                }
                                                column(Dimension_8_Value_Name; "Dimension Value Name")
                                                {
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

