#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <signal.h>
#include <atomic>
#include <vector>
#include <random>
#include <nlohmann/json.hpp>
#include "cs104_slave.h"
#include "cs101_information_objects.h"
#include "hal_thread.h"

using json = nlohmann::json;

std::atomic<bool> g_running{true};

struct DataPoint {
    int address;
    std::string name;
    float base_value;
    float variation;
    std::string unit;
    float current_value;
};

struct Config {
    int port = 2404;
    std::vector<DataPoint> data_points;
};

void signalHandler(int signal) {
    g_running = false;
}

Config loadConfig(const std::string& path) {
    Config config;
    try {
        std::ifstream file(path);
        if (file.is_open()) {
            json j;
            file >> j;
            if (j.contains("server") && j["server"].contains("port")) 
                config.port = j["server"]["port"];
            if (j.contains("dataPoints")) {
                for (auto& dp : j["dataPoints"]) {
                    DataPoint point;
                    point.address = dp["address"];
                    point.name = dp["name"];
                    point.base_value = dp["baseValue"];
                    point.variation = dp["variation"];
                    point.unit = dp.value("unit", "");
                    point.current_value = point.base_value;
                    config.data_points.push_back(point);
                }
            }
        }
    } catch (...) {}
    return config;
}

float generateValue(float base, float variation) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_real_distribution<> dis(-variation, variation);
    return base + dis(gen);
}

bool interrogationHandler(void* parameter, IMasterConnection connection, CS101_ASDU asdu, uint8_t qoi) {
    std::cout << "[INFO] Interrogation request received, QOI=" << (int)qoi << std::endl;
    
    if (qoi != 20) {
        IMasterConnection_sendACT_CON(connection, asdu, true);
        return true;
    }
    
    Config* config = (Config*)parameter;
    CS101_AppLayerParameters alParams = IMasterConnection_getApplicationLayerParameters(connection);
    
    IMasterConnection_sendACT_CON(connection, asdu, false);
    
    CS101_ASDU newAsdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION, 0, 1, false, false);
    
    for (auto& dp : config->data_points) {
        InformationObject io = (InformationObject)MeasuredValueScaled_create(NULL, dp.address, (int)dp.current_value, IEC60870_QUALITY_GOOD);
        CS101_ASDU_addInformationObject(newAsdu, io);
        InformationObject_destroy(io);
    }
    
    IMasterConnection_sendASDU(connection, newAsdu);
    CS101_ASDU_destroy(newAsdu);
    
    IMasterConnection_sendACT_TERM(connection, asdu);
    
    std::cout << "[INFO] Sent " << config->data_points.size() << " data points" << std::endl;
    return true;
}

void connectionEventHandler(void* parameter, IMasterConnection connection, CS104_PeerConnectionEvent event) {
    if (event == CS104_CON_EVENT_CONNECTION_OPENED) {
        std::cout << "[INFO] Client connected" << std::endl;
    } else if (event == CS104_CON_EVENT_CONNECTION_CLOSED) {
        std::cout << "[INFO] Client disconnected" << std::endl;
    } else if (event == CS104_CON_EVENT_ACTIVATED) {
        std::cout << "[INFO] Connection activated" << std::endl;
    } else if (event == CS104_CON_EVENT_DEACTIVATED) {
        std::cout << "[INFO] Connection deactivated" << std::endl;
    }
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    std::cout << "[INFO] IEC104 Simulator (lib60870) starting..." << std::endl;
    
    Config config = loadConfig(argc > 1 ? argv[1] : "/tmp/simulator.json");
    std::cout << "[INFO] Port: " << config.port << ", Data Points: " << config.data_points.size() << std::endl;
    
    CS104_Slave slave = CS104_Slave_create(10, 10);
    CS104_Slave_setLocalPort(slave, config.port);
    CS104_Slave_setInterrogationHandler(slave, interrogationHandler, &config);
    CS104_Slave_setConnectionEventHandler(slave, connectionEventHandler, &config);
    CS104_Slave_start(slave);
    
    if (!CS104_Slave_isRunning(slave)) {
        std::cerr << "[ERROR] Failed to start server" << std::endl;
        CS104_Slave_destroy(slave);
        return 1;
    }
    
    std::cout << "[INFO] IEC104 server started on port " << config.port << std::endl;
    
    int counter = 0;
    while (g_running) {
        Thread_sleep(5000);
        counter++;
        
        for (auto& dp : config.data_points) {
            dp.current_value = generateValue(dp.base_value, dp.variation);
        }
        
        if (counter % 2 == 0) {
            std::cout << "[INFO] Updated data (cycle " << counter << ")" << std::endl;
            for (size_t i = 0; i < std::min(size_t(2), config.data_points.size()); i++) {
                std::cout << "[DATA] " << config.data_points[i].name << " = " 
                         << config.data_points[i].current_value << " " 
                         << config.data_points[i].unit << std::endl;
            }
        }
    }
    
    CS104_Slave_stop(slave);
    CS104_Slave_destroy(slave);
    std::cout << "[INFO] IEC104 Simulator stopped" << std::endl;
    return 0;
}
