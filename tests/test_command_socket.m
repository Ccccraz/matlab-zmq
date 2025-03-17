function test_command_socket
    % Test the zmq.CommandSocket class functionality
    %
    % This test verifies that the CommandSocket class works correctly in both
    % client and server modes, with proper command handling and object serialization.
    
    % Run the tests
    test_basic_client_server_communication();
    test_object_serialization();
    test_custom_commands();
    test_error_handling();
    test_callbacks();
    
    fprintf('\nAll CommandSocket tests passed!\n');
end

function test_basic_client_server_communication()
    % Test basic communication between client and server
    fprintf('Testing basic client-server communication... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    try
        % Test gettime command
        [responseObj, responseCmd] = client.sendCommand('gettime');
        assert(strcmp(responseCmd, 'timeresponse'), 'Expected timeresponse command');
        assert(isfield(responseObj, 'serverTime'), 'Expected serverTime field in response');
        assert(isfield(responseObj, 'timeString'), 'Expected timeString field in response');
        
        % Test echo command with simple data
        testData = struct('message', 'Hello world', 'value', 42);
        [responseObj, responseCmd] = client.sendCommand('echo', testData);
        assert(strcmp(responseCmd, 'echoresponse'), 'Expected echoresponse command');
        assert(isequal(responseObj.message, testData.message), 'Echo response should match sent message');
        assert(isequal(responseObj.value, testData.value), 'Echo response should match sent value');
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

function test_object_serialization()
    % Test serialization of different MATLAB data types
    fprintf('Testing object serialization... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    try
        % Test with different data types
        
        % 1. Test with numeric arrays
        numericData = struct('array1d', 1:10, ...
                            'array2d', reshape(1:9, 3, 3), ...
                            'array3d', rand(2, 2, 2));
        [responseObj, responseCmd] = client.sendCommand('echo', numericData);
        assert(isequal(responseObj.array1d, numericData.array1d), 'Array 1D should match');
        assert(isequal(responseObj.array2d, numericData.array2d), 'Array 2D should match');
        assert(isequal(responseObj.array3d, numericData.array3d), 'Array 3D should match');
        
        % 2. Test with cell arrays
        cellData = struct('cellArray', {{'text', 42, true, {1, 2}}});
        [responseObj, responseCmd] = client.sendCommand('echo', cellData);
        assert(isequal(responseObj.cellArray, cellData.cellArray), 'Cell array should match');
        
        % 3. Test with logical arrays
        logicalData = struct('logicalArray', logical([1 0 0 1]));
        [responseObj, responseCmd] = client.sendCommand('echo', logicalData);
        assert(isequal(responseObj.logicalArray, logicalData.logicalArray), 'Logical array should match');
        
        % 4. Test with nested structs
        nestedData = struct('level1', struct('level2', struct('level3', 'deep')));
        [responseObj, responseCmd] = client.sendCommand('echo', nestedData);
        assert(isequal(responseObj.level1.level2.level3, 'deep'), 'Nested struct should match');
        
        % 5. Test with empty array
        emptyData = struct('empty', []);
        [responseObj, responseCmd] = client.sendCommand('echo', emptyData);
        assert(isempty(responseObj.empty), 'Empty array should match');
        
        % 6. Test with special values
        specialData = struct('nan', NaN, 'inf', Inf, 'eps', eps);
        [responseObj, responseCmd] = client.sendCommand('echo', specialData);
        assert(isnan(responseObj.nan), 'NaN value should be preserved');
        assert(isinf(responseObj.inf), 'Inf value should be preserved');
        assert(responseObj.eps == eps, 'Eps value should be preserved');
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

function test_custom_commands()
    % Test custom command registration and handling
    fprintf('Testing custom commands... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    try
        % Register a custom command on the server
        server.registerCommand('test', @(socket, data) custom_command_handler(socket, data));
        
        % Send the custom command
        testData = struct('param1', 'test', 'param2', 123);
        [responseObj, responseCmd] = client.sendCommand('test', testData);
        
        % Verify response
        assert(strcmp(responseCmd, 'testresponse'), 'Expected testresponse command');
        assert(isfield(responseObj, 'success'), 'Expected success field in response');
        assert(responseObj.success, 'Expected success to be true');
        assert(isfield(responseObj, 'received'), 'Expected received field in response');
        assert(isequal(responseObj.received, testData), 'Expected received data to match sent data');
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

function test_error_handling()
    % Test error handling in CommandSocket
    fprintf('Testing error handling... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    try
        % Test sending unknown command
        [responseObj, responseCmd] = client.sendCommand('nonexistent');
        
        % Verify error response
        assert(strcmp(responseCmd, 'errorresponse'), 'Expected errorresponse command');
        assert(isfield(responseObj, 'error'), 'Expected error field in response');
        assert(responseObj.error, 'Expected error to be true');
        assert(isfield(responseObj, 'message'), 'Expected message field in response');
        assert(isfield(responseObj, 'validCommands'), 'Expected validCommands field in response');
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

function test_callbacks()
    % Test callback functionality
    fprintf('Testing callbacks... ');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    % Variables to track callback invocations
    command_received = false;
    response_received = false;
    
    try
        % Set up callbacks
        server.OnCommand = @(cmd, data) set_flag_callback(cmd, data, @() command_received = true);
        client.OnResponse = @(cmd, data) set_flag_callback(cmd, data, @() response_received = true);
        
        % Send a command to trigger callbacks
        client.sendCommand('echo', struct('test', 'data'));
        
        % Verify callbacks were called
        assert(command_received, 'Server OnCommand callback should have been called');
        assert(response_received, 'Client OnResponse callback should have been called');
        
        fprintf('OK\n');
    catch ME
        fprintf('FAILED\n');
        rethrow(ME);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

% Helper functions

function server = create_test_server()
    % Create a test server
    server = zmq.CommandSocket('server', 5558);
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
    client = zmq.CommandSocket('client', 5558);
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

function custom_command_handler(socket, data)
    % Handler for custom 'test' command
    responseObj = struct('success', true, ...
                       'message', 'Custom command processed', ...
                       'received', data);
    socket.sendObject(responseObj, 'testresponse');
end

function set_flag_callback(~, ~, flagFcn)
    % Callback that sets a flag
    flagFcn();
end