import zmq
import time
import threading
import statistics
import argparse
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class BenchmarkResult:
    chunk_size: int
    num_frames: int
    latency_ms: float
    throughput_mbps: float


def start_server(port: int) -> threading.Thread:
    """Starts a ZeroMQ server in a separate thread that echoes back received messages."""
    def _server_thread():
        context = zmq.Context()
        socket = context.socket(zmq.REP)
        socket.bind(f"tcp://*:{port}")
        
        print("Server started and listening...")
        try:
            while True:
                frames = socket.recv_multipart()
                socket.send_multipart(frames)  # Echo back the same frames
        except zmq.error.ContextTerminated:
            print("Server shutting down...")
    
    thread = threading.Thread(target=_server_thread, daemon=True)
    thread.start()
    return thread


def run_client_test(port: int, header: bytes, data: bytes, chunk_size: int) -> BenchmarkResult:
    """Runs a client test with the specified frame sizes and returns performance metrics."""
    context = zmq.Context()
    socket = context.socket(zmq.REQ)
    socket.connect(f"tcp://localhost:{port}")
    
    # Split the data into chunks of the specified size
    chunks = []
    for i in range(0, len(data), chunk_size):
        chunks.append(data[i:i + chunk_size])
    
    # Create frames
    frames = [header] + chunks
    num_frames = len(frames)
    total_bytes = sum(len(frame) for frame in frames)
    
    # Warm-up round
    socket.send_multipart(frames)
    socket.recv_multipart()
    
    # Test round
    start_time = time.time()
    socket.send_multipart(frames)
    socket.recv_multipart()
    end_time = time.time()
    
    elapsed_time = end_time - start_time
    latency_ms = elapsed_time * 1000
    throughput_mbps = (total_bytes * 8 / 1000000) / elapsed_time
    
    socket.close()
    
    return BenchmarkResult(
        chunk_size=chunk_size,
        num_frames=num_frames,
        latency_ms=latency_ms,
        throughput_mbps=throughput_mbps
    )


def run_benchmark(port: int, header_size: int, data_size: int, chunk_sizes: List[int], num_runs: int = 3) -> List[BenchmarkResult]:
    """Run benchmarks for different chunk sizes with multiple runs per size."""
    header = b"H" * header_size
    data = b"D" * data_size
    
    results = []
    
    for chunk_size in chunk_sizes:
        print(f"\nBenchmarking chunk size: {chunk_size} bytes")
        run_results = []
        
        for i in range(num_runs):
            result = run_client_test(port, header, data, chunk_size)
            run_results.append(result)
            print(f"  Run {i+1}: Latency={result.latency_ms:.2f}ms, Throughput={result.throughput_mbps:.2f}Mbps")
            time.sleep(0.5)  # Brief pause between runs
        
        # Average the results
        avg_latency = statistics.mean(r.latency_ms for r in run_results)
        avg_throughput = statistics.mean(r.throughput_mbps for r in run_results)
        
        results.append(BenchmarkResult(
            chunk_size=chunk_size,
            num_frames=run_results[0].num_frames,
            latency_ms=avg_latency,
            throughput_mbps=avg_throughput
        ))
        
    return results


def main():
    parser = argparse.ArgumentParser(description="ZeroMQ Frame Size Benchmark")
    parser.add_argument("--port", type=int, default=5555, help="ZeroMQ port")
    parser.add_argument("--header-size", type=int, default=100, help="Size of the header in bytes")
    parser.add_argument("--data-size", type=int, default=500000, help="Size of the binary data in bytes")
    parser.add_argument("--runs", type=int, default=5, help="Number of test runs per chunk size")
    args = parser.parse_args()
    
    # Test various chunk sizes
    chunk_sizes = [
        1024,       # 1KB
        8192,       # 8KB
        16384,      # 16KB
        32768,      # 32KB
        65536,      # 64KB
        131072,     # 128KB
        262144,     # 256KB
        524288,     # 512KB (single frame for data)
    ]
    
    # Start server
    server_thread = start_server(args.port)
    time.sleep(1)  # Give server time to start
    
    print(f"Starting benchmark with {args.header_size} byte header and {args.data_size/1000:.1f}KB data")
    print(f"Running {args.runs} tests per chunk size")
    
    try:
        results = run_benchmark(args.port, args.header_size, args.data_size, chunk_sizes, args.runs)
        
        # Print results table
        print("\n=== BENCHMARK RESULTS ===")
        print(f"{'Chunk Size (bytes)':<20} {'# Frames':<10} {'Avg Latency (ms)':<20} {'Avg Throughput (Mbps)':<20}")
        print("-" * 70)
        
        for result in results:
            print(f"{result.chunk_size:<20} {result.num_frames:<10} {result.latency_ms:<20.2f} {result.throughput_mbps:<20.2f}")
            
        # Find best results
        min_latency = min(results, key=lambda x: x.latency_ms)
        max_throughput = max(results, key=lambda x: x.throughput_mbps)
        
        print("\n=== SUMMARY ===")
        print(f"Lowest latency: {min_latency.chunk_size} bytes ({min_latency.latency_ms:.2f}ms)")
        print(f"Highest throughput: {max_throughput.chunk_size} bytes ({max_throughput.throughput_mbps:.2f}Mbps)")
        
    finally:
        # Clean up
        zmq.Context.instance().term()
        time.sleep(0.5)  # Give server time to shut down

if __name__ == "__main__":
    main()