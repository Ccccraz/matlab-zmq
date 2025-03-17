function object_server(varargin)
    % ZeroMQ server that processes commands with serialized MATLAB objects
    %
    % This server demonstrates bidirectional communication with commands and
    % serialized objects. It supports the following commands:
    % - 'echo': Returns the object back to the client
    % - 'print': Prints the object contents to the command window
    % - 'gettime': Returns the server's current time
    % - 'quit': Stops the server
    %
    % Usage:
    %   object_server()              - Use default port 5557
    %   object_server(port)          - Use specified port
    
    % Parse input arguments
    port = 5557;
    if (nargin > 0)
        port = varargin{1};
    end
    
    % Create ZeroMQ context and REP socket (for request-reply pattern)
    context = zmq.Context();
    socket = context.socket('ZMQ_REP');
    socket.bind(sprintf('tcp://*:%d', port));
    
    fprintf('Server started on port %d.\n', port);
    fprintf('Supported commands: echo, print, gettime, quit\n');
    fprintf('Press Ctrl+C to stop.\n\n');
    
    try
        while true
            % Wait for client request
            fprintf('Waiting for client request...\n');
            
            % Receive message and optional object
            [clientObj, command] = receiveObject(socket);
            
            fprintf('Received command: %s\n', command);
            
            % Process the command
            switch lower(strtrim(command))
                case 'echo'
                    % Echo the object back to the client
                    fprintf('Echoing object back to client...\n');
                    if ~isempty(clientObj)
                        responseObj = clientObj;
                        responseText = 'echoresponse';
                    else
                        responseObj = struct('message', 'No object received');
                        responseText = 'echoresponse';
                    end
                    
                case 'print'
                    % Print the object contents
                    fprintf('Printing received object:\n');
                    if ~isempty(clientObj)
                        disp(clientObj);
                        responseObj = struct('success', true, 'message', 'Object printed');
                    else
                        fprintf('No object received to print.\n');
                        responseObj = struct('success', false, 'message', 'No object received');
                    end
                    responseText = 'printresponse';
                    
                case 'gettime'
                    % Return the server's current time
                    currentTime = now;
                    fprintf('Sending current server time: %s\n', datestr(currentTime));
                    responseObj = struct('serverTime', currentTime, ...
                                         'timeString', datestr(currentTime), ...
                                         'timeZone', 'Local');
                    responseText = 'timeresponse';
                    
                case 'quit'
                    % Send confirmation and then stop the server
                    fprintf('Quit command received. Shutting down server...\n');
                    responseObj = struct('message', 'Server shutting down');
                    responseText = 'quitresponse';
                    sendObject(socket, responseObj, responseText);
                    break;
                    
                otherwise
                    % Unknown command
                    fprintf('Unknown command: %s\n', command);
                    responseObj = struct('error', true, ...
                                         'message', sprintf('Unknown command: %s', command), ...
                                         'validCommands', {'echo', 'print', 'gettime', 'quit'});
                    responseText = 'errorresponse';
            end
            
            % Send the response
            fprintf('Sending response: %s\n\n', responseText);
            sendObject(socket, responseObj, responseText);
        end
    catch ME
        fprintf('Error: %s\n', ME.message);
    end
    
    % Clean up
    socket.close();
    context.term();
    fprintf('Server stopped.\n');
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
    
    % Check if there are more parts (the object)
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