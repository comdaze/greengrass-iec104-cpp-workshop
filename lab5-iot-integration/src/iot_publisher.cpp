#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <signal.h>
#include <atomic>
#include <queue>
#include <mutex>
#include <nlohmann/json.hpp>
#include <aws/crt/Api.h>
#include <aws/greengrass/GreengrassCoreIpcClient.h>

using namespace Aws::Crt;
using namespace Aws::Greengrass;
using json = nlohmann::json;

std::atomic<bool> g_running{true};
std::queue<std::string> g_messageQueue;
std::mutex g_queueMutex;

void signalHandler(int signal) {
    g_running = false;
}

class SubscribeHandler : public SubscribeToTopicStreamHandler {
public:
    void OnStreamEvent(SubscriptionResponseMessage *response) override {
        auto binaryMessage = response->GetBinaryMessage();
        if (binaryMessage.has_value() && binaryMessage.value().GetMessage().has_value()) {
            auto messageBytes = binaryMessage.value().GetMessage().value();
            std::string payload(messageBytes.begin(), messageBytes.end());
            
            std::cout << "[INFO] Received IPC message" << std::endl;
            
            std::lock_guard<std::mutex> lock(g_queueMutex);
            g_messageQueue.push(payload);
        }
    }
    
    bool OnStreamError(OperationError *error) override {
        std::cerr << "[ERROR] Stream error" << std::endl;
        return false;
    }
    
    void OnStreamClosed() override {
        std::cout << "[INFO] Stream closed" << std::endl;
    }
};

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    std::cout << "[INFO] IoT Publisher starting..." << std::endl;
    
    std::string ipcTopic = "iec104/data";
    std::string iotTopic = "wind-farm/data";
    
    if (argc > 1) {
        try {
            std::ifstream file(argv[1]);
            json config;
            file >> config;
            if (config.contains("ipcTopic")) ipcTopic = config["ipcTopic"];
            if (config.contains("iotTopic")) iotTopic = config["iotTopic"];
        } catch (...) {}
    }
    
    ApiHandle apiHandle(g_allocator);
    Io::EventLoopGroup eventLoopGroup(1);
    Io::DefaultHostResolver socketResolver(eventLoopGroup, 64, 30);
    Io::ClientBootstrap bootstrap(eventLoopGroup, socketResolver);
    
    GreengrassCoreIpcClient ipcClient(bootstrap);
    
    class LifecycleHandler : public ConnectionLifecycleHandler {
        void OnConnectCallback() override { std::cout << "[INFO] IPC Connected" << std::endl; }
        void OnDisconnectCallback(RpcError error) override {}
        bool OnErrorCallback(RpcError error) override { return true; }
    };
    
    LifecycleHandler lifecycleHandler;
    auto connectionStatus = ipcClient.Connect(lifecycleHandler).get();
    if (!connectionStatus) {
        std::cerr << "[ERROR] Failed to connect to IPC" << std::endl;
        return 1;
    }
    
    // Subscribe to IPC topic
    SubscribeToTopicRequest request;
    request.SetTopic(ipcTopic.c_str());
    
    auto streamHandler = MakeShared<SubscribeHandler>(DefaultAllocator());
    auto operation = ipcClient.NewSubscribeToTopic(streamHandler);
    auto activate = operation->Activate(request, nullptr).get();
    if (!activate) {
        std::cerr << "[ERROR] Subscribe activate failed" << std::endl;
        return 1;
    }
    
    auto responseFuture = operation->GetResult();
    if (responseFuture.wait_for(std::chrono::seconds(10)) == std::future_status::timeout) {
        std::cerr << "[ERROR] Subscribe timeout" << std::endl;
        return 1;
    }
    
    auto response = responseFuture.get();
    if (!response) {
        std::cerr << "[ERROR] Subscribe failed" << std::endl;
        return 1;
    }
    
    std::cout << "[INFO] Subscribed to IPC topic: " << ipcTopic << std::endl;
    std::cout << "[INFO] Will publish to IoT Core topic: " << iotTopic << std::endl;
    
    // Main loop - publish messages from queue
    while (g_running) {
        std::string payload;
        {
            std::lock_guard<std::mutex> lock(g_queueMutex);
            if (!g_messageQueue.empty()) {
                payload = g_messageQueue.front();
                g_messageQueue.pop();
            }
        }
        
        if (!payload.empty()) {
            std::cout << "[INFO] Publishing to IoT Core..." << std::endl;
            
            PublishToIoTCoreRequest pubRequest;
            pubRequest.SetTopicName(iotTopic.c_str());
            pubRequest.SetQos(QOS_AT_LEAST_ONCE);
            Vector<uint8_t> payloadBytes(payload.begin(), payload.end());
            pubRequest.SetPayload(payloadBytes);
            
            auto pubOperation = ipcClient.NewPublishToIoTCore();
            auto pubActivate = pubOperation->Activate(pubRequest, nullptr).get();
            if (!pubActivate) {
                std::cerr << "[ERROR] Publish activate failed: " << pubActivate.StatusToString() << std::endl;
                continue;
            }
            
            auto pubResultFuture = pubOperation->GetResult();
            if (pubResultFuture.wait_for(std::chrono::seconds(5)) == std::future_status::timeout) {
                std::cerr << "[ERROR] Publish timeout" << std::endl;
            } else {
                auto pubResult = pubResultFuture.get();
                if (pubResult) {
                    std::cout << "[INFO] Published to IoT Core: " << iotTopic << std::endl;
                } else {
                    auto errorType = pubResult.GetResultType();
                    if (errorType == OPERATION_ERROR) {
                        auto *error = pubResult.GetOperationError();
                        if (error && error->GetMessage().has_value()) {
                            std::cerr << "[ERROR] IoT Core error: " << error->GetMessage().value() << std::endl;
                        }
                    } else {
                        std::cerr << "[ERROR] RPC error: " << pubResult.GetRpcError().StatusToString() << std::endl;
                    }
                }
            }
        }
        
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    operation->Close();
    std::cout << "[INFO] IoT Publisher stopped" << std::endl;
    return 0;
}
