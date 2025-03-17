function test_command_socket_performance
    % Performance tests for the CommandSocket class
    %
    % This test measures the performance of the CommandSocket class for
    % different message sizes and serialization operations.
    
    fprintf('Running CommandSocket performance tests...\n');
    
    % Run performance tests
    test_message_throughput();
    test_serialization_performance();
    test_object_size_impact();
    
    fprintf('\nCommandSocket performance tests completed\n');
end

function test_message_throughput()
    % Test message throughput with different message sizes
    fprintf('Testing message throughput...\n');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    % Test parameters
    messageSizes = [10, 100, 1000, 10000, 100000];  % Bytes
    numMessages = 10;  % Number of messages per size
    
    fprintf('%-12s %-15s %-15s\n', 'Size (bytes)', 'Time (ms)', 'Throughput (MB/s)');
    
    try
        for size = messageSizes
            % Create test data of specified size
            testData = struct('array', rand(1, size/8));  % 8 bytes per double
            
            % Measure round-trip time
            tic;
            for i = 1:numMessages
                client.sendCommand('echo', testData);
            end
            elapsed = toc;
            
            % Calculate metrics
            avgTimeMs = (elapsed / numMessages) * 1000;
            throughputMBs = (size * numMessages) / (elapsed * 1024 * 1024);
            
            fprintf('%-12d %-15.2f %-15.2f\n', size, avgTimeMs, throughputMBs);
        end
    catch ME
        fprintf('Test failed: %s\n', ME.message);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

function test_serialization_performance()
    % Test serialization performance for different data types
    fprintf('\nTesting serialization performance...\n');
    
    % Test data types
    testData = {
        struct('name', 'Simple struct', 'value', 42),
        rand(100, 100),  % 10k element matrix
        cell(1, 1000),   % Large cell array
        struct('nested', struct('deep', struct('deeper', rand(10, 10))))  % Nested struct
    };
    
    dataNames = {'Simple struct', '10k matrix', 'Cell array', 'Nested struct'};
    
    fprintf('%-20s %-15s %-15s %-15s\n', 'Data Type', 'Serialize (ms)', 'Deserialize (ms)', 'Total (ms)');
    
    for i = 1:length(testData)
        data = testData{i};
        
        % Measure serialization time
        tic;
        for j = 1:10  % Average over 10 runs
            serialized = getByteStreamFromArray(data);
        end
        serializeTime = toc / 10 * 1000;  % ms
        
        % Measure deserialization time
        tic;
        for j = 1:10  % Average over 10 runs
            deserialized = getArrayFromByteStream(serialized);
        end
        deserializeTime = toc / 10 * 1000;  % ms
        
        % Report results
        fprintf('%-20s %-15.2f %-15.2f %-15.2f\n', ...
            dataNames{i}, serializeTime, deserializeTime, serializeTime + deserializeTime);
    end
end

function test_object_size_impact()
    % Test impact of object size on CommandSocket performance
    fprintf('\nTesting object size impact...\n');
    
    % Create server and client
    server = create_test_server();
    client = create_test_client();
    
    % Test parameters
    arraySizes = [10, 100, 1000, 10000];  % Number of elements
    
    fprintf('%-15s %-15s %-15s %-15s\n', 'Array Size', 'Data Size (KB)', 'RTT (ms)', 'Overhead (%)');
    
    try
        for size = arraySizes
            % Create test data
            testData = struct('array', rand(size, 1));
            
            % Get serialized size
            serialized = getByteStreamFromArray(testData);
            dataSize = length(serialized) / 1024;  % KB
            
            % Measure time for direct serialization/deserialization
            tic;
            for i = 1:5
                serialized = getByteStreamFromArray(testData);
                deserialized = getArrayFromByteStream(serialized);
            end
            directTime = toc / 5 * 1000;  % ms
            
            % Measure time for sending via CommandSocket
            tic;
            for i = 1:5
                client.sendCommand('echo', testData);
            end
            socketTime = toc / 5 * 1000;  % ms
            
            % Calculate overhead
            overhead = ((socketTime - directTime) / directTime) * 100;
            
            fprintf('%-15d %-15.2f %-15.2f %-15.1f\n', ...
                size, dataSize, socketTime, overhead);
        end
    catch ME
        fprintf('Test failed: %s\n', ME.message);
    end
    
    % Clean up
    cleanup_test_sockets(server, client);
end

% Helper functions

function server = create_test_server()
    % Create a test server
    server = zmq.CommandSocket('server', 5560);
    server.start();
    
    % Start the server in a separate thread
    t = timer('ExecutionMode', 'fixedRate', ...
             'Period', 0.001, ...  % Faster polling for performance tests
             'TimerFcn', @(~,~) process_one_request(server));
    start(t);
    server.TestTimer = t; % Store for cleanup
    
    % Give time for server to start
    pause(0.1);
end

function client = create_test_client()
    % Create a test client
    client = zmq.CommandSocket('client', 5560);
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