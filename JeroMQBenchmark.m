classdef JeroMQBenchmark < handle
	% JeroMQBenchmark A class for benchmarking ZeroMQ frame sizes using JeroMQ
	% Requires JeroMQ: https://github.com/jeromq/jeromq | https://javadoc.io/doc/org.zeromq/jeromq/latest/index.html
	% and the jeromq-0.6.0.jar file added to the javaclasspath
	% Sample results:
	% === BENCHMARK RESULTS ===
	% Benchmark for 128 byte header and 1048576 bytes data
	% Chunk Size (bytes)   # Frames   Avg Latency (ms)     Avg Throughput (Mbps)
	% ----------------------------------------------------------------------
	% 512                  2049       322.53               26.03
	% 1024                 1025       153.76               54.58
	% 8192                 129        25.41                330.23
	% 32768                33         11.33                771.22
	% 65536                17         9.36                 915.93
	% 131072               9          7.08                 1338.52
	% 262144               5          6.59                 1365.91
	% 524288               3          5.25                 1755.56
	% 1048576              2          6.26                 1387.05
	% === SUMMARY ===
	% Lowest latency: 524288 bytes (5.25ms)
	% Highest throughput: 524288 bytes (1755.56Mbps)
	
	properties
		% Configuration parameters
		Port = 5555
		IP   = 'localhost'
		HeaderSize = 2^7  % 128 bytes
		DataSize = 2^20
		BufferSize = 2^20
		NumRuns = 5
		ChunkSizes = [2^9, 2^10, 2^13, 2^15, 2^16, 2^17, 2^18, 2^19, 2^20]
		
		% Results storage
		Results = struct('chunk_size', {}, 'num_frames', {}, 'latency_ms', {}, 'throughput_mbps', {})
		
		 % JeroMQ Java objects
		Context
		Socket
		IsServer = false
		Running = false
	end
	
	methods
		function obj = JeroMQBenchmark(varargin)
			% Constructor with optional parameter overrides
			% Usage: benchmark = JeroMQBenchmark('Port', 5556, 'DataSize', 1000000)
			
			% Parse named parameters
			for i = 1:2:length(varargin)
				if isprop(obj, varargin{i})
					obj.(varargin{i}) = varargin{i+1};
				else
					error('Property %s not found', varargin{i});
				end
			end
			
			 % Add JeroMQ jar to javaclasspath if not already present
			if ~any(contains(javaclasspath, 'jeromq-0.6.0.jar'))
				javaaddpath('jeromq-0.6.0.jar','-begin');
				fprintf('Added JeroMQ jar to javaclasspath.\n');
			end
			
			% Initialize JeroMQ context
			obj.Context = JeroContext();
		end
		
		function delete(obj)
			% Destructor to clean up JeroMQ resources
			obj.stopServer();  % Stop the server if running
			
			if ~isempty(obj.Socket)
				fprintf('Socket stopped.\n');
				obj.Socket.close();
			end
			
			if ~isempty(obj.Context)
				fprintf('Context terminated.\n');
				obj.Context.delete();
			end
		end
		
		function startServer(obj)
			% Start a JeroMQ server in this instance
			if ~obj.IsServer
				% Create and bind socket
				obj.Socket = obj.Context.socket('REP');
				obj.Socket.set('ZMQ_RCVBUF',obj.BufferSize);
				obj.Socket.set('ZMQ_RCVTIMEO', -1);
				obj.Socket.set('ZMQ_SNDTIMEO', -1);
				obj.Socket.bind(['tcp://' obj.IP ':' num2str(obj.Port)]);
				
				fprintf('Server running on port %d. Use Ctrl+C to stop.\n', obj.Port);
				
				obj.IsServer = true;
				obj.Running = true;
				
				% Run server loop
				try
					while obj.Running
						% Receive multipart message
						message = obj.recvMultipart(obj.Socket);
						if ~isempty(message)
							fprintf('Received %d frames\n', length(message));
							if iscell(message) && ischar(message{1}) && contains(char(message{1}),'exit')
								fprintf('Got exit message.\n');
								obj.sendMultipart(obj.Socket,{'ok'});
								obj.stopServer;
							end
							% Echo back the message
							obj.sendMultipart(obj.Socket,message);
						end
					end
				catch e
					fprintf('Server stopped: %s %s\n', e.identifier, e.message);
					getReport(e);
					obj.stopServer();
				end
			else
				fprintf('Server is already running\n');
			end
		end
		
		function stopServer(obj)
			% Stop the server if it's running
			if obj.IsServer
				obj.Socket.close();
				obj.IsServer = false;
				fprintf('Server stopped.\n');
			end
			obj.Running = false;
		end
		
		function results = runBenchmark(obj)
			% Run the benchmark with the configured settings
			
			% Check if we need to start a server or provide instructions
			if ~obj.IsServer
				obj.displayServerInstructions();
			else
				error('Cannot run benchmark in server mode. Create a separate client instance.');
			end
			
			% Display benchmark configuration
			fprintf('\nStarting benchmark with %d byte header and %.1f KB data\n', ...
				obj.HeaderSize, obj.DataSize/1000);
			fprintf('Running %d tests per chunk size\n\n', obj.NumRuns);
			
			% Generate test data
			header = uint8(repmat('H', 1, obj.HeaderSize));
			data = uint8(repmat('D', 1, obj.DataSize));
			
			% Run benchmarks for each chunk size
			for i = 1:length(obj.ChunkSizes)
				chunk_size = obj.ChunkSizes(i);
				fprintf('Benchmarking chunk size: %d bytes\n', chunk_size);
				
				obj.benchmarkChunkSize(header, data, chunk_size, i);
			end
			
			% Display results
			obj.displayResults();
			obj.plotResults();
			
			% Return the results
			results = obj.Results;
		end
		
		function benchmarkChunkSize(obj, header, data, chunk_size, result_index)
			% Benchmark a specific chunk size
			
			run_latencies = zeros(1, obj.NumRuns);
			run_throughputs = zeros(1, obj.NumRuns);
			
			% Split data into chunks and prepare frames
			chunks = {};
			for j = 1:chunk_size:length(data)
				end_idx = min(j + chunk_size - 1, length(data));
				chunks{end+1} = data(j:end_idx);
			end
			
			num_frames = length(chunks) + 1;  % +1 for header
			
			fprintf('Benchmarking number of frames: %i\n', num_frames);
			
			% Calculate total bytes to be sent
			total_bytes = length(header);
			for j = 1:length(chunks)
				total_bytes = total_bytes + length(chunks{j});
			end
			
			% Run multiple tests for this chunk size
			for run = 1:obj.NumRuns
				% Create and connect socket for this run
				socket = obj.Context.socket('REQ');
				socket.set('ZMQ_RCVBUF',obj.BufferSize);
				socket.set('ZMQ_RCVTIMEO', -1);
				socket.set('ZMQ_SNDTIMEO', -1);
				socket.connect(['tcp://' obj.IP ':' num2str(obj.Port)]);

				% Prepare message frames
				frames = [{header} chunks];
				
				% Warm-up round
				obj.sendMultipart(socket, frames);
				received = obj.recvMultipart(socket);

				if length(frames) ~= length(received)
					socket.close()
					break
				end
				
				% Test round
				tic;
				obj.sendMultipart(socket, frames);
				received = obj.recvMultipart(socket);
				elapsed_time = toc;
				
				% Calculate metrics
				latency_ms = elapsed_time * 1000;
				throughput_mbps = (total_bytes * 8 / 1000000) / elapsed_time;
				
				run_latencies(run) = latency_ms;
				run_throughputs(run) = throughput_mbps;
				
				fprintf('  Run %d: Latency=%.2fms, Throughput=%.2fMbps\n', ...
					run, latency_ms, throughput_mbps);
				
				% Close socket
				socket.close();
				pause(0.5);  % Brief pause between runs
			end
			
			% Store average results
			result = struct(...
				'chunk_size', chunk_size, ...
				'num_frames', num_frames, ...
				'latency_ms', mean(run_latencies), ...
				'throughput_mbps', mean(run_throughputs));
			
			obj.Results(result_index) = result;
		end
		
		function displayResults(obj)
			obj.quitServer()
			% Display the benchmark results in a table format
			disp('=== BENCHMARK RESULTS ===');
			fprintf('Benchmark for %i byte header and %i bytes data\n', ...
				obj.HeaderSize, obj.DataSize);
			fprintf('%-20s %-10s %-20s %-20s\n', 'Chunk Size (bytes)', '# Frames', 'Avg Latency (ms)', 'Avg Throughput (Mbps)');
			disp(repmat('-', 1, 70));
			
			for i = 1:length(obj.Results)
				fprintf('%-20d %-10d %-20.2f %-20.2f\n', ...
					obj.Results(i).chunk_size, ...
					obj.Results(i).num_frames, ...
					obj.Results(i).latency_ms, ...
					obj.Results(i).throughput_mbps);
			end
			
			% Find best results
			[~, min_latency_idx] = min([obj.Results.latency_ms]);
			[~, max_throughput_idx] = max([obj.Results.throughput_mbps]);
			
			disp('=== SUMMARY ===');
			fprintf('Lowest latency: %d bytes (%.2fms)\n', ...
				obj.Results(min_latency_idx).chunk_size, obj.Results(min_latency_idx).latency_ms);
			fprintf('Highest throughput: %d bytes (%.2fMbps)\n', ...
				obj.Results(max_throughput_idx).chunk_size, obj.Results(max_throughput_idx).throughput_mbps);
		end

		function quitServer(obj)
			socket = obj.Context.socket('REQ');
			socket.connect(['tcp://' obj.IP ':' num2str(obj.Port)]);
			frames = {'exit',1};
			obj.sendMultipart(socket, frames);
			received = obj.recvMultipart(socket);
			socket.close();
		end
		
		function plotResults(obj)
			% Plot the benchmark results
			
			figure;
			
			subplot(2, 1, 1);
			plot([obj.Results.chunk_size], [obj.Results.latency_ms], 'o-', 'LineWidth', 2);
			set(gca, 'XScale', 'log');
			xlabel('Chunk Size (bytes)');
			ylabel('Latency (ms)');
			title('ZeroMQ Frame Size vs. Latency');
			grid on;
			
			subplot(2, 1, 2);
			plot([obj.Results.chunk_size], [obj.Results.throughput_mbps], 'o-', 'LineWidth', 2);
			set(gca, 'XScale', 'log');
			xlabel('Chunk Size (bytes)');
			ylabel('Throughput (Mbps)');
			title('ZeroMQ Frame Size vs. Throughput');
			grid on;
			
			sgtitle('ZeroMQ Frame Size Benchmark Results');
		end
		
		function sendMultipart(obj, socket, frames)
			% Send a multipart message using JeroMQ
			if ~exist('socket','var') || isempty(socket); socket = obj.Socket; end
			if ~exist('frames','var') || isempty(frames); frames = {1:3,2:4,3:5}; end
			for i = 1:length(frames)
				if i < length(frames)
					socket.send(frames{i}, org.zeromq.ZMQ.SNDMORE);
				else
					socket.send(frames{i}, 0);
				end
			end
		end
		
		function received = recvMultipart(obj, socket)
			% Receive a multipart message using JeroMQ
			if ~exist('socket','var') || isempty(socket); socket = obj.Socket; end
			if isempty(socket); warning('No socket'); return; end
			received = {};
			while true
				frame = socket.recv();
				if ~isempty(frame)
					received{end+1} = frame;
					if ~socket.hasReceiveMore(); break; end
				else
					break;
				end
			end
		end

		function displayServerInstructions(obj)
			% Display instructions for starting a server in another MATLAB instance
			fprintf('To run the server, start another MATLAB instance and run:\n');
			fprintf('server = JeroMQBenchmark(''Port'', %d);\n', obj.Port);
			fprintf('server.startServer();\n');
			input('Press Enter when the server is running...');
		end
	end
	
	methods(Static)
		function [client, server] = createClientServerPair(port)
			% Create a client and server pair for testing
			% Note: This only works if you have parallel computing toolbox
			if nargin < 1
				port = 5555;
			end
			
			% Create server instance
			server = JeroMQBenchmark('Port', port);
			
			% Start server in background task
			serverFuture = parfeval(@server.startServer, 0);
			
			% Wait a moment for server to start
			pause(1);
			
			% Create client instance
			client = JeroMQBenchmark('Port', port);
			
			fprintf('Client and server pair created.\n');
			fprintf('Use client.runBenchmark() to run the benchmark.\n');
			fprintf('After completion, use cancel(serverFuture) to stop the server.\n');
		end
	end
end