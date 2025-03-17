function test_socket_serialize_class
    % Tests serialization of MATLAB class objects using CommandSocket class
    %
    % This test verifies that custom MATLAB class objects can be properly
    % serialized, transmitted, and deserialized using the CommandSocket class.
    
    fprintf('Testing class object serialization... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    try
        % Create test objects of different classes
        testObjects = {
            TestDataClass('Test Data', 42, rand(3)),
            TestHandleClass('Handle Object')
        };
        
        % Test each object
        for i = 1:length(testObjects)
            testObj = testObjects{i};
            
            % Create a struct with the test object
            sendData = struct('testObject', testObj, ...
                            'className', class(testObj), ...
                            'timestamp', now);
            
            % Send echo command with the object
            [responseObj, responseCmd] = client.sendCommand('echo', sendData);
            
            % Verify the response
            assert(strcmp(responseCmd, 'echoresponse'), 'Expected echoresponse command');
            assert(isfield(responseObj, 'testObject'), 'Expected testObject field in response');
            assert(isfield(responseObj, 'className'), 'Expected className field in response');
            
            % Verify the returned object is of the same class
            assert(strcmp(class(responseObj.testObject), class(testObj)), ...
                'Returned object should be of the same class');
            
            % Verify object properties
            switch class(testObj)
                case 'TestDataClass'
                    assert(strcmp(responseObj.testObject.Name, testObj.Name), 'Name property should match');
                    assert(responseObj.testObject.Value == testObj.Value, 'Value property should match');
                    assert(isequal(responseObj.testObject.Data, testObj.Data), 'Data property should match');
                    
                case 'TestHandleClass'
                    assert(strcmp(responseObj.testObject.Label, testObj.Label), 'Label property should match');
                    
                    % Handle objects are copied during serialization, not referenced
                    assert(~eq(responseObj.testObject, testObj), 'Handle objects should be copies, not the same reference');
            end
        end
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

% Test class definitions

% Value class (passed by value)
classdef TestDataClass
    properties
        Name
        Value
        Data
    end
    
    methods
        function obj = TestDataClass(name, value, data)
            if nargin > 0
                obj.Name = name;
                obj.Value = value;
                obj.Data = data;
            end
        end
    end
end

% Handle class (normally passed by reference)
classdef TestHandleClass < handle
    properties
        Label
        CreationTime
    end
    
    methods
        function obj = TestHandleClass(label)
            if nargin > 0
                obj.Label = label;
                obj.CreationTime = now;
            end
        end
    end
end

% Helper functions

function server = create_test_server()
    % Create a test server
    server = zmq.CommandSocket('server', 5559);
    server.start();
    
    % Start the server in a separate thread
    t = timer('ExecutionMode', 'fixedRate', ...
             'Period', 0.01, ...
             'TimerFcn', @(~,~) process_one_request(server));
    start(t);
    server.TestTimer = t; % Store for cleanup
    
    % Give time for server to start
    pause(0.1);
end

function client = create_test_client()
    % Create a test client
    client = zmq.CommandSocket('client', 5559);
    client.start();
    client.connect('localhost');
    
    % Give time for client to connect
    pause(0.1);
end

function cleanup_test_sockets(server, client)
    % Clean up test sockets
    
    % Stop server timer if it exists
    if isfield(server, 'TestTimer') && isa(server.TestTimer, 'timer') && isvalid(server.TestTimer)
        stop(server.TestTimer);
        delete(server.TestTimer);
    end
    
    % Clean up sockets
    if ~isempty(client)
        client.stop();
    end
    
    if ~isempty(server)
        server.stop();
    end
    
    % Give time for cleanup
    pause(0.1);
end

function process_one_request(server)
    % Process a single request if one is available
    try
        % Try to process a request with a timeout
        server.processOneRequest();
    catch
        % Ignore errors (likely timeout)
    end
end