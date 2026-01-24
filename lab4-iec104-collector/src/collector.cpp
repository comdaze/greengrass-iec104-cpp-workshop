#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <signal.h>
#include <atomic>
#include <nlohmann/json.hpp>
#include <aws/crt/Api.h>
#include <aws/greengrass/GreengrassCoreIpcClient.h>
#include "cs104_connection.h"
#include "cs101_information_objects.h"

using namespace Aws::Crt;
using namespace Aws::Greengrass;
using namespace Aws::Eventstreamrpc;
using json = nlohmann::json;

std::atomic<bool> g_running{true};
json g_data = json::array();

struct Config {
    std::string server_host = "127.0.0.1";
    int server_port = 2404;
    std::string ipc_topic = "iec104/data";
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
            if (j.contains("serverHost")) config.server_host = j["serverHost"];
            if (j.contains("serverPort")) config.server_port = j["serverPort"];
            if (j.contains("ipcTopic")) config.ipc_topic = j["ipcTopic"];
        }
    } catch (...) {}
    return config;
}

bool asduReceivedHandler(void* parameter, int address, CS101_ASDU asdu) {
    int typeId = CS101_ASDU_getTypeID(asdu);
    std::cout << "[DEBUG] Received ASDU, TypeID=" << typeId << ", elements=" << CS101_ASDU_getNumberOfElements(asdu) << std::endl;
    
    if (typeId == M_ME_NB_1) {  // MeasuredValueScaled
        int numElements = CS101_ASDU_getNumberOfElements(asdu);
        for (int i = 0; i < numElements; i++) {
            MeasuredValueScaled io = (MeasuredValueScaled)CS101_ASDU_getElement(asdu, i);
            int ioa = InformationObject_getObjectAddress((InformationObject)io);
            int scaledValue = MeasuredValueScaled_getValue(io);
            float value = (float)scaledValue;
            
            std::cout << "[DEBUG] IOA=" << ioa << ", value=" << value << std::endl;
            
            std::string name, unit;
            if (ioa == 1001) { name = "wind_turbine_1_active_power"; unit = "kW"; }
            else if (ioa == 2001) { name = "energy_storage_soc"; unit = "%"; }
            else continue;
            
            g_data.push_back({
                {"address", ioa},
                {"name", name},
                {"value", value},
                {"unit", unit},
                {"timestamp", std::time(nullptr)}
            });
        }
    }
    return true;
}

bool publishToIPC(GreengrassCoreIpcClient& ipcClient, const std::string& topic, const json& data) {
    try {
        PublishToTopicRequest request;
        request.SetTopic(topic.c_str());
        
        BinaryMessage binaryMessage;
        std::string payload = data.dump();
        Vector<uint8_t> payloadBytes(payload.begin(), payload.end());
        binaryMessage.SetMessage(payloadBytes);
        
        PublishMessage message;
        message.SetBinaryMessage(binaryMessage);
        request.SetPublishMessage(message);
        
        auto operation = ipcClient.NewPublishToTopic();
        auto activate = operation->Activate(request, nullptr);
        activate.wait();
        
        auto responseFuture = operation->GetResult();
        if (responseFuture.wait_for(std::chrono::seconds(5)) == std::future_status::timeout) {
            std::cerr << "[ERROR] IPC publish timeout" << std::endl;
            return false;
        }
        
        auto response = responseFuture.get();
        if (!response) {
            auto errorType = response.GetResultType();
            if (errorType == OPERATION_ERROR) {
                auto *error = response.GetOperationError();
                if (error && error->GetMessage().has_value()) {
                    std::cerr << "[ERROR] IPC operation error: " << error->GetMessage().value() << std::endl;
                } else {
                    std::cerr << "[ERROR] IPC operation error (no message)" << std::endl;
                }
            } else {
                std::cerr << "[ERROR] IPC RPC error: " << response.GetRpcError().StatusToString() << std::endl;
            }
            return false;
        }
        
        std::cout << "[INFO] Published " << data.size() << " data points to IPC topic: " << topic << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[ERROR] IPC publish exception: " << e.what() << std::endl;
        return false;
    }
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    std::cout << "[INFO] IEC104 Collector (lib60870) starting..." << std::endl;
    
    Config config = loadConfig(argc > 1 ? argv[1] : "/tmp/collector-config.json");
    
    // 检查是否在 Greengrass 环境中运行
    const char* ipcSocket = std::getenv("AWS_GG_NUCLEUS_DOMAIN_SOCKET_FILEPATH_FOR_COMPONENT");
    bool isGreengrassEnv = (ipcSocket != nullptr);
    
    std::cout << "[INFO] Running mode: " << (isGreengrassEnv ? "Greengrass" : "Local Test") << std::endl;
    
    ApiHandle apiHandle(g_allocator);
    Io::EventLoopGroup eventLoopGroup(1);
    Io::DefaultHostResolver defaultHostResolver(eventLoopGroup, 64, 30);
    Io::ClientBootstrap clientBootstrap(eventLoopGroup, defaultHostResolver);
    
    GreengrassCoreIpcClient* ipcClient = nullptr;
    
    if (isGreengrassEnv) {
        ipcClient = new GreengrassCoreIpcClient(clientBootstrap);
        
        class MyLifecycleHandler : public ConnectionLifecycleHandler {
            void OnConnectCallback() override { std::cout << "[INFO] IPC Connected" << std::endl; }
            void OnDisconnectCallback(RpcError error) override {}
            bool OnErrorCallback(RpcError error) override { return true; }
        };
        
        MyLifecycleHandler lifecycleHandler;
        auto connectionStatus = ipcClient->Connect(lifecycleHandler).get();
        if (!connectionStatus) {
            std::cerr << "[ERROR] Failed to connect to IPC: " << connectionStatus.StatusToString() << std::endl;
            delete ipcClient;
            return 1;
        }
        std::cout << "[INFO] Connected to Greengrass IPC" << std::endl;
    } else {
        std::cout << "[INFO] Local test mode - IPC disabled, data will be saved to /tmp/iec104-data.json" << std::endl;
    }
    
    CS104_Connection connection = CS104_Connection_create(config.server_host.c_str(), config.server_port);
    CS104_Connection_setASDUReceivedHandler(connection, asduReceivedHandler, NULL);
    
    while (g_running) {
        if (CS104_Connection_connect(connection)) {
            std::cout << "[INFO] Connected to IEC104 server " << config.server_host << ":" << config.server_port << std::endl;
            
            CS104_Connection_sendStartDT(connection);
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            
            std::cout << "[INFO] Sending interrogation command..." << std::endl;
            CS104_Connection_sendInterrogationCommand(connection, CS101_COT_ACTIVATION, 1, IEC60870_QOI_STATION);
            
            std::cout << "[INFO] Entering data collection loop..." << std::endl;
            for (int i = 0; i < 60 && g_running; i++) {
                std::this_thread::sleep_for(std::chrono::seconds(1));
                
                if (i % 5 == 0 && i > 0) {
                    std::cout << "[INFO] Cycle " << i << ", data points: " << g_data.size() << std::endl;
                    if (!g_data.empty()) {
                        // 发布到 IPC (仅在 Greengrass 环境)
                        if (ipcClient) {
                            publishToIPC(*ipcClient, config.ipc_topic, g_data);
                        }
                        
                        // 保存到本地文件 (本地测试和 Greengrass 都保存)
                        std::ofstream file("/tmp/iec104-data.json");
                        file << g_data.dump(2);
                        file.close();
                        
                        std::cout << "[INFO] Saved " << g_data.size() << " data points to /tmp/iec104-data.json" << std::endl;
                        g_data.clear();
                    }
                    std::cout << "[INFO] Sending interrogation command..." << std::endl;
                    CS104_Connection_sendInterrogationCommand(connection, CS101_COT_ACTIVATION, 1, IEC60870_QOI_STATION);
                }
            }
            
            std::cout << "[INFO] Exiting data collection loop" << std::endl;
            CS104_Connection_close(connection);
        } else {
            std::cerr << "[ERROR] Failed to connect" << std::endl;
        }
        
        if (g_running) {
            std::cout << "[WARN] Connection lost, reconnecting..." << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(5));
        }
    }
    
    CS104_Connection_destroy(connection);
    
    if (ipcClient) {
        delete ipcClient;
    }
    
    std::cout << "[INFO] IEC104 Collector stopped" << std::endl;
    return 0;
}
