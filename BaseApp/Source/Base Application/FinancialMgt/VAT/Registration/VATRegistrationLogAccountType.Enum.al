﻿// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Finance.VAT.Registration;

enum 240 "VAT Registration Log Account Type"
{
    Extensible = true;
    AssignmentCompatibility = true;

    value(0; "Customer") { Caption = 'Customer'; }
    value(1; "Vendor") { Caption = 'Vendor'; }
    value(2; "Contact") { Caption = 'Contact'; }
    value(3; "Company Information") { Caption = 'Company Information'; }
}
