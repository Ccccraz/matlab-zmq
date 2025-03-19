% ZeroMQ Frame Size Benchmark for MATLAB
% Requires https://github.com/fagg/matlab-zmq

function benchmark(type)
	if strcmpi(type,'server')
		run_zmq_server(5555)
	else
		benchmark_zmq_frame_sizes()
	end
end

function results = benchmark_zmq_frame_sizes()
    % Configuration parameters
    port = 5555;
    header_size = 100;
    data_size = 500000;  % 500 KB
    num_runs = 5;
    
    % Test various chunk sizes
    chunk_sizes = [
        1024,       % 1KB
        8192,       % 8KB
        16384,      % 16KB
        32768,      % 32KB
        65536,      % 64KB
        131072,     % 128KB
        262144,     % 256KB
        524288      % 512KB (single frame for data)
    ];
    
    % Initialize results structure
    results = struct('chunk_size', {}, 'num_frames', {}, 'latency_ms', {}, 'throughput_mbps', {});
    
    % Create ZeroMQ context
    context = zmq.core.ctx_new();
    
    % Start server in a separate MATLAB instance
    disp('Starting server...');
    disp('To run the server, start another MATLAB instance and run:');
    disp(['run_zmq_server(' num2str(port) ');']);
    input('Press Enter when the server is running...');
    
    % Generate test data
    header = uint8(repmat('H', 1, header_size));
    data = uint8(repmat('D', 1, data_size));
    
    fprintf('\nStarting benchmark with %d byte header and %.1f KB data\n', header_size, data_size/1000);
    fprintf('Running %d tests per chunk size\n\n', num_runs);
    
    % Run benchmarks for each chunk size
    for i = 1:length(chunk_sizes)
        chunk_size = chunk_sizes(i);
        fprintf('Benchmarking chunk size: %d bytes\n', chunk_size);
        
        run_latencies = zeros(1, num_runs);
        run_throughputs = zeros(1, num_runs);
        
        % Split data into chunks and prepare frames
        chunks = {};
        for j = 1:chunk_size:length(data)
            end_idx = min(j + chunk_size - 1, length(data));
            chunks{end+1} = data(j:end_idx);
        end
        
        num_frames = length(chunks) + 1;  % +1 for header
        
        % Calculate total bytes to be sent
        total_bytes = header_size;
        for j = 1:length(chunks)
            total_bytes = total_bytes + length(chunks{j});
        end
        
        % Run multiple tests for this chunk size
        for run = 1:num_runs
            % Create and connect socket for this run
            socket = zmq.core.socket(context, 'ZMQ_REQ');
            zmq.core.connect(socket, ['tcp://localhost:' num2str(port)]);
            
            % Warm-up round
            send_multipart_message(socket, header, chunks);
            receive_multipart_message(socket);
            
            % Test round
            tic;
            send_multipart_message(socket, header, chunks);
            receive_multipart_message(socket);
            elapsed_time = toc;
            
            % Calculate metrics
            latency_ms = elapsed_time * 1000;
            throughput_mbps = (total_bytes * 8 / 1000000) / elapsed_time;
            
            run_latencies(run) = latency_ms;
            run_throughputs(run) = throughput_mbps;
            
            fprintf('  Run %d: Latency=%.2fms, Throughput=%.2fMbps\n', ...
                run, latency_ms, throughput_mbps);
            
            % Close socket
            zmq.core.close(socket);
            pause(0.5);  % Brief pause between runs
        end
        
        % Store average results
        result = struct(...
            'chunk_size', chunk_size, ...
            'num_frames', num_frames, ...
            'latency_ms', mean(run_latencies), ...
            'throughput_mbps', mean(run_throughputs));
        
        results(i) = result;
    end
    
    % Clean up
    zmq.core.ctx_shutdown(context);
    zmq.core.ctx_term(context);
    
    % Print results table
    disp('=== BENCHMARK RESULTS ===');
    fprintf('%-20s %-10s %-20s %-20s\n', 'Chunk Size (bytes)', '# Frames', 'Avg Latency (ms)', 'Avg Throughput (Mbps)');
    disp(repmat('-', 1, 70));
    
    for i = 1:length(results)
        fprintf('%-20d %-10d %-20.2f %-20.2f\n', ...
            results(i).chunk_size, ...
            results(i).num_frames, ...
            results(i).latency_ms, ...
            results(i).throughput_mbps);
    end
    
    % Find best results
    [~, min_latency_idx] = min([results.latency_ms]);
    [~, max_throughput_idx] = max([results.throughput_mbps]);
    
    disp('=== SUMMARY ===');
    fprintf('Lowest latency: %d bytes (%.2fms)\n', ...
        results(min_latency_idx).chunk_size, results(min_latency_idx).latency_ms);
    fprintf('Highest throughput: %d bytes (%.2fMbps)\n', ...
        results(max_throughput_idx).chunk_size, results(max_throughput_idx).throughput_mbps);
    
    % Plot results
    figure;
    
    subplot(2, 1, 1);
    plot([results.chunk_size], [results.latency_ms], 'o-', 'LineWidth', 2);
    set(gca, 'XScale', 'log');
    xlabel('Chunk Size (bytes)');
    ylabel('Latency (ms)');
    title('ZeroMQ Frame Size vs. Latency');
    grid on;
    
    subplot(2, 1, 2);
    plot([results.chunk_size], [results.throughput_mbps], 'o-', 'LineWidth', 2);
    set(gca, 'XScale', 'log');
    xlabel('Chunk Size (bytes)');
    ylabel('Throughput (Mbps)');
    title('ZeroMQ Frame Size vs. Throughput');
    grid on;
    
    sgtitle('ZeroMQ Frame Size Benchmark Results');
end

% Helper function to send multipart message
function send_multipart_message(socket, header, chunks)
    % Send header with more flag
    zmq.core.send(socket, header, 'ZMQ_SNDMORE');
    
    % Send all data chunks except the last one with more flag
    for i = 1:length(chunks)-1
        zmq.core.send(socket, chunks{i}, 'ZMQ_SNDMORE');
    end
    
    % Send the last chunk with no more flag
    if ~isempty(chunks)
        zmq.core.send(socket, chunks{end});
    else
        % If there are no chunks, send empty message to complete the send
        zmq.core.send(socket, uint8([]));
    end
end

% Helper function to receive multipart message
function frames = receive_multipart_message(socket)
    frames = {};
    
    % Receive first part
    [frames{1}, more] = zmq.core.recv(socket);
    
    % Continue receiving parts while more flag is set
    while more
        [frames{end+1}, more] = zmq.core.recv(socket);
    end
end

% Server function to be run in a separate MATLAB instance
function run_zmq_server(port)
    disp(['Starting ZeroMQ server on port ' num2str(port) '...']);
    
    % Create context and socket
    context = zmq.core.ctx_new();
    socket = zmq.core.socket(context, 'ZMQ_REP');
    zmq.core.bind(socket, ['tcp://*:' num2str(port)]);
    
    disp('Server running. Press Ctrl+C to stop.');
    
    try
        while true
            % Receive multipart message
            frames = {};
            [frames{1}, more] = zmq.core.recv(socket);
            
            % Continue receiving parts while more flag is set
            while more
                [frames{end+1}, more] = zmq.core.recv(socket);
            end
            
            fprintf('Received %d frames\n', length(frames));
            
            % Echo back the message
            for i = 1:length(frames)-1
                zmq.core.send(socket, frames{i}, 'ZMQ_SNDMORE');
            end
            zmq.core.send(socket, frames{end});
        end
    catch e
        disp('Server stopped.');
        disp(e.message);
    end
    
    % Clean up
    zmq.core.close(socket);
    zmq.core.ctx_shutdown(context);
    zmq.core.ctx_term(context);
end