function object_client(varargin)
    % ZeroMQ client that communicates with a server using commands and serialized objects
    %
    % This client supports bidirectional communication with the server using commands:
    % - 'echo': Server echoes back the sent object
    % - 'print': Server prints the object to its command window
    % - 'gettime': Server returns its current time
    % - 'quit': Server shuts down
    %
    % The client also supports the same commands coming from the server:
    % - When receiving 'echo', client sends back the object
    % - When receiving 'print', client prints the object
    % - When receiving 'gettime', client sends back its current time
    %
    % Usage:
    %   object_client()              - Connect to localhost on default port 5557
    %   object_client(server)        - Connect to specified server on default port
    %   object_client(server, port)  - Connect to specified server and port
    
    % Parse input arguments
    server = 'localhost';
    port = 5557;
    
    if (nargin > 0)
        server = varargin{1};
    end
    
    if (nargin > 1)
        port = varargin{2};
    end
    
    % Create ZeroMQ context and REQ socket
    context = zmq.Context();
    socket = context.socket('ZMQ_REQ');
    
    % Connect to server
    address = sprintf('tcp://%s:%d', server, port);
    fprintf('Connecting to server at %s...\n', address);
    socket.connect(address);
    
    try
        % Interactive command loop
        running = true;
        
        while running
            % Get command from user
            fprintf('\nAvailable commands: echo, print, gettime, quit, exit\n');
            cmd = input('Enter command: ', 's');
            
            if isempty(cmd)
                continue;
            end
            
            cmd = lower(strtrim(cmd));
            
            % Handle client-side exit (doesn't send to server)
            if strcmp(cmd, 'exit')
                fprintf('Exiting client without stopping server...\n');
                break;
            end
            
            % Create object to send based on the command
            switch cmd
                case 'echo'
                    sendObj = createSampleObject();
                    fprintf('Sending sample object to be echoed back:\n');
                    disp(sendObj);
                    
                case 'print'
                    sendObj = createSampleObject();
                    fprintf('Sending sample object to be printed by server:\n');
                    
                case 'gettime'
                    sendObj = struct('clientTime', now, ...
                                     'clientTimeString', datestr(now));
                    
                case 'quit'
                    sendObj = struct('message', 'Client requesting server shutdown');
                    
                otherwise
                    fprintf('Sending command: %s\n', cmd);
                    sendObj = struct('message', sprintf('Command: %s', cmd));
            end
            
            % Send command and object to server
            fprintf('Sending command: %s\n', cmd);
            sendObject(socket, sendObj, cmd);
            
            % Receive response from server
            fprintf('Waiting for server response...\n');
            [responseObj, responseCmd] = receiveObject(socket);
            
            fprintf('Received response command: %s\n', responseCmd);
            
            % Process server response
            processServerResponse(responseCmd, responseObj);
            
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
    socket.disconnect(address);
    socket.close();
    context.term();
    fprintf('Client disconnected.\n');
end

function sendObject(socket, obj, text, options)
    % Send a serialized MATLAB object with text message
    
    if nargin < 3
        text = '';
    end
    
    if nargin < 4
        options = {};
    end
    
    % Serialize the object
    serializedObj = getByteStreamFromArray(obj);
    
    % Send text part with SNDMORE flag
    if ~isempty(text)
        socket.send(uint8(text), 'sndmore');
    end
    
    % Send serialized object
    socket.send(serializedObj, options{:});
end

function [obj, text] = receiveObject(socket, options)
    % Receive a serialized MATLAB object with text message
    
    if nargin < 2
        options = {};
    end
    
    % Receive the first part (command/text)
    message = socket.recv(options{:});
    text = char(message);
    
    % Check if there's more parts (the object)
    hasMoreParts = socket.get('rcvmore');
    
    if hasMoreParts
        % Receive the serialized object
        serializedObj = socket.recv(options{:});
        
        % Deserialize the object
        try
            obj = getArrayFromByteStream(serializedObj);
        catch ME
            warning('Failed to deserialize object: %s', ME.message);
            obj = [];
        end
    else
        % No object part in the message
        obj = [];
    end
end

function obj = createSampleObject()
    % Create a sample object with various data types
    
    obj = struct();
    obj.timestamp = now;
    obj.dateString = datestr(now);
    obj.randomData = rand(3, 3);
    obj.message = 'Sample object from client';
    obj.ipAddress = getIPAddress();
    obj.computerName = getComputerName();
end

function processServerResponse(command, obj)
    % Process the response from the server
    
    switch command
        case 'echoresponse'
            fprintf('Received echo response with object:\n');
            if ~isempty(obj)
                disp(obj);
            else
                fprintf('(No object data)\n');
            end
            
        case 'printresponse'
            fprintf('Server printed the object. Response:\n');
            if ~isempty(obj)
                disp(obj);
            else
                fprintf('(No response data)\n');
            end
            
        case 'timeresponse'
            fprintf('Received server time:\n');
            if ~isempty(obj) && isfield(obj, 'timeString')
                fprintf('Server time: %s\n', obj.timeString);
                
                % Calculate time difference between client and server
                clientTime = now;
                if isfield(obj, 'serverTime')
                    timeDiff = (clientTime - obj.serverTime) * 24 * 60 * 60; % Difference in seconds
                    fprintf('Time difference: %.2f seconds\n', timeDiff);
                end
            else
                fprintf('(No time data received)\n');
            end
            
        case 'quitresponse'
            fprintf('Server acknowledged quit command:\n');
            if ~isempty(obj) && isfield(obj, 'message')
                fprintf('%s\n', obj.message);
            else
                fprintf('Server is shutting down.\n');
            end
            
        case 'errorresponse'
            fprintf('Server reported an error:\n');
            if ~isempty(obj)
                if isfield(obj, 'message')
                    fprintf('Error: %s\n', obj.message);
                end
                if isfield(obj, 'validCommands')
                    fprintf('Valid commands: ');
                    fprintf('%s ', obj.validCommands{:});
                    fprintf('\n');
                end
            else
                fprintf('(No error details provided)\n');
            end
            
        otherwise
            fprintf('Unknown response command: %s\n', command);
            if ~isempty(obj)
                fprintf('Response data:\n');
                disp(obj);
            end
    end
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