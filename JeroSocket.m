classdef JeroSocket < handle
    %Socket  Encapsulates a ZeroMQ socket using JeroMQ.
    %   The Socket class provides a high-level interface for interacting with
    %   ZeroMQ sockets in MATLAB using the JeroMQ library.

    properties (Access = private)
        %socketPointer  Reference to the underlying JeroMQ socket.
        socketPointer;
    end

    properties (Access = public)
        %bindings  Cell array of endpoints the socket is bound to.
        bindings
        %connections  Cell array of endpoints the socket is connected to.
        connections
        %defaultBufferLength  Default buffer length for receiving messages.
        defaultBufferLength
    end

    methods
        function obj = JeroSocket(contextPointer, socketType)
            %Socket  Constructs a Socket object.
            %   obj = Socket(contextPointer, socketType) creates a JeroMQ socket
            %   of the specified type within the given context.
            %
            %   Inputs:
            %       contextPointer - Pointer to the JeroMQ context.
            %       socketType   - Type of the socket (e.g., 'ZMQ_PUB', 'ZMQ_SUB').
            %
            %   Outputs:
            %       obj          - A Socket object.
            socketType = obj.normalize_const_name(socketType);
            
            % Convert socketType string to JeroMQ socket type constant
            switch socketType
                case 'ZMQ_REP'
                    zmqSocketType = org.zeromq.ZMQ.REP;
                case 'ZMQ_REQ'
                    zmqSocketType = org.zeromq.ZMQ.REQ;
                case 'ZMQ_PUB'
                    zmqSocketType = org.zeromq.ZMQ.PUB;
                case 'ZMQ_SUB'
                    zmqSocketType = org.zeromq.ZMQ.SUB;
                case 'ZMQ_PUSH'
                    zmqSocketType = org.zeromq.ZMQ.PUSH;
                case 'ZMQ_PULL'
                    zmqSocketType = org.zeromq.ZMQ.PULL;
                case 'ZMQ_PAIR'
                    zmqSocketType = org.zeromq.ZMQ.PAIR;
                case 'ZMQ_ROUTER'
                    zmqSocketType = org.zeromq.ZMQ.ROUTER;
                case 'ZMQ_DEALER'
                    zmqSocketType = org.zeromq.ZMQ.DEALER;
                case 'ZMQ_STREAM'
                    zmqSocketType = org.zeromq.ZMQ.STREAM;
                otherwise
                    error('Unsupported socket type: %s', socketType);
            end
            
            % Core API: Create the JeroMQ socket
            obj.socketPointer = contextPointer.socket(zmqSocketType);
            
            % Init properties
            obj.bindings = {};
            obj.connections = {};
            obj.defaultBufferLength = 2^19;
        end

        function bind(obj, endpoint)
            %bind  Binds the socket to a network endpoint.
            %   bind(obj, endpoint) binds the JeroMQ socket to the specified
            %   endpoint.
            %
            %   Inputs:
            %       obj      - A Socket object.
            %       endpoint - The network endpoint to bind to (e.g., 'tcp://*:5555').
            
            % Core API: Bind the JeroMQ socket
            obj.socketPointer.bind(endpoint);
            
            % Add endpoint to the tracked bindings
            % this is important to the cleanup process
            obj.bindings{end+1} = endpoint;
        end

        function connect(obj, endpoint)
            %connect  Connects the socket to a network endpoint.
            %   connect(obj, endpoint) connects the JeroMQ socket to the specified
            %   endpoint.
            %
            %   Inputs:
            %       obj      - A Socket object.
            %       endpoint - The network endpoint to connect to (e.g., 'tcp://localhost:5555').
            
            % Core API: Connect the JeroMQ socket
            obj.socketPointer.connect(endpoint);
            
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
           
            % Core API: Disconnect the JeroMQ socket
            obj.socketPointer.disconnect(endpoint);
            
            % Remove endpoint from the tracked connections
            % to avoid double cleaning
            index = find(strcmp(obj.connections, endpoint));
            obj.connections(index) = [];
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
            
            % Convert option name string to JeroMQ option type constant
            switch optName
                case 'ZMQ_RCVTIMEO'
                    zmqOptName = org.zeromq.ZMQ.RCVTIMEO;
                case 'ZMQ_SNDTIMEO'
                    zmqOptName = org.zeromq.ZMQ.SNDTIMEO;
				case 'ZMQ_RCVMORE'
					zmqOptName = org.zeromq.ZMQ.RCVMORE;
                otherwise
                    error('Unsupported option: %s', optName);
            end
            
            % Core API: Get the JeroMQ socket option
            option = obj.socketPointer.getSocketOpt(zmqOptName);
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
            
            % Core API: Receive a message from the JeroMQ socket
            bytes = obj.socketPointer.recv(0);
			
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
            if isa(data, 'uint8')
                data = typecast(int8(data), 'int8');
            elseif isa(data, 'char')
                data = int8(data);
            end
            
            % Determine if we should send more data
            if (nargin > 2) && sendMore
                flag = org.zeromq.ZMQ.SNDMORE;
            else
                flag = 0;
            end
            
            % Core API: Send the message using JeroMQ
            nbytes = obj.socketPointer.send(data, flag);
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
            
            % Convert option name string to JeroMQ option type constant
            switch optName
                case 'ZMQ_RCVTIMEO'
                    zmqOptName = org.zeromq.ZMQ.RCVTIMEO;
                case 'ZMQ_SNDTIMEO'
                    zmqOptName = org.zeromq.ZMQ.SNDTIMEO;
                case 'ZMQ_LINGER'
                    zmqOptName = org.zeromq.ZMQ.LINGER;
                otherwise
                    error('Unsupported option: %s', optName);
            end
            
            % Core API: Set the JeroMQ socket option
            obj.socketPointer.setSocketOpt(zmqOptName, value);
        end

        function unbind(obj, endpoint)
            %unbind  Unbinds the socket from a network endpoint.
            %   unbind(obj, endpoint) unbinds the JeroMQ socket from the specified
            %   endpoint.
            %
            %   Inputs:
            %       obj      - A Socket object.
            %       endpoint - The network endpoint to unbind from.
            
            % JeroMQ does not have an explicit unbind function.
            % This function only removes the endpoint from the tracked bindings.
            index = find(strcmp(obj.bindings, endpoint));
            obj.bindings(index) = [];
        end

        function close(obj)
            %close  Closes the socket.
            %   close(obj) closes the JeroMQ socket.
            %
            %   Inputs:
            %       obj - A Socket object.
            
            % Core API: Close the JeroMQ socket
            obj.socketPointer.close();
        end

        function delete(obj)
            %delete  Destructor for the Socket object.
            %   delete(obj) is the destructor for the Socket object. It closes the
            %   socket and releases any associated resources.
            
            if ~isempty(obj.socketPointer)
                % Disconnect/Unbind all the endpoints
                cellfun(@(b) obj.unbind(b), obj.bindings, 'UniformOutput', false);
                cellfun(@(c) obj.disconnect(c), obj.connections, 'UniformOutput', false);
                
                % Avoid linger time
                obj.set('linger', 0);
                
                % Close the socket
                obj.close();
            end
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
			
			% Core API: Check if there are more parts to receive
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
end
