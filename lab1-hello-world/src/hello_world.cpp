#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <signal.h>
#include <atomic>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

std::atomic<bool> g_running{true};

void signalHandler(int signal) {
    std::cout << "[INFO] Received signal " << signal << ", shutting down..." << std::endl;
    g_running = false;
}

struct Config {
    std::string message = "Hello from Greengrass!";
    int interval = 5;
};

Config loadConfig(const std::string& configPath) {
    Config config;
    
    try {
        std::ifstream file(configPath);
        if (file.is_open()) {
            json j;
            file >> j;
            
            if (j.contains("message")) {
                config.message = j["message"].get<std::string>();
            }
            if (j.contains("interval")) {
                config.interval = j["interval"].get<int>();
            }
            
            std::cout << "[INFO] Loaded configuration from " << configPath << std::endl;
        }
    } catch (const std::exception& e) {
        std::cerr << "[WARN] Failed to load config: " << e.what() << std::endl;
        std::cout << "[INFO] Using default configuration" << std::endl;
    }
    
    return config;
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    std::cout << "[INFO] HelloWorld component starting..." << std::endl;
    
    // 加载配置
    std::string configPath = "/tmp/config.json";
    if (argc > 1) {
        configPath = argv[1];
    }
    
    Config config = loadConfig(configPath);
    
    std::cout << "[INFO] Configuration:" << std::endl;
    std::cout << "[INFO]   Message: " << config.message << std::endl;
    std::cout << "[INFO]   Interval: " << config.interval << " seconds" << std::endl;
    
    int counter = 0;
    while (g_running) {
        std::cout << "[INFO] " << config.message << std::endl;
        std::cout << "[INFO] Component running for " << (++counter * config.interval) << " seconds" << std::endl;
        
        std::this_thread::sleep_for(std::chrono::seconds(config.interval));
    }
    
    std::cout << "[INFO] HelloWorld component stopped" << std::endl;
    return 0;
}
