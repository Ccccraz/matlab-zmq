# ZeroMQ MATLAB Examples

This directory contains examples demonstrating how to use ZeroMQ with MATLAB.

## Basic Examples

- `pub_server.m` and `sub_client.m`: Demonstrate the Publisher-Subscriber pattern
- `producer.m` and `consumer.m`: Demonstrate the Push-Pull pattern
- `collector.m`: Demonstrates how to collect messages from multiple sources

## Advanced Examples

- `object_server.m` and `object_client.m`: Demonstrate bidirectional communication with commands and serialized MATLAB objects
- `serialization_helper.m`: Contains utility functions for serializing and deserializing MATLAB objects
- `command_socket_demo.m`: Demonstrates using the `zmq.CommandSocket` class for command-based communication

## OO Interface Examples

- The `zmq.CommandSocket` class provides an object-oriented interface for command-based communication with serialized objects
- `command_socket_demo.m`: Shows how to use the CommandSocket class in both client and server mode

## Running the Examples

1. Start MATLAB
2. Navigate to this directory
3. Run the server example in one MATLAB session
4. Run the client example in another MATLAB session

For example, to run the interactive command-based serialization example:

```matlab
% In first MATLAB session
object_server()

% In second MATLAB session
object_client()
```

To run the CommandSocket demo:

```matlab
% In first MATLAB session
command_socket_demo('server')

% In second MATLAB session
command_socket_demo('client')
```

## Command-based Serialization Example

The `object_server.m` and `object_client.m` examples demonstrate an interactive command-based protocol with support for serialized MATLAB objects. The client can send commands to the server, and each command can include a serialized MATLAB object.

### Supported Commands:

- `echo`: Returns the object back to the sender
- `print`: Prints the received object in the command window
- `gettime`: Returns the current time of the receiver
- `quit`: Stops the server
- `exit`: (Client only) Exits the client without stopping the server

### How It Works:

1. The client sends a command with an optional serialized object
2. The server processes the command and sends back a response with its own serialized object
3. Commands and responses are sent as multipart ZeroMQ messages:
   - The first part is the text command
   - The second part is the serialized MATLAB object (optional)

### Serialization:

The serialization is done using MATLAB's built-in `getByteStreamFromArray` and `getArrayFromByteStream` functions, which can serialize any MATLAB object, including:

- Numeric arrays
- Cell arrays
- Structures
- Custom classes (must be in the MATLAB path)
- Character arrays and strings
- Logical arrays

The `serialization_helper.m` file provides utility functions that make it easy to send and receive serialized objects in your own applications.

## CommandSocket Class

The `zmq.CommandSocket` class provides a higher-level, object-oriented interface for command-based communication with serialized objects. It encapsulates both client and server behavior in a single class:

### Features:

- Can operate in either client or server mode
- Handles object serialization/deserialization automatically
- Provides callback mechanism for received messages
- Supports custom command handlers
- Includes default handlers for common commands (echo, print, gettime, quit)

### Usage Example:

```matlab
% Server mode
server = zmq.CommandSocket('server');
server.start();
server.processRequests();  % Processes requests until stopped

% Client mode
client = zmq.CommandSocket('client');
client.start();
client.connect('localhost');
[responseObj, responseCmd] = client.sendCommand('gettime', dataObj);
```

### Custom Command Handlers:

You can add your own command handlers to the CommandSocket:

```matlab
% Register a custom command on a server
server.registerCommand('status', @(socket, data) handleStatusCommand(socket, data));

% Example handler function
function handleStatusCommand(socket, data)
    % Process the command
    statusInfo = struct('status', 'online', 'uptime', '2:34:56');
    
    % Send a response
    socket.sendObject(statusInfo, 'statusresponse');
end
```

### Callbacks:

The CommandSocket class supports various callbacks:

```matlab
% Set a callback for all received commands
server.OnCommand = @(cmd, data) fprintf('Received command: %s\n', cmd);

% Set a callback for all received responses
client.OnResponse = @(cmd, data) fprintf('Received response: %s\n', cmd);

% Set an error callback
client.OnError = @(err) fprintf('Error: %s\n', err.message);
```

The `command_socket_demo.m` file provides a complete example of using the CommandSocket class in both client and server mode with custom commands and callbacks.