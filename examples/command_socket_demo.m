function command_socket_demo
    % Demonstrates how to use the zmq.CommandSocket class
    %
    % This example shows how to:
    % 1. Create a server using CommandSocket
    % 2. Create a client using CommandSocket
    % 3. Send commands with serialized objects between them
    % 4. Add custom command handlers
    %
    % To run this demo:
    % 1. Open two MATLAB sessions
    % 2. In the first session, run: command_socket_demo('server')
    % 3. In the second session, run: command_socket_demo('client')
    
    % If no arguments, show usage
    if nargin < 1
        fprintf('Usage:\n');
        fprintf('  command_socket_demo server     - Run as server\n');
        fprintf('  command_socket_demo client     - Run as client\n');
        return;
    end
    
    % Process argument
    mode = varargin{1};
    
    if strcmpi(mode, 'server')
        runServer();
    elseif strcmpi(mode, 'client')
        runClient();
    else
        fprintf('Unknown mode: %s\n', mode);
        fprintf('Usage:\n');
        fprintf('  command_socket_demo server     - Run as server\n');
        fprintf('  command_socket_demo client     - Run as client\n');
    end
end

function runServer()
    % Run the CommandSocket in server mode
    
    fprintf('Starting CommandSocket server...\n');
    
    % Create the server
    server = zmq.CommandSocket('server');
    
    % Add custom command handler for 'status' command
    server.registerCommand('status', @(socket, data) handleStatusCommand(socket, data));
    
    % Start the server
    server.start();
    
    % Set a callback for all received commands
    server.OnCommand = @(cmd, data) fprintf('Server received command: %s\n', cmd);
    
    % Process requests until Ctrl+C is pressed
    try
        server.processRequests();
    catch ME
        if ~strcmp(ME.identifier, 'MATLAB:quit')
            rethrow(ME);
        end
    end
    
    % Clean up
    server.stop();
    fprintf('Server stopped.\n');
end

function runClient()
    % Run the CommandSocket in client mode
    
    fprintf('Starting CommandSocket client...\n');
    
    % Create the client
    client = zmq.CommandSocket('client');
    
    % Start the client and connect to server
    client.start();
    client.connect('localhost');
    
    % Set callbacks
    client.OnResponse = @(cmd, data) fprintf('Client received response: %s\n', cmd);
    
    % Interactive command loop
    try
        running = true;
        
        while running
            % Display available commands
            fprintf('\nAvailable commands:\n');
            fprintf('  echo        - Send an echo command with a test object\n');
            fprintf('  print       - Send a print command with a test object\n');
            fprintf('  gettime     - Get the server\'s current time\n');
            fprintf('  status      - Get the server\'s status\n');
            fprintf('  quit        - Stop the server\n');
            fprintf('  exit        - Exit this client\n');
            
            % Get command from user
            cmd = input('Enter command: ', 's');
            
            if isempty(cmd)
                continue;
            end
            
            cmd = lower(strtrim(cmd));
            
            % Handle client-side exit
            if strcmp(cmd, 'exit')
                fprintf('Exiting client...\n');
                break;
            end
            
            % Create appropriate data for the command
            data = [];
            
            switch cmd
                case 'echo'
                    fprintf('Creating sample object for echo...\n');
                    data = createSampleObject();
                    
                case 'print'
                    fprintf('Creating sample object for printing...\n');
                    data = createSampleObject();
                    
                case 'gettime'
                    data = struct('clientTime', now, ...
                                 'clientTimeString', datestr(now));
                    
                case 'status'
                    data = struct('requestedBy', getComputerName(), ...
                                 'timestamp', now);
                    
                case 'quit'
                    data = struct('message', 'Client requesting server shutdown');
                    
                otherwise
                    fprintf('Sending command: %s\n', cmd);
                    data = struct('message', sprintf('Command: %s', cmd));
            end
            
            % Send the command and get response
            fprintf('Sending command: %s\n', cmd);
            [responseObj, responseCmd] = client.sendCommand(cmd, data);
            
            % Check if we need to exit after the server's response
            if strcmp(cmd, 'quit') && strcmp(responseCmd, 'quitresponse')
                fprintf('Server shutdown confirmed. Exiting client.\n');
                running = false;
            end
        end
        
    catch ME
        fprintf('Error: %s\n', ME.message);
    end
    
    % Clean up
    client.stop();
    fprintf('Client stopped.\n');
end

function handleStatusCommand(socket, data)
    % Custom handler for 'status' command
    fprintf('Status command received\n');
    
    % Create a detailed status response
    statusInfo = struct();
    statusInfo.status = 'running';
    statusInfo.uptime = datestr(now, 'HH:MM:SS');
    statusInfo.hostname = getComputerName();
    
    % Add system information
    [~, systemInfo] = memory;
    statusInfo.memoryUsage = systemInfo.MemAvailableAllArrays / systemInfo.MemAvailableAllArrays;
    statusInfo.javaMemory = java.lang.Runtime.getRuntime().freeMemory() / java.lang.Runtime.getRuntime().totalMemory();
    
    if ~isempty(data) && isfield(data, 'requestedBy')
        statusInfo.requestedBy = data.requestedBy;
        statusInfo.requestTime = data.timestamp;
    end
    
    % Send the response
    fprintf('Sending status response\n');
    socket.sendObject(statusInfo, 'statusresponse');
end

function obj = createSampleObject()
    % Create a sample object with various data types
    
    obj = struct();
    obj.timestamp = now;
    obj.dateString = datestr(now);
    obj.randomData = rand(3, 3);
    obj.message = 'Sample object from command_socket_demo';
    obj.ipAddress = getIPAddress();
    obj.computerName = getComputerName();
    
    % Add some more complex data types
    obj.cell = {1, 'two', 3.0, logical([1 0 1])};
    obj.logical = logical([1 0 0 1 1]);
    obj.nested = struct('a', 1, 'b', 'test', 'c', {{'nested', 'cell'}});
end

function ipAddress = getIPAddress()
    % Get the IP address of the local machine
    try
        % Try using Java to get IP address (works in newer MATLAB versions)
        import java.net.InetAddress;
        ipAddress = char(InetAddress.getLocalHost.getHostAddress);
    catch
        % Fallback method
        ipAddress = '127.0.0.1'; % Default to localhost
    end
end

function name = getComputerName()
    % Get the computer name
    try
        % Try using Java to get computer name (works in newer MATLAB versions)
        import java.net.InetAddress;
        name = char(InetAddress.getLocalHost.getHostName);
    catch
        % Fallback method
        [~, name] = system('hostname');
        name = strtrim(name);
    end
end