// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved. 
// Licensed under the MIT License. See License.txt in the project root for license information. 
// ------------------------------------------------------------------------------------------------

codeunit 50171 AzureBlobStorage
{
    // 
    // Azure Blob Storage REST Api
    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/blob-service-rest-api
    //
    var
        AccountName: Text;
        ResourceUri: Text;
        [NonDebuggable]
        SharedKey: Text;
        StorageApiVersionTok: label '2015-07-08', locked = true;
        PutVerbTok: label 'PUT', locked = true;
        GetVerbTok: label 'GET', locked = true;
        DeleteVerbTok: label 'DELETE', locked = true;
        StorageNotEnabledErr: label 'Azure Storage is not set-up. Please go to Service Connections to set-up';
        IsInitialized: Boolean;

    //
    // Initialize the Blob Storage Api
    //
    procedure Initialize();
    var
        AzureStorageSetup: Record AzureStorageSetup;
    begin
        if not AzureStorageSetup.Get() then
            Error(StorageNotEnabledErr);

        if not AzureStorageSetup.IsEnabled then
            Error(StorageNotEnabledErr);

        AccountName := AzureStorageSetup.AccountName;
        ResourceUri := StrSubstNo('https://%1.blob.core.windows.net', AzureStorageSetup.AccountName);
        SharedKey := AzureStorageSetup.GetSharedAccessKey();

        IsInitialized := true;
    end;

    local procedure CheckInitialized();
    begin
        if not IsInitialized then
            Initialize();
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/list-containers2
    // 
    procedure ListContainers(var containers: XmlDocument);
    var
        client: HttpClient;
        request: HttpRequestMessage;
        response: HttpResponseMessage;
        content: Text;
    begin
        CheckInitialized();

        InitializeRequest(request, GetVerbTok, '/', 'comp=list');
        client.Send(request, response);
        CheckResponseCode(response);

        response.Content().ReadAs(content);
        XmlDocument.ReadFrom(content, containers);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/list-containers2
    // 
    procedure ListContainers(var Containers: record AzureBlobStorageContainer temporary)
    var
        TypeHelper: Codeunit "Type Helper";
        ContainersXml: XmlDocument;
        ContainerList: XmlNodeList;
        ContainerNode: XmlNode;
        Node: XmlNode;
        Properties: XmlElement;
        i: Integer;
    begin
        ListContainers(ContainersXml);

        containers.DeleteAll();
        if ContainersXml.SelectNodes('/EnumerationResults/Containers/Container', ContainerList) then
            for i := 1 to ContainerList.Count() do begin
                Containers.Init();

                ContainerList.Get(i, ContainerNode);

                ContainerNode.SelectSingleNode('Name', Node);
                Containers.Name := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Containers.Name));

                if ContainerNode.SelectSingleNode('Properties', Node) then begin
                    Properties := Node.AsXmlElement();

                    if Properties.SelectSingleNode('Last-Modified', Node) then
                        Containers."Last-Modified" := TypeHelper.EvaluateUTCDateTime(Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('Etag', Node) then
                        Containers.Etag := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Containers.Etag));

                    if Properties.SelectSingleNode('LeaseState', Node) then
                        Evaluate(Containers.LeaseState, Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('LeaseStatus', Node) then
                        Evaluate(Containers.LeaseStatus, Node.AsXmlElement().InnerText());
                end;

                Containers.Insert();
            end;
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/create-container
    // 
    procedure CreateContainer(ResourcePath: Text);
    var
        client: HttpClient;
        request: HttpRequestMessage;
        response: HttpResponseMessage;
    begin
        CheckInitialized();

        InitializeRequest(request, PutVerbTok, ResourcePath, 'restype=container');
        client.Send(request, response);
        CheckResponseCode(response);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/delete-container
    // 
    procedure DeleteContainer(ResourcePath: Text): Boolean;
    var
        client: HttpClient;
        request: HttpRequestMessage;
        response: HttpResponseMessage;
    begin
        CheckInitialized();

        InitializeRequest(request, DeleteVerbTok, ResourcePath, 'restype=container');
        client.Send(request, response);
        CheckResponseCode(response);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/list-blobs
    // 
    procedure ListBlobs(ResourcePath: Text; Prefix: Text; var blobs: XmlDocument);
    var
        client: HttpClient;
        request: HttpRequestMessage;
        response: HttpResponseMessage;
        content: Text;
        parameters: Text;
    begin
        CheckInitialized();

        parameters := 'restype=container&comp=list';
        if prefix <> '' then
            parameters += '&prefix=' + Prefix; // TODO: Escaping of Prefix?
        InitializeRequest(request, GetVerbTok, ResourcePath, parameters);
        client.Send(request, response);
        CheckResponseCode(response);

        response.Content().ReadAs(content);
        XmlDocument.ReadFrom(content, blobs);
    end;

    procedure ListBlobs(ResourcePath: Text; var blobs: XmlDocument);
    begin
        ListBlobs(ResourcePath, '', blobs);
    end;

    procedure ListBlobs(ResourcePath: Text; Prefix: Text; var Blobs: record AzureBlobStorageBlob)
    var
        TypeHelper: Codeunit "Type Helper";
        BlobsXml: XmlDocument;
        BlobList: XmlNodeList;
        BlobNode: XmlNode;
        Node: XmlNode;
        Properties: XmlElement;
        i: Integer;
    begin
        ListBlobs(ResourcePath, Prefix, BlobsXml);

        Blobs.DeleteAll();
        if BlobsXml.SelectNodes('/EnumerationResults/Blobs/Blob', BlobList) then
            for i := 1 to BlobList.Count() do begin
                Blobs.Init();

                BlobList.Get(i, BlobNode);

                BlobNode.SelectSingleNode('Name', Node);
                Blobs.Name := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Blobs.Name));

                if BlobNode.SelectSingleNode('Properties', Node) then begin
                    Properties := Node.AsXmlElement();

                    if Properties.SelectSingleNode('Last-Modified', Node) then
                        Blobs."Last-Modified" := TypeHelper.EvaluateUTCDateTime(Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('Etag', Node) then
                        Blobs.Etag := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Blobs.Etag));

                    if Properties.SelectSingleNode('LeaseState', Node) then
                        Evaluate(Blobs.LeaseState, Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('LeaseStatus', Node) then
                        Evaluate(Blobs.LeaseStatus, Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('Content-Length', Node) then
                        Evaluate(Blobs."Content-Length", Node.AsXmlElement().InnerText());

                    if Properties.SelectSingleNode('Content-Type', Node) then
                        Blobs."Content-Type" := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Blobs.Etag));

                    if Properties.SelectSingleNode('Content-Encoding', Node) then
                        Blobs."Content-Encoding" := CopyStr(Node.AsXmlElement().InnerText(), 1, MaxStrLen(Blobs.Etag));
                end;

                Blobs.Container := CopyStr(ResourcePath, 1, MaxStrLen(Blobs.Container));

                Blobs.Insert();
            end;
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/get-blob
    // 
    procedure GetBlob(ResourcePath: Text; var blob: InStream): Boolean;
    var
        response: HttpResponseMessage;
    begin
        GetBlob(ResourcePath, response);

        response.Content().ReadAs(blob);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/get-blob
    // 
    procedure GetBlob(ResourcePath: Text; var blob: Text): Boolean;
    var
        response: HttpResponseMessage;
    begin
        GetBlob(ResourcePath, response);

        response.Content().ReadAs(blob);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/get-blob
    // 
    local procedure GetBlob(ResourcePath: Text; var response: HttpResponseMessage)
    var
        client: HttpClient;
        request: HttpRequestMessage;
    begin
        CheckInitialized();

        InitializeRequest(request, GetVerbTok, ResourcePath, '');
        client.Send(request, response);
        CheckResponseCode(response);
    end;


    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/delete-blob
    // 
    procedure DeleteBlob(ResourcePath: Text)
    var
        client: HttpClient;
        request: HttpRequestMessage;
        response: HttpResponseMessage;
    begin
        CheckInitialized();

        InitializeRequest(request, DeleteVerbTok, ResourcePath, '');
        client.Send(request, response);
        CheckResponseCode(response);
    end;


    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob
    // 
    procedure PutBlob(ResourcePath: Text; blob: InStream; ContentType: Text)
    var
        TempBlob: codeunit "Temp Blob";
        request: HttpRequestMessage;
        ins: InStream;
        outs: OutStream;
    begin
        TempBlob.CreateOutStream(outs);
        CopyStream(outs, blob);
        TempBlob.CreateInStream(ins);

        request.Content().WriteFrom(ins);
        PutBlob(ResourcePath, TempBlob.Length(), ContentType, request);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob
    // 
    procedure PutBlob(ResourcePath: Text; blob: codeunit "Temp Blob"; ContentType: Text)
    var
        request: HttpRequestMessage;
        ins: InStream;
    begin
        blob.CreateInStream(ins);
        request.Content().WriteFrom(ins);
        PutBlob(ResourcePath, blob.Length(), ContentType, request);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob
    // 
    procedure PutBlob(ResourcePath: Text; blob: Text)
    begin
        PutBlob(ResourcePath, blob, 'text/plain; charset=utf-8')
    end;
    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob
    // 
    procedure PutBlob(ResourcePath: Text; blob: Text; ContentType: Text)
    var
        request: HttpRequestMessage;
    begin
        request.Content().WriteFrom(blob);
        PutBlob(ResourcePath, StrLen(blob), ContentType, request);
    end;

    //
    // Api Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob
    // 
    local procedure PutBlob(ResourcePath: Text; ContentLength: Integer; ContentType: Text; var request: HttpRequestMessage)
    var
        client: HttpClient;
        response: HttpResponseMessage;
        headers: HttpHeaders;
    begin
        CheckInitialized();

        request.Content().GetHeaders(headers);
        headers.Add('Content-Length', Format(ContentLength));
        if headers.Contains('Content-Type') then
            headers.Remove('Content-Type');
        headers.Add('Content-Type', ContentType);

        InitializeRequest(request, PutVerbTok, ResourcePath, '', 'x-ms-blob-type:BlockBlob', Format(ContentLength), ContentType);
        client.Send(request, response);
        CheckResponseCode(response);
    end;

    local procedure CheckResponseCode(response: HttpResponseMessage)
    begin
        if not response.IsSuccessStatusCode() then
            Error(response.ReasonPhrase());
    end;

    local procedure InitializeRequest(var request: HttpRequestMessage; methodVerb: Text; resourcePath: Text; parameters: Text)
    begin
        InitializeRequest(request, methodVerb, resourcePath, parameters, '', '', '');
    end;

    local procedure InitializeRequest(var request: HttpRequestMessage; methodVerb: Text; resourcePath: Text; parameters: Text; xHeaders: Text; ContentLength: Text; ContentType: Text)
    var
        TypeHelper: codeunit "Type Helper";
        headers: HttpHeaders;
        UtcDateTime: Text;
        token: Text;
        xHeaderList: List of [Text];
        header: Text;
        index: Integer;
    begin
        UtcDateTime := TypeHelper.GetCurrUTCDateTimeAsText();

        request.GetHeaders(headers);

        // Add x-ms-??? headers
        headers.Add('x-ms-date', UtcDateTime);
        headers.Add('x-ms-version', StorageApiVersionTok);
        if xHeaders <> '' then begin
            xHeaderList := xHeaders.Split(';');
            foreach header in xHeaderList do begin
                index := header.IndexOf(':');
                token := header.Substring(1, index - 1);
                token := header.Substring(index);
                headers.Add(header.Substring(1, index - 1), header.Substring(index + 1));
            end;
        end;

        // Add Authorization header
        token := GetSasToken(methodVerb, ResourcePath, UtcDateTime, ContentLength, ContentType, CreateCanonicalizedParameters(parameters), xHeaderList);
        headers.Add('Authorization', token);

        request.Method := methodVerb;
        if parameters <> '' then
            resourcePath := resourcePath + '?' + parameters;
        request.SetRequestUri(ResourceUri + ResourcePath);
    end;

    local procedure CreateCanonicalizedParameters(parameters: Text): Text;
    var
        builder: TextBuilder;
        paramList: List of [Text];
        i: Integer;
        Cr: Text[1];
    begin
        if parameters = '' then
            exit;

        Cr[1] := 10;
        paramList := parameters.Split('&');
        SortList(paramList);

        for i := 1 to paramList.Count() do begin
            if builder.Length() > 0 then
                builder.Append(Cr);
            builder.Append(paramList.Get(i).Replace('=', ':'));
        end;

        exit(builder.ToText());
    end;

    local procedure SortList(var list: List of [Text])
    var
        i: Integer;
        j: Integer;
        s: Text;
    begin
        for i := 1 to list.Count() - 1 do
            for j := i + 1 to list.Count() do
                if list.Get(i) > list.Get(j) then begin
                    s := list.Get(i);
                    list.Set(i, list.Get(j));
                    list.Set(j, s);
                end;
    end;

    //
    // Shared Access Key Generation
    //
    // Documentation: https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
    //
    // Some digested documentation here: https://www.red-gate.com/simple-talk/cloud/platform-as-a-service/azure-blob-storage-part-5-blob-storage-rest-api/
    //
    local procedure GetSasToken(Verb: Text; ResourcePath: Text; Date: Text; ContentLength: Text; ContentType: Text; query: Text; xHeaderList: List of [Text]): Text;
    var
        EncryptionManagement: codeunit "Cryptography Management";
        Cr: Text[1];
        stringToSign: TextBuilder;
        Signature: Text;
        header: Text;
    begin
        Cr[1] := 10;

        stringToSign.Append(Verb + Cr +
              Cr + /*Content-Encoding*/
              Cr + /*Content-Language*/
              ContentLength + Cr + /*Content-Length*/
              Cr + /*Content-MD5*/
              ContentType + Cr + /*Content-Type*/
              Cr + /*Date*/
              Cr + /*If-Modified-Since*/
              Cr + /*If-Match*/
              Cr + /*If-None-Match*/
              Cr + /*If-Unmodified-Since*/
              Cr); /*Range*/

        xHeaderList.Add('x-ms-date:' + Date);
        xHeaderList.Add('x-ms-version:' + StorageApiVersionTok);
        SortList(xHeaderList);
        foreach header in xHeaderList do begin
            stringToSign.Append(header);
            stringToSign.Append(Cr);
        end;

        stringToSign.Append('/' + AccountName + ResourcePath);
        if query <> '' then
            stringToSign.Append(Cr + query);

        header := stringToSign.ToText();
        signature := EncryptionManagement.GenerateBase64KeyedHashAsBase64String(stringToSign.ToText(), SharedKey, 2 /* HMACSHA256 */);

        exit(StrSubstNo('SharedKey %1:%2', AccountName, Signature));
    end;

    procedure GetContentTypeFromFileName(Filename: Text): Text;
    var
        Extension: Text;
        IndexOfLastDot: Integer;
    begin
        IndexOfLastDot := Filename.LastIndexOf('.');
        if IndexOfLastDot < 1 then
            exit('');

        Extension := Filename.Substring(IndexOfLastDot + 1).ToLower();
        case Extension of
            'jpg':
                exit('image/jpeg');
            'pdf':
                exit('application/pdf');
            'png':
                exit('image/png');
            'txt':
                exit('text/plain');
            else
                exit('');
        end;
    end;
}