#include <iostream>
#include <vector>
#include <cuda_runtime.h>
#include <chrono>
#include <ctime>
#include <iomanip>

int memtest(void* d_mem, int pattern, size_t allocSize);

int main(int argc, char* argv[]) {
    int iterations = 1;

    // Parse -t option
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-t") == 0 && i + 1 < argc) {
            iterations = std::atoi(argv[i + 1]);
            ++i;
        }
    }

    size_t totalMem = 0, freeMem = 0;
    cudaMemGetInfo(&freeMem, &totalMem);

    std::cout << "Total GPU memory: " << (totalMem / (1024 * 1024)) << " MB\n";
    std::cout << "Free GPU memory : " << (freeMem / (1024 * 1024)) << " MB\n";

    // Leave some room for overhead
    size_t allocSize = freeMem - (50 * 1024 * 1024); // Leave 50MB free

    std::cout << "Trying to allocate: " << (allocSize / (1024 * 1024)) << " MB\n";

    unsigned char* d_mem = nullptr;
    cudaError_t err = cudaMalloc((void**)&d_mem, allocSize);
    if (err != cudaSuccess) {
        std::cerr << "cudaMalloc failed: " << cudaGetErrorString(err) << "\n";
        return 1;
    }

    for (int iter = 0; iter < iterations; ++iter) {
        auto now = std::chrono::system_clock::now();
        std::time_t now_c = std::chrono::system_clock::to_time_t(now);
        std::tm local_tm = *std::localtime(&now_c);

        std::cout << "\n--- Iteration " << iter + 1 << " ---\n";
        std::cout << "Time: "
            << std::put_time(&local_tm, "%Y-%m-%d %H:%M:%S") << "\n";

        // Fill VRAM with 0xFF
        std::cout << "Test pattern: 0xff\n";
        memtest(d_mem, 0xFF, allocSize);
        std::cout << "Test pattern: 0x00\n";
        memtest(d_mem, 0x00, allocSize);
        std::cout << "Test pattern: 0xaa\n";
        memtest(d_mem, 0xAA, allocSize);
        std::cout << "Test pattern: 0x55\n";
        memtest(d_mem, 0x55, allocSize);
    }
    // Clean up
    cudaFree(d_mem);
    return 0;
}

int memtest(void * d_mem, int pattern, size_t allocSize) {

    cudaError_t err = cudaMemset(d_mem, pattern, allocSize);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemset failed: " << cudaGetErrorString(err) << "\n";
        cudaFree(d_mem);
        return 1;
    }

    // Allocate host memory to read back
    unsigned char* h_mem = (unsigned char*)malloc(allocSize);
    if (!h_mem) {
        std::cerr << "Host malloc failed.\n";
        cudaFree(d_mem);
        return 1;
    }

    // Copy from device to host
    err = cudaMemcpy(h_mem, d_mem, allocSize, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemcpy failed: " << cudaGetErrorString(err) << "\n";
        free(h_mem);
        cudaFree(d_mem);
        return 1;
    }

    // Check for mismatches
    size_t errors = 0;
    for (size_t i = 0; i < allocSize; ++i) {
        if (h_mem[i] != pattern) {
            if (++errors < 10) { // Show first few errors
                std::cout << "Mismatch at byte " << i << ": "
                    << static_cast<int>(h_mem[i]) << " != 0x" << std::hex << pattern << "\n";
            }
        }
    }

    if (errors == 0) {
        std::cout << "VRAM test passed: all bytes match 0x" << std::hex << pattern << "\n";
    }
    else {
        std::cout << "VRAM test failed: " << errors << " mismatches found.\n";
    }
    free(h_mem);
    
    return 0;
}
