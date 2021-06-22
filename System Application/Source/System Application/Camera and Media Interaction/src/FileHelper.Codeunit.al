// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------

codeunit 1910 "File Helper"
{
    Access = Internal;

    var
        FilePath: Text;
        FileNotAvailableErr: Label 'The file is not available.';

    [TryFunction]
    procedure GetFile(var TempBlob: Codeunit "Temp Blob")
    var
        File: File;
        InStr: InStream;
        OutStr: OutStream;
    begin
        if not File.Open(FilePath) then
            Error(FileNotAvailableErr);

        File.CreateInStream(InStr);
        TempBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStr);
        File.Close();
    end;

    procedure FileExists(): Boolean
    begin
        if FilePath = '' then
            exit(false);
        exit(Exists(FilePath));
    end;

    procedure SetPath(SavedFilePath: Text)
    begin
        FilePath := SavedFilePath;
    end;
}
