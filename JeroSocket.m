classdef JeroSocket < handle
	%Socket  Encapsulates a ZeroMQ socket using JeroMQ ZSocket.
	%   The Socket class provides a high-level interface for interacting with
	%   ZeroMQ sockets in MATLAB using the JeroMQ ZSocket class.

	properties (GetAccess = public, SetAccess = private)
		%socketPointer  Reference to the underlying JeroMQ ZSocket.
		socketPointer
	end

	properties (Access = public)
		%bindings  Cell array of endpoints the socket is bound to.
		bindings = {}
		%connections  Cell array of endpoints the socket is connected to.
		connections = {}
		%defaultBufferLength  Default buffer length for receiving messages.
		defaultBufferLength = 2^20
		sendTimeout = 10000
		receiveTimeout = 10000
		linger = 0
	end

	methods
		function obj = JeroSocket(contextPointer, socketType)
			%Socket  Constructs a Socket object.
			%   obj = Socket(contextPointer, socketType) creates a JeroMQ socket
			%   of the specified type within the given context.
			%
			%   Inputs:
			%       contextPointer - Pointer to the JeroMQ ZContext.
			%       socketType   - Type of the socket (e.g., 'REP', 'REQ', 'PUB', 'SUB').
			%                      Can be a string or org.zeromq.SocketType enum value.
			%
			%   Outputs:
			%       obj          - A Socket object.
			
			% Convert socketType string to SocketType enum if it's a string
			if ischar(socketType) || isstring(socketType)
				socketType = char(socketType);
				socketType = strrep(upper(socketType), 'ZMQ_', '');
				
				% Map string to SocketType enum
				try
					zmqSocketType = org.zeromq.SocketType.valueOf(socketType);
				catch
					error('Unsupported socket type: %s', socketType);
				end
			elseif isa(socketType, 'org.zeromq.SocketType')
				% Already a SocketType enum
				zmqSocketType = socketType;
			else
				error('socketType must be a string or org.zeromq.SocketType enum');
			end

			% Create the JeroMQ ZSocket
			obj.socketPointer = contextPointer.createSocket(zmqSocketType);
			obj.set('ZMQ_RCVBUF',obj.defaultBufferLength);
			obj.set('ZMQ_SNDTIMEO',obj.sendTimeout);
			obj.set('ZMQ_RCVTIMEO',obj.receiveTimeout);
			obj.set('ZMQ_LINGER', obj.linger);
		end

		function bind(obj, endpoint)
			%bind  Binds the socket to a network endpoint.
			%   bind(obj, endpoint) binds the JeroMQ socket to the specified
			%   endpoint.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       endpoint - The network endpoint to bind to (e.g., 'tcp://*:5555').

			% Bind the JeroMQ ZSocket
			obj.socketPointer.bind(endpoint);

			% Add endpoint to the tracked bindings
			% this is important to the cleanup process
			obj.bindings{end+1} = endpoint;
		end

		function unbind(obj, endpoint)
			%unbind  Unbinds the socket from a network endpoint.
			%   unbind(obj, endpoint) unbinds the JeroMQ socket from the specified
			%   endpoint.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       endpoint - The network endpoint to unbind from.

			% Unbind the JeroMQ ZSocket
			obj.socketPointer.unbind(endpoint);

			% Remove the endpoint from the tracked bindings
			index = find(strcmp(obj.bindings, endpoint));
			obj.bindings(index) = [];
		end

		function connect(obj, endpoint)
			%connect  Connects the socket to a network endpoint.
			%   connect(obj, endpoint) connects the JeroMQ socket to the specified
			%   endpoint.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       endpoint - The network endpoint to connect to (e.g., 'tcp://localhost:5555').

			% Connect the JeroMQ ZSocket
			obj.socketPointer.connect(endpoint);
			
			% Set default receive timeout
			obj.socketPointer.setReceiveTimeOut(10000);

			% Add endpoint to the tracked connections
			% this is important to the cleanup process
			obj.connections{end+1} = endpoint;
		end

		function disconnect(obj, endpoint)
			%disconnect  Disconnects the socket from a network endpoint.
			%   disconnect(obj, endpoint) disconnects the JeroMQ socket from the specified
			%   endpoint.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       endpoint - The network endpoint to disconnect from.

			% Disconnect the JeroMQ ZSocket
			obj.socketPointer.disconnect(endpoint);

			% Remove endpoint from the tracked connections
			% to avoid double cleaning
			index = find(strcmp(obj.connections, endpoint));
			obj.connections(index) = [];
		end

		function set(obj, name, value)
			%set  Sets a socket option.
			%   set(obj, name, value) sets the value of the specified socket
			%   option.
			%
			%   Inputs:
			%       obj   - A Socket object.
			%       name  - The name of the socket option (e.g., 'RCVTIMEO').
			%       value - The value to set for the option.
			optName = obj.normalize_const_name(name);

			% Set the socket option based on the name
			switch optName
				case 'ZMQ_RCVBUF'
					obj.socketPointer.setReceiveBufferSize(value);
				case 'ZMQ_RCVTIMEO'
					obj.socketPointer.setReceiveTimeOut(value);
				case 'ZMQ_SNDTIMEO'
					obj.socketPointer.setSendTimeOut(value);
				case 'ZMQ_LINGER'
					obj.socketPointer.setLinger(value);
				otherwise
					warning('Unsupported option: %s', optName);
			end
		end

		function option = get(obj, name)
			%get  Gets a socket option.
			%   option = get(obj, name) retrieves the value of the specified
			%   socket option.
			%
			%   Inputs:
			%       obj  - A Socket object.
			%       name - The name of the socket option (e.g., 'RCVTIMEO').
			%
			%   Outputs:
			%       option - The value of the socket option.
			optName = obj.normalize_const_name(name);

			% Get the socket option based on the name
			switch optName
				case 'ZMQ_RCVTIMEO'
					option = obj.socketPointer.getReceiveTimeOut();
				case 'ZMQ_SNDTIMEO'
					option = obj.socketPointer.getSendTimeOut();
				case 'ZMQ_RCVMORE'
					option = obj.socketPointer.hasReceiveMore();
				otherwise
					error('Unsupported option: %s', optName);
			end
		end

		function message = recv_multipart(obj, varargin)
			%recv_multipart  Receives a multipart message.
			%   message = recv_multipart(obj, varargin) receives a multipart
			%   message from the socket.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       varargin - Optional arguments for receiving the message.
			%
			%   Outputs:
			%       message  - A cell array containing the message parts.

			message = {};

			% Receive all parts of the multipart message
			while true
				% Receive a single message part
				part = obj.recv();

				% Add the part to the message
				message = [message {part}];

				% Check if there are more parts to receive
				if ~obj.hasReceiveMore()
					break;
				end
			end
		end

		function message = recv_string(obj, varargin)
			%recv_string  Receives a message as a string.
			%   message = recv_string(obj, varargin) receives a message from the
			%   socket and converts it to a string.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       varargin - Optional arguments for receiving the message.
			%
			%   Outputs:
			%       message  - The received message as a string.

			% Receive the multipart message
			messageParts = obj.recv_multipart(varargin{:});

			% Concatenate the message parts into a single string
			message = char([messageParts{:}]);
		end

		function msg = recv(obj)
			%recv  Receives a message.
			%   message = recv(obj, varargin) receives a message from the socket.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       varargin - Optional arguments for receiving the message.
			%
			%   Outputs:
			%       message  - The received message.

			% Receive a message from the JeroMQ ZSocket
			bytes = obj.socketPointer.recv();

			if ~isempty(bytes)
				msg = uint8(typecast(bytes, 'int8'));
			else
				msg = [];
			end
		end

		function send_multipart(obj, message, varargin)
			%send_multipart  Sends a multipart message.
			%   send_multipart(obj, message, varargin) sends a multipart message
			%   through the socket.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       message  - cell array / int8 array containing the message parts to send.
			%       varargin - Optional arguments for sending the message.

			if iscell(message)
				% Send each part of the message
				for i = 1:length(message)
					% Get the current message part
					part = message{i};

					% Check if it is the last part
					isLastPart = (i == length(message));

					% Send the message part
					obj.send(part, ~isLastPart);
				end
			else
				% If message is not a cell, treat it as a single part message
				obj.send(message, false);
			end
		end

		function send_string(obj, message, varargin)
			%send_string  Sends a string message.
			%   send_string(obj, message, varargin) sends a string message
			%   through the socket.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       message  - The string to send.
			%       varargin - Optional arguments for sending the message.

			% Convert the string to a byte array
			data = uint8(message);

			% Send the byte array
			obj.send(data, false);
		end

		function nbytes = send(obj, data, sendMore)
			%send  Sends a message.
			%   send(obj, data, varargin) sends a message through the socket.
			%
			%   Inputs:
			%       obj      - A Socket object.
			%       data     - The data to send.
			%       varargin - Optional arguments for sending the message.
			%
			%   Outputs:
			%       nbytes   - The number of bytes sent.

			% Convert data to byte array
			if isa(data, 'int8')
				data = typecast(uint8(data), 'uint8');
			elseif isa(data, 'char')
				data = uint8(data);
			end

			% Determine if we should send more data
			if (nargin > 2) && sendMore
				flag = org.zeromq.ZMQ.SNDMORE;
			else
				flag = 0;
			end

			% Send the message using JeroMQ ZSocket
			nbytes = obj.socketPointer.send(data, flag);
		end

		function close(obj)
			%close  Closes the socket.
			%   close(obj) closes the JeroMQ socket.
			%
			%   Inputs:
			%       obj - A Socket object.

			if ~isempty(obj.socketPointer)
				% Disconnect/Unbind all the endpoints
				cellfun(@(b) obj.unbind(b), obj.bindings, 'UniformOutput', false);
				cellfun(@(c) obj.disconnect(c), obj.connections, 'UniformOutput', false);

				% Avoid linger time
				obj.socketPointer.setLinger(0);

				% Close the socket
				obj.socketPointer.close();
			end
		end

		function delete(obj)
			%delete  Destructor for the Socket object.
			%   delete(obj) is the destructor for the Socket object. It closes the
			%   socket and releases any associated resources.

			obj.close();
		end

		function result = hasReceiveMore(obj)
			%hasReceiveMore  Checks if there are more parts to receive in a multipart message.
			%   result = hasReceiveMore(obj) checks if there are more parts to receive
			%   in a multipart message.
			%
			%   Inputs:
			%       obj - A Socket object.
			%
			%   Outputs:
			%       result - True if there are more parts to receive, false otherwise.

			% Check if there are more parts to receive
			result = obj.socketPointer.hasReceiveMore();
		end
	end

	methods (Access = protected)
		function normalized = normalize_const_name(~, name)
			%normalize_const_name  Normalizes a constant name.
			%   normalized = normalize_const_name(name) converts a constant name
			%   to a normalized form (e.g., 'rcvtimeo' to 'ZMQ_RCVTIMEO').
			%
			%   Inputs:
			%       name - The constant name to normalize.
			%
			%   Outputs:
			%       normalized - The normalized constant name.
			normalized = strrep(upper(name), 'ZMQ_', '');
			normalized = strcat('ZMQ_', normalized);
		end
	end
	
	methods (Static)
		function socketTypes = availableSocketTypes()
			%availableSocketTypes Returns all available socket types from SocketType enum
			%   socketTypes = availableSocketTypes() returns a cell array of strings
			%   representing all available socket types in the SocketType enum.
			
			% Get all SocketType enum values
			javaSocketTypes = org.zeromq.SocketType.values();
			
			% Convert to cell array of strings
			socketTypes = cell(length(javaSocketTypes), 1);
			for i = 1:length(javaSocketTypes)
				socketTypes{i} = char(javaSocketTypes(i).name());
			end
		end
	end
end
