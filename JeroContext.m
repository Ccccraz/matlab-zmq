classdef JeroContext < handle
    %Context  Encapsulates a ZeroMQ context using JeroMQ.

    properties (Access = private)
        %contextPointer  Reference to the underlying JeroMQ context.
        contextPointer
        %spawnedSockets  Cell array to track spawned sockets.
        spawnedSockets
    end

    methods
        function obj = JeroContext(varargin)
            %Context  Constructs a Context object.
            %   obj = Context() creates a JeroMQ context.
            
            if (nargin ~= 0)
                warning('zmq:Context:extraConstructArgs','Extraneous constructor arguments.');
            end
            
            % Core API: Create a JeroMQ context
            obj.contextPointer = org.zeromq.ZMQ.context(1);
            
            % Initi properties
            obj.spawnedSockets = {};
        end

        function delete(obj)
            %delete  Destructor for the Context object.
            %   delete(obj) is the destructor for the Context object. It terminates
            %   the context and releases any associated resources.
            
            if ~isempty(obj.contextPointer)
                % Delete all spawned sockets
                for n = 1:length(obj.spawnedSockets)
                    socketObj = obj.spawnedSockets{n};
                    if (isvalid(socketObj))
                        socketObj.delete();
                    end
                end
                
                % Terminate the context
                obj.term();
            end
        end

        function ptr = get_ptr(obj)
            %get_ptr  Returns the underlying JeroMQ context.
            %   ptr = get_ptr(obj) returns the underlying JeroMQ context.
            
            ptr = obj.contextPointer;
        end

        function option = get(obj, name)
           %get  Gets a context option.
            %   option = get(obj, name) retrieves the value of the specified
            %   context option.
            %
            %   Inputs:
            %       obj  - A Context object.
            %       name - The name of the context option (e.g., 'IO_THREADS').
            %
            %   Outputs:
            %       option - The value of the context option.
            optName = obj.normalize_const_name(name);
            
             % Convert option name string to JeroMQ option type constant
            switch optName
                case 'ZMQ_IO_THREADS'
                    zmqOptName = org.zeromq.ZMQ.IO_THREADS;
                otherwise
                    error('Unsupported option: %s', optName);
            end
            
            % Core API: Get the JeroMQ context option
            option = obj.contextPointer.getContextOpt(zmqOptName);
        end

        function set(obj, name, value)
            %set  Sets a context option.
            %   set(obj, name, value) sets the value of the specified context
            %   option.
            %
            %   Inputs:
            %       obj   - A Context object.
            %       name  - The name of the context option (e.g., 'IO_THREADS').
            %       value - The value to set for the option.
            optName = obj.normalize_const_name(name);
            
            % Convert option name string to JeroMQ option type constant
            switch optName
                case 'ZMQ_IO_THREADS'
                    zmqOptName = org.zeromq.ZMQ.IO_THREADS;
                otherwise
                    error('Unsupported option: %s', optName);
            end
            
            % Core API: Set the JeroMQ context option
            obj.contextPointer.setContextOpt(zmqOptName, value);
        end

        function newSocket = socket(obj, socketType)
            %socket  Creates a new socket within the context.
            %   newSocket = socket(obj, socketType) creates a new socket of the
            %   specified type within the context.
            %
            %   Inputs:
            %       obj        - A Context object.
            %       socketType - The type of the socket to create (e.g., 'ZMQ_REP', 'ZMQ_REQ').
            %
            %   Outputs:
            %       newSocket  - A Socket object representing the new socket.
            
            % Create a new JeroMQ Socket object
            newSocket = JeroSocket(obj.contextPointer, socketType);
            
            % Keep tracking of spawned sockets
            % this is important to the cleanup process
            obj.spawnedSockets{end+1} = newSocket;
        end

        function term(obj)
            %term  Terminates the context.
            %   term(obj) terminates the context and releases any associated
            %   resources.
            
            % Core API: Terminate the JeroMQ context
            obj.contextPointer.term();
			obj.contextPointer.close();
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
