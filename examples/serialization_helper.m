function serialization_helper
    % Helper functions for MATLAB object serialization with ZeroMQ
    %
    % This file provides utility functions for sending and receiving
    % serialized MATLAB objects through ZeroMQ sockets.
    %
    % Example usage:
    %   context = zmq.Context();
    %   socket = context.socket('ZMQ_REQ');
    %   socket.connect('tcp://localhost:5557');
    %   
    %   % Send an object
    %   myData = struct('field1', 1, 'field2', 'test');
    %   sendObject(socket, myData, 'my data');
    %   
    %   % Receive an object
    %   [responseObj, responseText] = receiveObject(socket);
    
    % This is just a container for the helper functions
    % See the functions below for implementation details
end

function sendObject(socket, obj, text, options)
    % Send a serialized MATLAB object with an optional text message
    %
    % Parameters:
    %   socket - ZeroMQ socket object (zmq.Socket instance)
    %   obj - MATLAB object to serialize and send
    %   text - (optional) Text message to send as first part (default: '')
    %   options - (optional) Additional send options (default: {})
    
    if nargin < 3
        text = '';
    end
    
    if nargin < 4
        options = {};
    end
    
    % Serialize the object
    serializedObj = getByteStreamFromArray(obj);
    
    if ~isempty(text)
        % Send text as first part with SNDMORE flag
        socket.send(uint8(text), 'sndmore');
    end
    
    % Send serialized object
    socket.send(serializedObj, options{:});
end

function [obj, text] = receiveObject(socket, options)
    % Receive a serialized MATLAB object with an optional text message
    %
    % Parameters:
    %   socket - ZeroMQ socket object (zmq.Socket instance)
    %   options - (optional) Additional receive options (default: {})
    %
    % Returns:
    %   obj - Deserialized MATLAB object
    %   text - Text message received as first part (empty if no text part)
    
    if nargin < 2
        options = {};
    end
    
    % Initialize return values
    obj = [];
    text = '';
    
    % Receive the first part
    message = socket.recv(options{:});
    
    % Check if there are more parts
    hasMoreParts = socket.get('rcvmore');
    
    if hasMoreParts
        % First part is text, second part is object
        text = char(message);
        serializedObj = socket.recv(options{:});
    else
        % Only one part - it's the serialized object
        serializedObj = message;
    end
    
    % Deserialize the object
    try
        obj = getArrayFromByteStream(serializedObj);
    catch ME
        warning('Failed to deserialize object: %s', ME.message);
    end
end

function sendMultipartObject(socket, obj, text, chunkSize, options)
    % Send a large serialized MATLAB object with text using multipart transmission
    %
    % Parameters:
    %   socket - ZeroMQ socket object
    %   obj - MATLAB object to serialize and send
    %   text - (optional) Text message to send as first part (default: '')
    %   chunkSize - (optional) Size of each chunk in bytes (default: 8192)
    %   options - (optional) Additional send options (default: {})
    
    if nargin < 3
        text = '';
    end
    
    if nargin < 4
        chunkSize = 8192;  % Default to 8KB chunks
    end
    
    if nargin < 5
        options = {};
    end
    
    % Serialize the object
    serializedObj = getByteStreamFromArray(obj);
    
    if ~isempty(text)
        % Send text as first part with SNDMORE flag
        socket.send(uint8(text), 'sndmore');
    end
    
    % Send the serialized object using multipart
    socket.send_multipart(serializedObj, chunkSize, options{:});
end

function [obj, text] = receiveMultipartObject(socket, chunkSize, options)
    % Receive a large serialized MATLAB object with text using multipart transmission
    %
    % Parameters:
    %   socket - ZeroMQ socket object
    %   chunkSize - (optional) Size of each chunk in bytes (default: 8192)
    %   options - (optional) Additional receive options (default: {})
    %
    % Returns:
    %   obj - Deserialized MATLAB object
    %   text - Text message received as first part (empty if no text part)
    
    if nargin < 2
        chunkSize = 8192;  % Default to 8KB chunks
    end
    
    if nargin < 3
        options = {};
    end
    
    % Initialize return values
    obj = [];
    text = '';
    
    % Receive the first part
    message = socket.recv(options{:});
    
    % Check if there are more parts
    hasMoreParts = socket.get('rcvmore');
    
    if hasMoreParts
        % First part is text, second part is the start of multipart object
        text = char(message);
        
        % Receive the multipart object
        serializedObj = socket.recv_multipart(chunkSize, options{:});
    else
        % Only one part or start of multipart - try to receive as multipart
        if socket.get('rcvmore')
            serializedObj = socket.recv_multipart(chunkSize, options{:});
        else
            serializedObj = message;
        end
    end
    
    % Deserialize the object
    try
        obj = getArrayFromByteStream(serializedObj);
    catch ME
        warning('Failed to deserialize object: %s', ME.message);
    end
end