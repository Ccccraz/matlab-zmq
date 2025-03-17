function test_socket_serialize
    % Test the high-level Socket class API for serializing and deserializing MATLAB objects
    
    % Create context and sockets
    ctx = zmq.Context();
    server = ctx.socket('ZMQ_REP');
    client = ctx.socket('ZMQ_REQ');
    
    % Setup cleanup
    cleanupObj = onCleanup(@() cleanup(ctx, server, client));
    
    % Bind/connect
    server.bind('tcp://127.0.0.1:30001');
    client.connect('tcp://127.0.0.1:30001');
    
    % Create a test object with different data types
    testObj = struct();
    testObj.numeric = [1, 2, 3; 4, 5, 6];
    testObj.string = 'Hello ZeroMQ';
    testObj.logical = [true, false, true];
    testObj.cell = {1, 'two', 3.0};
    testObj.nested = struct('a', 1, 'b', 'test');
    
    % Test serialization with the Socket class API
    
    % Send request from client
    request = 'Client request';
    client.send_string(request);
    
    % Receive request on server
    receivedRequest = server.recv_string();
    assert(strcmp(receivedRequest, request), ...
        'Server should receive the client request. Expected "%s", but got "%s"', ...
        request, receivedRequest);
    
    % Serialize the test object
    serializedObj = getByteStreamFromArray(testObj);
    
    % Send multipart response: text + serialized object
    server.send(uint8('Response part 1'), 'sndmore');
    server.send(serializedObj);
    
    % Receive text part on client
    textResponse = char(client.recv());
    assert(strcmp(textResponse, 'Response part 1'), ...
        'Client should receive the first part of the response. Expected "Response part 1", but got "%s"', ...
        textResponse);
    
    % Check if there's another part and receive serialized object
    hasMoreParts = client.get('rcvmore');
    assert(hasMoreParts == 1, 'Socket should indicate more parts are available');
    
    serializedResponse = client.recv();
    hasMoreParts = client.get('rcvmore');
    assert(hasMoreParts == 0, 'Socket should indicate no more parts are available');
    
    % Deserialize the object
    deserializedObj = getArrayFromByteStream(serializedResponse);
    
    % Verify object fields and values
    assert(isstruct(deserializedObj), 'Deserialized data should be a struct');
    assert(isfield(deserializedObj, 'numeric'), 'Missing field: numeric');
    assert(isfield(deserializedObj, 'string'), 'Missing field: string');
    assert(isfield(deserializedObj, 'logical'), 'Missing field: logical');
    assert(isfield(deserializedObj, 'cell'), 'Missing field: cell');
    assert(isfield(deserializedObj, 'nested'), 'Missing field: nested');
    
    % Check numeric field
    assert(all(size(deserializedObj.numeric) == size(testObj.numeric)), ...
        'Numeric array dimensions should match');
    assert(all(all(deserializedObj.numeric == testObj.numeric)), ...
        'Numeric array values should match');
    
    % Check string field
    assert(strcmp(deserializedObj.string, testObj.string), ...
        'String field should match. Expected "%s", got "%s"', ...
        testObj.string, deserializedObj.string);
    
    % Check logical field
    assert(all(deserializedObj.logical == testObj.logical), ...
        'Logical array should match');
    
    % Check cell field
    assert(isequal(deserializedObj.cell, testObj.cell), ...
        'Cell array should match');
    
    % Check nested struct
    assert(isstruct(deserializedObj.nested), 'Nested field should be a struct');
    assert(deserializedObj.nested.a == testObj.nested.a, ...
        'Nested struct field "a" should match');
    assert(strcmp(deserializedObj.nested.b, testObj.nested.b), ...
        'Nested struct field "b" should match');
    
    % Test sending/receiving multipart message using send_multipart/recv_multipart
    
    % Create a large array to test multipart transmission
    largeArray = rand(1000, 1);
    serializedLargeArray = getByteStreamFromArray(largeArray);
    
    % Client sends a multipart message with the large array
    client.send_multipart(serializedLargeArray, 4096); % Use 4KB chunks
    
    % Server receives the multipart message
    receivedLargeSerializedArray = server.recv_multipart(4096);
    
    % Verify the received data
    deserializedLargeArray = getArrayFromByteStream(receivedLargeSerializedArray);
    assert(all(size(deserializedLargeArray) == size(largeArray)), ...
        'Large array dimensions should match');
    assert(all(deserializedLargeArray == largeArray), ...
        'Large array contents should match');
    
    % Server responds with a multipart message
    responseObj = struct('success', true, 'message', 'Large array received');
    serializedResponse = getByteStreamFromArray(responseObj);
    server.send_multipart(serializedResponse, 1024); % Use 1KB chunks
    
    % Client receives the response
    receivedResponseSerialized = client.recv_multipart(1024);
    deserializedResponse = getArrayFromByteStream(receivedResponseSerialized);
    
    % Verify response
    assert(isstruct(deserializedResponse), 'Response should be a struct');
    assert(isfield(deserializedResponse, 'success'), 'Response should have success field');
    assert(deserializedResponse.success, 'Success should be true');
    assert(strcmp(deserializedResponse.message, 'Large array received'), ...
        'Message should match');
end

function cleanup(ctx, server, client)
    % Clean up ZeroMQ resources
    
    if ~isempty(server)
        server.unbind('tcp://127.0.0.1:30001');
        server.close();
    end
    
    if ~isempty(client)
        client.disconnect('tcp://127.0.0.1:30001');
        client.close();
    end
    
    if ~isempty(ctx)
        ctx.term();
    end
end