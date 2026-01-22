#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <signal.h>
#include <atomic>
#include <iomanip>
#include <sstream>
#include <ctime>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

std::atomic<bool> g_running{true};

enum class LogLevel { DEBUG, INFO, WARN, ERROR };

class Logger {
private:
    LogLevel level_;
    bool console_enabled_;
    bool file_enabled_;
    std::string log_file_;
    std::ofstream file_stream_;

    std::string levelToString(LogLevel level) {
        switch(level) {
            case LogLevel::DEBUG: return "DEBUG";
            case LogLevel::INFO:  return "INFO";
            case LogLevel::WARN:  return "WARN";
            case LogLevel::ERROR: return "ERROR";
            default: return "UNKNOWN";
        }
    }

    std::string getTimestamp() {
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S");
        return ss.str();
    }

public:
    Logger(LogLevel level = LogLevel::INFO, bool console = true, bool file = false, const std::string& path = "")
        : level_(level), console_enabled_(console), file_enabled_(file), log_file_(path) {
        if (file_enabled_ && !log_file_.empty()) {
            file_stream_.open(log_file_, std::ios::app);
        }
    }

    ~Logger() {
        if (file_stream_.is_open()) {
            file_stream_.close();
        }
    }

    void log(LogLevel level, const std::string& message) {
        if (level < level_) return;

        std::string log_line = "[" + getTimestamp() + "] [" + levelToString(level) + "] " + message;

        if (console_enabled_) {
            std::cout << log_line << std::endl;
        }

        if (file_enabled_ && file_stream_.is_open()) {
            file_stream_ << log_line << std::endl;
            file_stream_.flush();
        }
    }

    void debug(const std::string& msg) { log(LogLevel::DEBUG, msg); }
    void info(const std::string& msg) { log(LogLevel::INFO, msg); }
    void warn(const std::string& msg) { log(LogLevel::WARN, msg); }
    void error(const std::string& msg) { log(LogLevel::ERROR, msg); }
};

struct Config {
    std::string message = "Hello from Lab 2!";
    int interval = 5;
    std::string log_level = "INFO";
    bool log_to_console = true;
    bool log_to_file = false;
    std::string log_file_path = "/tmp/lab2.log";
    int counter_threshold = 10;
};

LogLevel parseLogLevel(const std::string& level) {
    if (level == "DEBUG") return LogLevel::DEBUG;
    if (level == "WARN") return LogLevel::WARN;
    if (level == "ERROR") return LogLevel::ERROR;
    return LogLevel::INFO;
}

Config loadConfig(const std::string& configPath, Logger& logger) {
    Config config;
    
    try {
        std::ifstream file(configPath);
        if (file.is_open()) {
            json j;
            file >> j;
            
            if (j.contains("message")) config.message = j["message"];
            if (j.contains("interval")) config.interval = j["interval"];
            if (j.contains("logLevel")) config.log_level = j["logLevel"];
            if (j.contains("logToConsole")) config.log_to_console = j["logToConsole"];
            if (j.contains("logToFile")) config.log_to_file = j["logToFile"];
            if (j.contains("logFilePath")) config.log_file_path = j["logFilePath"];
            if (j.contains("counterThreshold")) config.counter_threshold = j["counterThreshold"];
            
            logger.info("Configuration loaded from " + configPath);
        }
    } catch (const std::exception& e) {
        logger.error("Failed to load config: " + std::string(e.what()));
        logger.info("Using default configuration");
    }
    
    return config;
}

void signalHandler(int signal) {
    std::cout << "\n[INFO] Received signal " << signal << ", shutting down..." << std::endl;
    g_running = false;
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    Logger logger(LogLevel::INFO, true, false);
    logger.info("Lab2 ConfigDemo component starting...");
    
    std::string configPath = "/tmp/config.json";
    if (argc > 1) {
        configPath = argv[1];
    }
    
    Config config = loadConfig(configPath, logger);
    
    Logger mainLogger(
        parseLogLevel(config.log_level),
        config.log_to_console,
        config.log_to_file,
        config.log_file_path
    );
    
    mainLogger.info("=== Configuration ===");
    mainLogger.info("Message: " + config.message);
    mainLogger.info("Interval: " + std::to_string(config.interval) + " seconds");
    mainLogger.info("Log Level: " + config.log_level);
    mainLogger.info("Log to Console: " + std::string(config.log_to_console ? "true" : "false"));
    mainLogger.info("Log to File: " + std::string(config.log_to_file ? "true" : "false"));
    if (config.log_to_file) {
        mainLogger.info("Log File: " + config.log_file_path);
    }
    mainLogger.info("Counter Threshold: " + std::to_string(config.counter_threshold));
    mainLogger.info("====================");
    
    int counter = 0;
    while (g_running) {
        counter++;
        
        mainLogger.debug("Debug: Loop iteration " + std::to_string(counter));
        mainLogger.info(config.message);
        mainLogger.info("Counter: " + std::to_string(counter) + "/" + std::to_string(config.counter_threshold));
        
        if (counter >= config.counter_threshold) {
            mainLogger.warn("Counter threshold reached! Resetting counter.");
            counter = 0;
        }
        
        if (counter % 3 == 0) {
            mainLogger.debug("Counter is divisible by 3");
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(config.interval));
    }
    
    mainLogger.info("Lab2 ConfigDemo component stopped");
    return 0;
}
