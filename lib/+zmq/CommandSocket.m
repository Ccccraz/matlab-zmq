classdef CommandSocket < handle
    % CommandSocket - A class for ZeroMQ command-based communication with object serialization
    %
    % This class encapsulates both client and server behavior for ZeroMQ
    % communication with commands and serialized MATLAB objects. It can operate
    % in either client or server mode, and provides methods for sending and
    % receiving commands with serialized objects.
    %
    % Examples:
    %   % Create a server
    %   server = zmq.CommandSocket('server');
    %   server.start();
    %   server.processRequests();
    %
    %   % Create a client
    %   client = zmq.CommandSocket('client');
    %   client.connect('localhost');
    %   response = client.sendCommand('gettime');
    %
    % See also: zmq.Context, zmq.Socket
    
    properties
        % Core ZeroMQ properties
        Context         % ZeroMQ context
        Socket          % ZeroMQ socket
        Mode            % 'client' or 'server'
        Port = 5557     % Port to use (default: 5557)
        Address = ''    % Connection address (for client)
        Running = false % Flag to indicate if server is running
        
        % Command handling properties
        CommandHandlers    % Map of command handlers
        ResponseHandlers   % Map of response handlers
        
        % Callback properties
        OnMessage          % Callback for all received messages
        OnCommand          % Callback for received commands
        OnResponse         % Callback for received responses
        OnError            % Callback for errors
    end
    
    methods
        function obj = CommandSocket(mode, port)
            % Constructor for CommandSocket
            %
            % Parameters:
            %   mode - 'client' or 'server'
            %   port - (optional) Port number to use (default: 5557)
            
            % Validate mode
            if nargin < 1 || ~ischar(mode) || ...
                    (~strcmpi(mode, 'client') && ~strcmpi(mode, 'server'))
                error('Mode must be either ''client'' or ''server''');
            end
            
            % Set mode
            obj.Mode = lower(mode);
            
            % Set port if provided
            if nargin >= 2 && ~isempty(port)
                obj.Port = port;
            end
            
            % Initialize command handlers
            obj.CommandHandlers = containers.Map();
            obj.ResponseHandlers = containers.Map();
            
            % Register default command handlers
            obj.registerDefaultHandlers();
        end
        
        function delete(obj)
            % Destructor for CommandSocket
            obj.stop();
        end
        
        function start(obj)
            % Start the CommandSocket (initialize ZeroMQ socket)
            %
            % For server mode, this binds to the specified port
            % For client mode, this just creates the socket (connect must be called later)
            
            % Create ZeroMQ context and socket
            obj.Context = zmq.Context();
            
            if strcmpi(obj.Mode, 'server')
                % Server mode: create REP socket and bind
                obj.Socket = obj.Context.socket('ZMQ_REP');
                obj.Socket.bind(sprintf('tcp://*:%d', obj.Port));
                fprintf('Server started on port %d\n', obj.Port);
                obj.Running = true;
            else
                % Client mode: create REQ socket
                obj.Socket = obj.Context.socket('ZMQ_REQ');
                % Connection will be done with the connect method
            end
        end
        
        function connect(obj, host)
            % Connect to a server (client mode only)
            %
            % Parameters:
            %   host - Hostname or IP address of the server
            
            if ~strcmpi(obj.Mode, 'client')
                error('connect method can only be used in client mode');
            end
            
            if nargin < 2 || isempty(host)
                host = 'localhost';
            end
            
            % Construct address
            obj.Address = sprintf('tcp://%s:%d', host, obj.Port);
            
            % Connect to the server
            if ~isempty(obj.Socket)
                obj.Socket.connect(obj.Address);
                fprintf('Connected to server at %s\n', obj.Address);
                obj.Running = true;
            else
                error('Socket not initialized. Call start() first.');
            end
        end
        
        function stop(obj)
            % Stop the CommandSocket and clean up resources
            
            obj.Running = false;
            
            % Clean up socket
            if ~isempty(obj.Socket)
                if strcmpi(obj.Mode, 'server')
                    try
                        obj.Socket.unbind(sprintf('tcp://*:%d', obj.Port));
                    catch
                        % Ignore unbind errors
                    end
                elseif strcmpi(obj.Mode, 'client') && ~isempty(obj.Address)
                    try
                        obj.Socket.disconnect(obj.Address);
                    catch
                        % Ignore disconnect errors
                    end
                end
                
                try
                    obj.Socket.close();
                catch
                    % Ignore close errors
                end
                obj.Socket = [];
            end
            
            % Clean up context
            if ~isempty(obj.Context)
                try
                    obj.Context.term();
                catch
                    % Ignore term errors
                end
                obj.Context = [];
            end
            
            fprintf('Socket stopped\n');
        end
        
        function registerCommand(obj, command, handler)
            % Register a handler for a specific command
            %
            % Parameters:
            %   command - Command string to handle
            %   handler - Function handle to call when the command is received
            %             The handler should accept two parameters:
            %             - The CommandSocket object
            %             - The received object data
            
            obj.CommandHandlers(lower(command)) = handler;
        end
        
        function registerResponse(obj, response, handler)
            % Register a handler for a specific response
            %
            % Parameters:
            %   response - Response string to handle
            %   handler - Function handle to call when the response is received
            %             The handler should accept two parameters:
            %             - The CommandSocket object
            %             - The received object data
            
            obj.ResponseHandlers(lower(response)) = handler;
        end
        
        function [responseObj, responseCmd] = sendCommand(obj, command, data)
            % Send a command with optional data and wait for response
            %
            % Parameters:
            %   command - Command string to send
            %   data - (optional) Data object to send with the command
            %
            % Returns:
            %   responseObj - Object received in the response
            %   responseCmd - Command/text received in the response
            
            if ~strcmpi(obj.Mode, 'client')
                error('sendCommand method can only be used in client mode');
            end
            
            if nargin < 3
                data = [];
            end
            
            % Send the command
            obj.sendObject(data, command);
            
            % Receive and process the response
            [responseObj, responseCmd] = obj.receiveObject();
            
            % Invoke response handler if one exists
            if obj.ResponseHandlers.isKey(lower(responseCmd))
                handler = obj.ResponseHandlers(lower(responseCmd));
                handler(obj, responseObj);
            end
            
            % Call the general response callback if defined
            if ~isempty(obj.OnResponse)
                obj.OnResponse(responseCmd, responseObj);
            end
        end
        
        function sendResponse(obj, data, responseText)
            % Send a response with optional data (server mode only)
            %
            % Parameters:
            %   data - Data object to send with the response
            %   responseText - Text/command to send with the response
            
            if ~strcmpi(obj.Mode, 'server')
                error('sendResponse method can only be used in server mode');
            end
            
            % Send the response
            obj.sendObject(data, responseText);
        end
        
        function processRequests(obj, timeout)
            % Process incoming requests in a loop (server mode only)
            %
            % Parameters:
            %   timeout - (optional) Maximum time in seconds to process requests
            %             If not specified, will run until stop() is called
            
            if ~strcmpi(obj.Mode, 'server')
                error('processRequests method can only be used in server mode');
            end
            
            if nargin < 2
                timeout = inf;
            end
            
            startTime = tic;
            
            fprintf('Server started. Processing requests...\n');
            fprintf('Registered commands: ');
            commands = obj.CommandHandlers.keys();
            for i = 1:length(commands)
                fprintf('%s ', commands{i});
            end
            fprintf('\n');
            
            obj.Running = true;
            
            % Main processing loop
            while obj.Running && toc(startTime) < timeout
                try
                    % Wait for and process a single request
                    obj.processOneRequest();
                    
                    % Add a small pause to avoid CPU hogging
                    pause(0.01);
                catch ME
                    fprintf('Error processing request: %s\n', ME.message);
                    
                    % Call error callback if defined
                    if ~isempty(obj.OnError)
                        obj.OnError(ME);
                    end
                    
                    % Try to send an error response
                    try
                        errorData = struct('error', true, ...
                                         'message', ME.message, ...
                                         'stack', ME.stack);
                        obj.sendObject(errorData, 'errorresponse');
                    catch
                        % If sending error response fails, just continue
                    end
                end
            end
            
            fprintf('Server stopped processing requests\n');
        end
        
        function processOneRequest(obj)
            % Process a single incoming request (server mode only)
            
            if ~strcmpi(obj.Mode, 'server')
                error('processOneRequest method can only be used in server mode');
            end
            
            % Receive the command and data
            [clientObj, command] = obj.receiveObject();
            
            % Call the general message callback if defined
            if ~isempty(obj.OnMessage)
                obj.OnMessage(command, clientObj);
            end
            
            % Call the command callback if defined
            if ~isempty(obj.OnCommand)
                obj.OnCommand(command, clientObj);
            end
            
            % If we have a handler for this command, call it
            if obj.CommandHandlers.isKey(lower(command))
                handler = obj.CommandHandlers(lower(command));
                handler(obj, clientObj);
            else
                % Unknown command
                fprintf('Unknown command: %s\n', command);
                errorData = struct('error', true, ...
                                 'message', sprintf('Unknown command: %s', command), ...
                                 'validCommands', {obj.CommandHandlers.keys()});
                obj.sendObject(errorData, 'errorresponse');
            end
        end
    end
    
    % Private methods
    methods (Access = private)
        function sendObject(obj, data, text, options)
            % Send a serialized MATLAB object with text
            
            if nargin < 3
                text = '';
            end
            
            if nargin < 4
                options = {};
            end
            
            % Serialize the object if it's not empty
            if ~isempty(data)
                serializedObj = getByteStreamFromArray(data);
            else
                % If no data, just send an empty array
                serializedObj = uint8([]);
            end
            
            % Send text part with SNDMORE flag if we have both text and data
            if ~isempty(text) && ~isempty(serializedObj)
                obj.Socket.send(uint8(text), 'sndmore');
                obj.Socket.send(serializedObj, options{:});
            elseif ~isempty(text)
                % Just send text
                obj.Socket.send(uint8(text), options{:});
            elseif ~isempty(serializedObj)
                % Just send data
                obj.Socket.send(serializedObj, options{:});
            else
                % Send empty message
                obj.Socket.send(uint8(''), options{:});
            end
        end
        
        function [obj, text] = receiveObject(obj, options)
            % Receive a serialized MATLAB object with text
            
            if nargin < 2
                options = {};
            end
            
            % Receive the first part (command/text)
            message = obj.Socket.recv(options{:});
            text = char(message);
            
            % Check if there's more parts (the object)
            hasMoreParts = obj.Socket.get('rcvmore');
            
            if hasMoreParts
                % Receive the serialized object
                serializedObj = obj.Socket.recv(options{:});
                
                % Deserialize the object if it's not empty
                if ~isempty(serializedObj)
                    try
                        obj = getArrayFromByteStream(serializedObj);
                    catch ME
                        warning('Failed to deserialize object: %s', ME.message);
                        obj = [];
                    end
                else
                    obj = [];
                end
            else
                % No object part in the message
                obj = [];
            end
        end
        
        function registerDefaultHandlers(obj)
            % Register default command handlers
            
            % Echo command handler
            obj.registerCommand('echo', @(socket, data) obj.handleEcho(data));
            
            % Print command handler
            obj.registerCommand('print', @(socket, data) obj.handlePrint(data));
            
            % GetTime command handler
            obj.registerCommand('gettime', @(socket, data) obj.handleGetTime(data));
            
            % Quit command handler
            obj.registerCommand('quit', @(socket, data) obj.handleQuit(data));
            
            % Register default response handlers
            obj.registerResponse('echoresponse', @(socket, data) obj.displayResponse('Echo', data));
            obj.registerResponse('printresponse', @(socket, data) obj.displayResponse('Print', data));
            obj.registerResponse('timeresponse', @(socket, data) obj.displayTimeResponse(data));
            obj.registerResponse('quitresponse', @(socket, data) obj.displayQuitResponse(data));
            obj.registerResponse('errorresponse', @(socket, data) obj.displayErrorResponse(data));
        end
        
        function handleEcho(obj, data)
            % Handle 'echo' command
            fprintf('Echo command received\n');
            
            % Simply echo back the received data
            if ~isempty(data)
                responseObj = data;
            else
                responseObj = struct('message', 'No object received');
            end
            
            obj.sendObject(responseObj, 'echoresponse');
        end
        
        function handlePrint(obj, data)
            % Handle 'print' command
            fprintf('Print command received\n');
            
            % Print the received object
            if ~isempty(data)
                fprintf('Received object:\n');
                disp(data);
                responseObj = struct('success', true, 'message', 'Object printed');
            else
                fprintf('No object received to print\n');
                responseObj = struct('success', false, 'message', 'No object received');
            end
            
            obj.sendObject(responseObj, 'printresponse');
        end
        
        function handleGetTime(obj, data)
            % Handle 'gettime' command
            fprintf('GetTime command received\n');
            
            % Return current time
            currentTime = now;
            responseObj = struct('serverTime', currentTime, ...
                                'timeString', datestr(currentTime), ...
                                'timeZone', 'Local');
            
            obj.sendObject(responseObj, 'timeresponse');
        end
        
        function handleQuit(obj, data)
            % Handle 'quit' command
            fprintf('Quit command received\n');
            
            % Send quit confirmation
            responseObj = struct('message', 'Server shutting down');
            obj.sendObject(responseObj, 'quitresponse');
            
            % Set running flag to false to stop the server
            obj.Running = false;
        end
        
        function displayResponse(obj, responseType, data)
            % Display a generic response
            fprintf('%s response received:\n', responseType);
            if ~isempty(data)
                disp(data);
            else
                fprintf('(No data)\n');
            end
        end
        
        function displayTimeResponse(obj, data)
            % Display time response
            fprintf('Time response received:\n');
            if ~isempty(data) && isfield(data, 'timeString')
                fprintf('Remote time: %s\n', data.timeString);
                
                % Calculate time difference
                if isfield(data, 'serverTime')
                    timeDiff = (now - data.serverTime) * 24 * 60 * 60; % Difference in seconds
                    fprintf('Time difference: %.2f seconds\n', timeDiff);
                end
            else
                fprintf('(No time data)\n');
            end
        end
        
        function displayQuitResponse(obj, data)
            % Display quit response
            fprintf('Quit response received:\n');
            if ~isempty(data) && isfield(data, 'message')
                fprintf('%s\n', data.message);
            else
                fprintf('Remote side is shutting down\n');
            end
        end
        
        function displayErrorResponse(obj, data)
            % Display error response
            fprintf('Error response received:\n');
            if ~isempty(data)
                if isfield(data, 'message')
                    fprintf('Error: %s\n', data.message);
                end
                if isfield(data, 'validCommands')
                    fprintf('Valid commands: ');
                    fprintf('%s ', data.validCommands{:});
                    fprintf('\n');
                end
            else
                fprintf('(No error details)\n');
            end
        end
    end
end