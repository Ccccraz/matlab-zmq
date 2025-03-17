function test_object_serialization
    % Test the serialization and deserialization of MATLAB objects through ZeroMQ
    
    [ctx, server, client] = setup;
    cleanupObj = onCleanup(@() teardown(ctx, server, client));
    
    %% Create test object
    testData = struct();
    testData.timestamp = now;
    testData.value = [1, 2, 3, 4, 5];
    testData.message = 'Test message';
    
    %% Test sending and receiving multipart message with serialized object
    
    % Client test - request send
    requestMsg = 'Request from client';
    assert_does_not_throw(@zmq.core.send, client, uint8(requestMsg));
    
    % Server test - request receive
    receivedRequest = char(zmq.core.recv(server));
    assert(strcmp(receivedRequest, requestMsg), ...
        'Server should receive the client request message. Expected "%s", but got "%s"', ...
        requestMsg, receivedRequest);
    
    % Server test - send multipart response (text + serialized object)
    responseMsg = 'Response from server';
    serializedData = getByteStreamFromArray(testData);
    
    % Send first part with SNDMORE flag
    zmq.core.setsockopt(server, 'ZMQ_SNDMORE', uint8(1));
    assert_does_not_throw(@zmq.core.send, server, uint8(responseMsg));
    
    % Send second part (serialized object)
    assert_does_not_throw(@zmq.core.send, server, serializedData);
    
    % Client test - receive text response
    receivedResponse = char(zmq.core.recv(client));
    assert(strcmp(receivedResponse, responseMsg), ...
        'Client should receive the server response message. Expected "%s", but got "%s"', ...
        responseMsg, receivedResponse);
    
    % Client test - check if there's another part
    hasMoreParts = zmq.core.getsockopt(client, 'ZMQ_RCVMORE');
    assert(hasMoreParts == 1, ...
        'ZMQ_RCVMORE should be 1 when there are more message parts to receive');
    
    % Client test - receive and deserialize object
    receivedSerialized = zmq.core.recv(client);
    hasMoreParts = zmq.core.getsockopt(client, 'ZMQ_RCVMORE');
    assert(hasMoreParts == 0, ...
        'ZMQ_RCVMORE should be 0 after receiving all parts of a multipart message');
    
    % Test deserialization
    deserializedData = getArrayFromByteStream(receivedSerialized);
    
    % Verify the object structure
    assert(isstruct(deserializedData), 'Deserialized data should be a struct');
    assert(isfield(deserializedData, 'timestamp'), 'Deserialized data should have a timestamp field');
    assert(isfield(deserializedData, 'value'), 'Deserialized data should have a value field');
    assert(isfield(deserializedData, 'message'), 'Deserialized data should have a message field');
    
    % Verify the object contents
    assert(deserializedData.timestamp == testData.timestamp, ...
        'Timestamp field should match. Expected %f, got %f', ...
        testData.timestamp, deserializedData.timestamp);
    assert(all(deserializedData.value == testData.value), ...
        'Value field should match. Expected %s, got %s', ...
        mat2str(testData.value), mat2str(deserializedData.value));
    assert(strcmp(deserializedData.message, testData.message), ...
        'Message field should match. Expected "%s", got "%s"', ...
        testData.message, deserializedData.message);
    
    % Test DONTWAIT flag behavior with serialized objects
    try
        % Try to receive when there's no message (should throw)
        zmq.core.recv(client, 1024, 'ZMQ_DONTWAIT');
        assert(false, 'Should have thrown an exception when no message available');
    catch e
        % This is expected
    end
end

function [ctx, server, client] = setup
    % Setup ZeroMQ context and REQ-REP socket pair for testing
    
    %% Open session
    ctx = zmq.core.ctx_new();
    
    % Create REQ socket for client
    client = zmq.core.socket(ctx, 'ZMQ_REQ');
    zmq.core.connect(client, 'tcp://127.0.0.1:30000');
    
    % Create REP socket for server
    server = zmq.core.socket(ctx, 'ZMQ_REP');
    zmq.core.bind(server, 'tcp://127.0.0.1:30000');
end

function teardown(ctx, server, client)
    % Clean up ZeroMQ resources
    
    %% Close session
    zmq.core.unbind(server, 'tcp://127.0.0.1:30000');
    zmq.core.close(server);
    
    zmq.core.disconnect(client, 'tcp://127.0.0.1:30000');
    zmq.core.close(client);
    
    zmq.core.ctx_shutdown(ctx);
    zmq.core.ctx_term(ctx);
end